# frozen_string_literal: true

require 'aspera/cli/plugins/node'
require 'aspera/assert'
module Aspera
  module Cli
    module Plugins
      # Plugin for Aspera Shares v1
      class Shares < Cli::BasicAuthPlugin
        # path for node API after base url
        NODE_API_PATH = 'node_api'
        # path for node admin after base url
        ADMIN_API_PATH = 'api/v1'
        class << self
          def detect(address_or_url)
            address_or_url = "https://#{address_or_url}" unless address_or_url.match?(%r{^[a-z]{1,6}://})
            api = Rest.new(base_url: address_or_url, redirect_max: 1)
            found = false
            begin
              # shall fail: shares requires auth, but we check error message
              # TODO: use ping instead ?
              api.read("#{NODE_API_PATH}/app")
            rescue RestCallError => e
              if e.response.code.to_s.eql?('401') && e.response.body.eql?('{"error":{"user_message":"API user authentication failed"}}')
                found = true
              end
            end
            return nil unless found
            version = 'unknown'
            test_page = api.call(operation: 'GET', subpath: 'login')
            if (m = test_page[:http].body.match(/\(v(1\..*)\)/))
              version = m[1]
            end
            return {
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

        def initialize(**env)
          super
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
              res = Rest
                .new(base_url: "#{options.get_option(:url, mandatory: true)}/#{NODE_API_PATH}")
                .call(
                  operation: 'GET',
                  subpath: 'ping',
                  headers: {'content-type': 'application/json'})
              raise 'Shares not detected' unless res[:http].body.eql?(' ')
              nagios.add_ok('shares api', 'accessible')
            rescue StandardError => e
              nagios.add_critical('API', e.to_s)
            end
            return nagios.result
          when :repository, :files
            api_shares_node = basic_auth_api(NODE_API_PATH)
            repo_command = options.get_next_command(Node::COMMANDS_SHARES)
            return Node
                .new(**init_params, api: api_shares_node)
                .execute_action(repo_command)
          when :admin
            api_shares_admin = basic_auth_api(ADMIN_API_PATH)
            admin_command = options.get_next_command(%i[node share transfer_settings user group].freeze)
            case admin_command
            when :node
              return entity_action(api_shares_admin, 'data/nodes')
            when :share
              share_command = options.get_next_command(%i[user_permissions group_permissions].concat(Plugin::ALL_OPS))
              case share_command
              when *Plugin::ALL_OPS
                return entity_command(
                  share_command, api_shares_admin, 'data/shares',
                  display_fields: %w[id name node_id directory percent_free])
              when :user_permissions, :group_permissions
                share_id = instance_identifier
                return entity_action(api_shares_admin, "data/shares/#{share_id}/#{share_command}")
              end
            when :transfer_settings
              xfer_settings_command = options.get_next_command(%i[show modify])
              return entity_command(xfer_settings_command, api_shares_admin, 'data/transfer_settings', is_singleton: true)
            when :user, :group
              entity_type = admin_command
              entities_location = options.get_next_command(%i[all local ldap saml])
              entities_prefix = entities_location.eql?(:all) ? '' : "#{entities_location}_"
              entities_path = "data/#{entities_prefix}#{entity_type}s"
              entity_action = nil
              case entities_location
              when :all
                entity_action = %i[list show delete]
                entity_action.concat(USR_GRP_SETTINGS)
                entity_action.push(:users) if entity_type.eql?(:group)
                entity_action.freeze
              when :local
                entity_action = %i[list show delete create modify]
                entity_action.push(:users) if entity_type.eql?(:group)
                entity_action.freeze
              when :ldap
                entity_action = %i[add].freeze
              when :saml
                entity_action = %i[import].freeze
              end
              entity_verb = options.get_next_command(entity_action)
              case entity_verb
              when *Plugin::ALL_OPS # list, show, delete, create, modify
                display_fields = entity_type.eql?(:user) ? %w[id username first_name last_name email] : nil
                display_fields.push(:directory_user) if entity_type.eql?(:user) && entities_location.eql?(:all)
                return entity_command(entity_verb, api_shares_admin, entities_path, display_fields: display_fields)
              when *USR_GRP_SETTINGS # transfer_settings, app_authorizations, share_permissions
                group_id = instance_identifier
                entities_path = "#{entities_path}/#{group_id}/#{entity_verb}"
                return entity_action(api_shares_admin, entities_path, is_singleton: !entity_verb.eql?(:share_permissions))
              when :import # saml
                return do_bulk_operation(command: entity_verb, descr: 'user information') do |entity_parameters|
                  entity_parameters = entity_parameters.transform_keys{|k|k.gsub(/\s+/, '_').downcase}
                  Aspera.assert_type(entity_parameters, Hash)
                  SAML_IMPORT_MANDATORY.each{|p|raise "missing mandatory field: #{p}" if entity_parameters[p].nil?}
                  entity_parameters.each_key do |p|
                    raise "unsupported field: #{p}, use: #{SAML_IMPORT_ALLOWED.join(',')}" unless SAML_IMPORT_ALLOWED.include?(p)
                  end
                  api_shares_admin.create("#{entities_path}/import", entity_parameters)[:data]
                end
              when :add # ldap
                return do_bulk_operation(command: entity_verb, descr: "#{entity_type} name", values: String) do |entity_name|
                  api_shares_admin.create(entities_path, {entity_type=>entity_name})[:data]
                end
              when :users # group
                return entity_action(api_shares_admin, "#{entities_path}/#{instance_identifier}/#{entities_prefix}users")
              else Aspera.error_unexpected_value(entity_verb)
              end
            end
          end
        end
      end
    end
  end
end
