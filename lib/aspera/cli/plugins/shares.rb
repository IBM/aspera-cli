# frozen_string_literal: true

require 'aspera/cli/plugins/basic_auth'
require 'aspera/cli/plugins/node'
require 'aspera/assert'
module Aspera
  module Cli
    module Plugins
      # Plugin for Aspera Shares v1
      class Shares < BasicAuth
        # path for node API after base url
        NODE_API_PATH = 'node_api'
        # path for node admin after base url
        ADMIN_API_PATH = 'api/v1'
        class << self
          # Check various endpoints on Shares
          # @return [Hash] with version, ping, api
          def health_check(url)
            result = {}
            result[:version] =
              begin
                version = nil
                login_page = Rest
                  .new(base_url: url, redirect_max: 2)
                  .read('', headers: {'Accept'=>'text/html'})
                if (m = login_page.match(/\(v([0-9a-f\.]+)\)/))
                  version = m[1]
                  if (m = login_page.match(/Patch level ([0-9]+)/))
                    version = "#{result[:version]} #{m[0]}"
                  end
                end
                raise 'no version' if version.nil?
                version
              rescue => e
                e
              end
            result[:ping] =
              begin
                Rest
                  .new(base_url: "#{url}/#{NODE_API_PATH}")
                  .read('ping', headers: {'Content-Type'=>'application/json'})
                'ping ok'
              rescue => e
                e
              end
            result[:api] =
              begin
                resp = Rest.new(base_url: url, redirect_max: 1).read("#{NODE_API_PATH}/app", exception: false, ret: :resp)
                # shall fail: shares requires auth, but we check error message
                raise 'not found' unless resp.code.to_s.eql?('401') && resp.body.eql?('{"error":{"user_message":"API user authentication failed"}}')
                'available'
              rescue => e
                e
              end
            result
          end

          # @return [Hash,NilClass]
          def detect(address_or_url)
            address_or_url = "https://#{address_or_url}" unless address_or_url.match?(%r{^[a-z]{1,6}://})
            health = health_check(address_or_url)
            return unless health[:api].is_a?(String)
            return {
              version: health[:version].is_a?(String) ? health[:version] : 'unknown',
              url:     address_or_url
            }
          end
        end

        # @param wizard  [Wizard] The wizard object
        # @param app_url [String] Tested URL
        # @return [Hash] :preset_value, :test_args
        def wizard(wizard, app_url)
          return {
            preset_value: {
              url:      app_url,
              username: options.get_option(:username, mandatory: true),
              password: options.get_option(:password, mandatory: true)
            },
            test_args:    'files browse /'
          }
        end

        def initialize(**_)
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
            shares_url = options.get_option(:url, mandatory: true)
            health = self.class.health_check(shares_url)
            nagios.add_ok('version', health[:version]) if health[:version].is_a?(String)
            if health[:ping].is_a?(String)
              nagios.add_ok('ping', health[:ping])
            else
              nagios.add_critical('ping', health[:ping].to_s)
            end
            if health[:api].is_a?(String)
              nagios.add_ok('API', health[:api])
            else
              nagios.add_critical('API', health[:api].to_s)
            end
            Main.result_object_list(nagios.status_list)
          when :files
            api_shares_node = basic_auth_api(NODE_API_PATH)
            repo_command = options.get_next_command(Node::COMMANDS_SHARES)
            return Node
                .new(context: context, api: api_shares_node)
                .execute_action(repo_command)
          when :admin
            api_shares_admin = basic_auth_api(ADMIN_API_PATH)
            admin_command = options.get_next_command(%i[node share transfer_settings user group].freeze)
            lookup_share = ->(field, value){lookup_entity_generic(entity: 'share', field: field, value: value){api_shares_admin.read('data/shares')}['id']}
            case admin_command
            when :node
              return entity_execute(api: api_shares_admin, entity: 'data/nodes')
            when :share
              share_command = options.get_next_command(%i[user_permissions group_permissions].concat(ALL_OPS))
              case share_command
              when *ALL_OPS
                return entity_execute(
                  api:            api_shares_admin,
                  entity:         'data/shares',
                  command:        share_command,
                  display_fields: %w[id name node_id directory percent_free],
                  &lookup_share
                )
              when :user_permissions, :group_permissions
                share_id = instance_identifier(&lookup_share)
                return entity_execute(api: api_shares_admin, entity: "data/shares/#{share_id}/#{share_command}")
              end
            when :transfer_settings
              xfer_settings_command = options.get_next_command(%i[show modify])
              return entity_execute(
                api: api_shares_admin,
                entity: 'data/transfer_settings',
                command: xfer_settings_command,
                is_singleton: true
              )
            when :user, :group
              entity_type = admin_command
              entities_location = options.get_next_command(%i[all local ldap saml])
              entities_prefix = entities_location.eql?(:all) ? '' : "#{entities_location}_"
              entities_path = "data/#{entities_prefix}#{entity_type}s"
              entity_commands = nil
              case entities_location
              when :all
                entity_commands = %i[list show delete]
                entity_commands.concat(USR_GRP_SETTINGS)
                entity_commands.push(:users) if entity_type.eql?(:group)
                entity_commands.freeze
              when :local
                entity_commands = %i[list show delete create modify]
                entity_commands.push(:users) if entity_type.eql?(:group)
                entity_commands.freeze
              when :ldap
                entity_commands = %i[add].freeze
              when :saml
                entity_commands = %i[import].freeze
              end
              entity_verb = options.get_next_command(entity_commands)
              lookup_block = ->(field, value){lookup_entity_generic(entity: entity_type, field: field, value: value){api_shares_admin.read(entities_path)}['id']}
              case entity_verb
              when *ALL_OPS # list, show, delete, create, modify
                display_fields = entity_type.eql?(:user) ? %w[id user_id username first_name last_name email] : nil
                display_fields.push(:directory_user) if entity_type.eql?(:user) && entities_location.eql?(:all)
                return entity_execute(
                  api:            api_shares_admin,
                  entity:         entities_path,
                  command:        entity_verb,
                  display_fields: display_fields,
                  &lookup_block
                )
              when *USR_GRP_SETTINGS # transfer_settings, app_authorizations, share_permissions
                group_id = instance_identifier(&lookup_block)
                entities_path = "#{entities_path}/#{group_id}/#{entity_verb}"
                return entity_execute(api: api_shares_admin, entity: entities_path, is_singleton: !entity_verb.eql?(:share_permissions), &lookup_share)
              when :import # saml
                return do_bulk_operation(command: entity_verb, descr: 'user information') do |entity_parameters|
                  entity_parameters = entity_parameters.transform_keys{ |k| k.gsub(/\s+/, '_').downcase}
                  Aspera.assert_type(entity_parameters, Hash)
                  SAML_IMPORT_MANDATORY.each{ |p| raise "missing mandatory field: #{p}" if entity_parameters[p].nil?}
                  entity_parameters.each_key do |p|
                    raise "unsupported field: #{p}, use: #{SAML_IMPORT_ALLOWED.join(',')}" unless SAML_IMPORT_ALLOWED.include?(p)
                  end
                  api_shares_admin.create("#{entities_path}/import", entity_parameters)
                end
              when :add # ldap
                return do_bulk_operation(command: entity_verb, descr: "#{entity_type} name", values: String) do |entity_name|
                  api_shares_admin.create(entities_path, {entity_type=>entity_name})
                end
              when :users # group
                return entity_execute(api: api_shares_admin, entity: "#{entities_path}/#{instance_identifier(&lookup_block)}/#{entities_prefix}users")
              else Aspera.error_unexpected_value(entity_verb)
              end
            end
          end
        end
      end
    end
  end
end
