# frozen_string_literal: true

require 'aspera/cli/plugins/node'

module Aspera
  module Cli
    module Plugins
      # Plugin for Aspera Shares v1
      class Shares < Aspera::Cli::BasicAuthPlugin
        class << self
          def detect(address_or_url)
            address_or_url = "https://#{address_or_url}" unless address_or_url.match?(%r{^[a-z]{1,6}://})
            api = Rest.new(base_url: address_or_url, redirect_max: 1)
            found = false
            begin
              # shall fail: shares requires auth, but we check error message
              # TODO: use ping instead ?
              api.read('node_api/app')
            rescue RestCallError => e
              if e.response.code.to_s.eql?('401') && e.response.body.eql?('{"error":{"user_message":"API user authentication failed"}}')
                found = true
              end
            end
            return nil unless found
            version = 'unknown'
            main_page = api.call({ operation: 'GET', subpath: 'login' })
            if (m = main_page[:http].body.match(/\(v(1\..*)\)/))
              version = m[1]
            end
            return {
              name:    'Shares',
              version: version,
              url:     address_or_url
            }
          end

          def wizard(object:, private_key_path: nil, pub_key_pem: nil)
            options = object.options
            return {
              preset_value: {
                url:      options.get_option(:url, mandatory: true),
                username: options.get_option(:username, mandatory: true),
                password: options.get_option(:password, mandatory: true)
              },
              test_args:    'files br /'
            }
          end
        end

        def initialize(env)
          super(env)
          options.declare(:type, 'Type of user/group for operations', values: %i[any local ldap saml], default: :any)
          options.parse_options!
        end

        SAML_IMPORT_MANDATORY = %w[id name_id].freeze
        SAML_IMPORT_ALLOWED = %w[email given_name surname].concat(SAML_IMPORT_MANDATORY).freeze

        ACTIONS = %i[health files admin].freeze
        # common to users and groups
        USR_GRP_SETTINGS = %i[transfer_settings app_authorizations share_permissions].freeze

        def execute_action
          command = options.get_next_command(ACTIONS, aliases: {repository: :files})
          case command
          when :health
            nagios = Nagios.new
            begin
              Rest
                .new(base_url: options.get_option(:url, mandatory: true) + '/node_api')
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
          when :repository, :files
            api_shares_node = basic_auth_api('node_api')
            repo_command = options.get_next_command(Node::COMMANDS_SHARES)
            return Node.new(@agents.merge(skip_basic_auth_options: true, node_api: api_shares_node)).execute_action(repo_command)
          when :admin
            api_shares_admin = basic_auth_api('api/v1')
            admin_command = options.get_next_command(%i[user group share node].freeze)
            case admin_command
            when :node
              return entity_action(api_shares_admin, 'data/nodes')
            when :user, :group
              entity_type = admin_command
              entities_location = options.get_option(:type, mandatory: true)
              entities_path = "data/#{entities_location}_#{entity_type}s"
              entity_action = nil
              case entities_location
              when :any
                entities_path = "data/#{entity_type}s"
                entity_action = %i[list show delete]
                entity_action.concat(USR_GRP_SETTINGS)
                entity_action.push(:users) if entity_type.eql?(:group)
                entity_action.freeze
              when :local
                entity_action = %i[list show create modify delete].freeze
              when :ldap
                entity_action = %i[add].freeze
              when :saml
                entity_action = %i[import].freeze
              end
              entity_verb = options.get_next_command(entity_action)
              # entity_path = "#{entities_path}/#{instance_identifier}" if %i[app_authorizations share_permissions].include?(entity_verb)
              case entity_verb
              when *Plugin::ALL_OPS
                display_fields = entity_type.eql?(:user) ? %w[id username first_name last_name email] : nil
                display_fields.push(:directory_user) if entity_type.eql?(:user) && entities_location.eql?(:any)
                return entity_command(entity_verb, api_shares_admin, entities_path, display_fields: display_fields)
              when :import
                return do_bulk_operation(value_create_modify(type: :bulk_hash), 'created') do |entity_parameters|
                  entity_parameters = entity_parameters.transform_keys{|k|k.gsub(/\s+/, '_').downcase}
                  raise 'expecting Hash' unless entity_parameters.is_a?(Hash)
                  SAML_IMPORT_MANDATORY.each{|p|raise "missing mandatory field: #{p}" if entity_parameters[p].nil?}
                  entity_parameters.each_key do |p|
                    raise "unsupported field: #{p}, use: #{SAML_IMPORT_ALLOWED.join(',')}" unless SAML_IMPORT_ALLOWED.include?(p)
                  end
                  api_shares_admin.create("#{entities_path}/import", entity_parameters)[:data]
                end
              when :add
                return do_bulk_operation(value_create_modify(type: :bulk_hash), 'created') do |entity_name|
                  raise "expecting string (name), have #{entity_name.class}" unless entity_name.is_a?(String)
                  api_shares_admin.create(entities_path, {entity_type=>entity_name})[:data]
                end
              when *USR_GRP_SETTINGS
                group_id = instance_identifier
                entities_path = "#{entities_path}/#{group_id}/#{entity_verb}"
                return entity_action(api_shares_admin, entities_path, is_singleton: !entity_verb.eql?(:share_permissions))
              end
            when :share
              share_command = options.get_next_command(%i[user_permissions group_permissions].concat(Plugin::ALL_OPS))
              case share_command
              when *Plugin::ALL_OPS
                return entity_command(share_command, api_shares_admin, 'data/shares')
                # return {type: :object_list, data: all_shares, fields: %w[id name status status_message]}
              when :user_permissions, :group_permissions
                return entity_action(api_shares_admin, "data/shares/#{instance_identifier}/#{share_command}")
              end
            end
          end
        end # execute action
      end # Shares
    end # Plugins
  end # Cli
end # Aspera
