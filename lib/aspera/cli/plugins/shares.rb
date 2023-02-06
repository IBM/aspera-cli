# frozen_string_literal: true

require 'aspera/cli/plugins/node'

module Aspera
  module Cli
    module Plugins
      class Shares < Aspera::Cli::BasicAuthPlugin
        class << self
          def detect(base_url)
            api = Rest.new({base_url: base_url})
            # Shares
            begin
              # shall fail: shares requires auth, but we check error message
              # TODO: use ping instead ?
              api.read('node_api/app')
            rescue RestCallError => e
              if e.response.code.to_s.eql?('401') && e.response.body.eql?('{"error":{"user_message":"API user authentication failed"}}')
                return {version: 'unknown'}
              end
            end
            nil
          end
        end

        def initialize(env)
          super(env)
          options.add_opt_list(:user_type, %i[any local ldap saml], 'Type of user for user operations')
          options.set_option(:user_type, :any)
          options.parse_options!
        end

        SAML_IMPORT_MANDATORY = %w[id name_id].freeze
        SAML_IMPORT_ALLOWED = %w[email given_name surname].concat(SAML_IMPORT_MANDATORY).freeze

        ACTIONS = %i[health repository admin].freeze

        def execute_action
          command = options.get_next_command(ACTIONS)
          case command
          when :health
            nagios = Nagios.new
            begin
              Rest
                .new(base_url: options.get_option(:url, is_type: :mandatory) + '/node_api')
                .call(
                  operation: 'GET',
                  subpath: 'ping',
                  headers: {'content-type': 'application/json'},
                  return_error: true)
              nagios.add_ok('shares api', 'accessible')
            rescue StandardError => e
              nagios.add_critical('node api', e.to_s)
            end
            return nagios.result
          when :repository
            api_shares_node = basic_auth_api('node_api')
            command = options.get_next_command(Node::COMMANDS_SHARES)
            case command
            when *Node::COMMANDS_SHARES then Node.new(@agents.merge(skip_basic_auth_options: true, node_api: api_shares_node)).execute_action(command)
            else raise "INTERNAL ERROR, unknown command: [#{command}]"
            end
          when :admin
            api_shares_admin = basic_auth_api('api/v1')
            users_type = options.get_option(:user_type, is_type: :mandatory)
            users_path = "data/#{users_type}_users"
            users_actions = nil
            case users_type
            when :any
              users_path = 'data/users'
              users_actions = %i[list show delete share_permissions app_authorizations].freeze
            when :local
              users_actions = %i[list show create modify delete].freeze
            when :ldap
              users_actions = %i[add].freeze
            when :saml
              users_actions = %i[import].freeze
            end
            command = options.get_next_command(%i[user share])
            case command
            when :user
              command = options.get_next_command(users_actions)
              user_id = instance_identifier if %i[app_authorizations share_permissions].include?(command)
              case command
              when :list, :show, :create, :delete, :modify
                return entity_command(command, api_shares_admin, users_path, display_fields: %w[id username email directory_user urn])
              when :app_authorizations
                case options.get_next_command(%i[modify show])
                when :show
                  return {type: :single_object, data: api_shares_admin.read("data/users/#{user_id}/app_authorizations")[:data]}
                when :modify
                  parameters = options.get_option(:value, is_type: :mandatory)
                  return {type: :single_object, data: api_shares_admin.update("data/users/#{user_id}/app_authorizations", parameters)[:data]}
                end
              when :share_permissions
                case options.get_next_command(%i[list show])
                when :list
                  return {type: :object_list, data: api_shares_admin.read("data/users/#{user_id}/share_permissions")[:data]}
                when :show
                  return {type: :single_object, data: api_shares_admin.read("data/users/#{user_id}/share_permissions/#{instance_identifier}")[:data]}
                end
              when :import
                parameters = options.get_option(:value, is_type: :mandatory)
                return do_bulk_operation(parameters, 'created') do |user_params|
                  user_params = user_params.transform_keys{|k|k.gsub(/\s+/, '_').downcase}
                  raise 'expecting Hash' unless user_params.is_a?(Hash)
                  SAML_IMPORT_MANDATORY.each{|p|raise "missing mandatory field: #{p}" if user_params[p].nil?}
                  user_params.each_key do |p|
                    raise "unsupported field: #{p}, use: #{SAML_IMPORT_ALLOWED.join(',')}" unless SAML_IMPORT_ALLOWED.include?(p)
                  end
                  api_shares_admin.create('data/saml_users/import', user_params)[:data]
                end
              when :add
                parameters = options.get_option(:value)
                return do_bulk_operation(parameters, 'created') do |user_name|
                  raise "expecting string (user name), have #{user_name.class}" unless user_name.is_a?(String)
                  api_shares_admin.create('data/ldap_users', {'user'=>user_name})[:data]
                end
              end
            when :share
              command = options.get_next_command(%i[user_permissions group_permissions].concat(Plugin::ALL_OPS))
              # all_shares = api_shares_admin.read('data/shares')[:data]
              case command
              when *Plugin::ALL_OPS
                return entity_command(command, api_shares_admin, 'data/shares')
                # return {type: :object_list, data: all_shares, fields: %w[id name status status_message]}
              when :user_permissions, :group_permissions
                share_id = instance_identifier
                permission_path = "data/shares/#{share_id}/#{command}"
                case options.get_next_command(%i[list show create modify delete])
                when :list
                  return {type: :object_list, data: api_shares_admin.read(permission_path)[:data]}
                when :create
                  parameters = options.get_option(:value)
                  return {type: :single_object, data: api_shares_admin.create(permission_path, parameters)[:data]}
                when :show
                  return {type: :single_object, data: api_shares_admin.read("#{permission_path}/#{instance_identifier}")[:data]}
                when :modify
                  parameters = options.get_option(:value)
                  return {type: :single_object, data: api_shares_admin.create("#{permission_path}/#{instance_identifier}", parameters)[:data]}
                when :delete
                  parameters = options.get_option(:value)
                  return {type: :single_object, data: api_shares_admin.delete("#{permission_path}/#{instance_identifier}", parameters)[:data]}
                end
              end
            end
          end
        end # execute action
      end # Shares
    end # Plugins
  end # Cli
end # Aspera
