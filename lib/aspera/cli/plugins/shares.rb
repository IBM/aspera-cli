# frozen_string_literal: true

require 'aspera/cli/plugins/node'

module Aspera
  module Cli
    module Plugins
      class Shares < BasicAuthPlugin
        class << self
          def detect(base_url)
            api = Rest.new({base_url: base_url})
            # Shares
            begin
              # shall fail: shares requires auth, but we check error message
              api.read('node_api/app')
            rescue RestCallError => e
              if e.response.code.to_s.eql?('401') && e.response.body.eql?('{"error":{"user_message":"API user authentication failed"}}')
                return {version: 'unknown'}
              end
            end
            nil
          end
        end

        #        def initialize(env)
        #          super(env)
        #        end

        SAML_IMPORT_MANDATORY=%w[id name_id].freeze
        SAML_IMPORT_ALLOWED=%w[email given_name surname].concat(SAML_IMPORT_MANDATORY).freeze

        ACTIONS = %i[health repository admin].freeze

        def execute_action
          command = options.get_next_command(ACTIONS)
          case command
          when :health
            nagios = Nagios.new
            begin
              Rest.
                new(base_url: options.get_option(:url, is_type: :mandatory)+'/node_api').
                call(
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
            command = options.get_next_command(Node::FILE_ACTIONS)
            case command
            when *Node::FILE_ACTIONS then Node.new(@agents.merge(skip_basic_auth_options: true, node_api: api_shares_node)).execute_action(command)
            else raise "INTERNAL ERROR, unknown command: [#{command}]"
            end
          when :admin
            api_shares_admin = basic_auth_api('api/v1')
            command = options.get_next_command(%i[user share])
            case command
            when :user
              command = options.get_next_command(%i[list app_authorizations share_permissions saml_import ldap_import])
              user_id = instance_identifier if %i[app_authorizations share_permissions].include?(command)
              case command
              when :list
                return {type: :object_list, data: api_shares_admin.read('data/users')[:data], fields: %w[id username email directory_user urn]}
              when :app_authorizations
                return {type: :single_object, data: api_shares_admin.read("data/users/#{user_id}/app_authorizations")[:data]}
              when :share_permissions
                #share_name = options.get_next_argument('share name')
                #all_shares = api_shares_admin.read('data/shares')[:data]
                #share_id = all_shares.find{|s| s['name'].eql?(share_name)}['id']
                return {type: :object_list, data: api_shares_admin.read("data/users/#{user_id}/share_permissions")[:data]}
              when :saml_import
                parameters = options.get_option(:value)
                return do_bulk_operation(parameters, 'created') do |user_params|
                  user_params=user_params.transform_keys{|k|k.gsub(/\s+/, '_').downcase}
                  raise 'expecting Hash' unless user_params.is_a?(Hash)
                  SAML_IMPORT_MANDATORY.each{|p|raise "missing mandatory field: #{p}" if user_params[p].nil?}
                  user_params.keys.each do |p|
                    raise "unsupported field: #{p}, use: #{SAML_IMPORT_ALLOWED.join(',')}" unless SAML_IMPORT_ALLOWED.include?(p)
                  end
                  api_shares_admin.create('data/saml_users/import', user_params)[:data]
                end
              when :ldap_import
                parameters = options.get_option(:value)
                return do_bulk_operation(parameters, 'created') do |user_name|
                  raise 'expecting string (user name), have #{user_params.class}' unless user_params.is_a?(String)
                  api_shares_admin.create('data/ldap_users', {'user'=>user_name})[:data]
                end
              end
            when :share
              command = options.get_next_command(%i[list user_permissions])
              share_id = instance_identifier if %i[user_permissions].include?(command)
              all_shares = api_shares_admin.read('data/shares')[:data]
              case command
              when :list
                return {type: :object_list, data: all_shares, fields: %w[id name status status_message]}
              when :user_permissions
                #share_name = options.get_next_argument('share name')
                #share_id = all_shares.find{|s| s['name'].eql?(share_name)}['id']
                #raise "NOT IMPLEMENTED: #{share_name} #{share_id}"
                return {type: :object_list, data: api_shares_admin.read("data/shares/#{share_id}/user_permissions")[:data]}
              end
            end
          end
        end # execute action
      end # Shares
    end # Plugins
  end # Cli
end # Aspera
