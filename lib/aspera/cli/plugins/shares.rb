# frozen_string_literal: true

require 'aspera/cli/plugins/basic_auth'
require 'aspera/cli/plugins/node'
require 'aspera/assert'
require 'aspera/rest_list'

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
            # Get version from main page
            result[:version] =
              begin
                version = nil
                login_page = Rest
                  .new(base_url: url, redirect_max: 2)
                  .read('', headers: {'Accept'=>'text/html'})
                raise 'not Shares' unless login_page.include?('aspera-Shares')
                if (m = login_page.match(/\(v([0-9a-f\.]+)\)/))
                  version = m[1]
                  if (m = login_page.match(/Patch level ([0-9]+)/))
                    version = "#{version} #{m[0]}"
                  end
                end
                version.nil? ? 'no version' : version
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
                data, resp = Rest
                  .new(base_url: "#{url}/#{NODE_API_PATH}", redirect_max: 1)
                  .read('info', exception: false, ret: :both)
                # shall fail: shares requires auth, but we check error message
                if resp.code.to_s.eql?('401') && data&.dig('error', 'user_message')&.include?('authentication failed')
                  'available'
                else
                  raise "not found (#{resp.code})"
                end
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
          @api_shares_admin = nil
        end

        SAML_IMPORT_MANDATORY = %w[id name_id].freeze
        SAML_IMPORT_ALLOWED = %w[email given_name surname].concat(SAML_IMPORT_MANDATORY).freeze

        # common to users and groups
        USR_GRP_SETTINGS = %i[transfer_settings app_authorizations share_permissions].freeze

        # --- DSL ---

        command(:health,   description: 'Check Shares health')
        command(:info,     description: 'Show server information')
        command(:files,    description: 'Browse and transfer files on Shares', aliases: [:repository])
        command(:admin,    description: 'Administer Shares', setup: :setup_admin)

        commands_under(:admin) do
          command(:node,              description: 'Manage nodes')
          command(:share,             description: 'Manage shares')
          command(:transfer_settings, description: 'Manage transfer settings')
          command(:user,              description: 'Manage users')
          command(:group,             description: 'Manage groups')
        end

        commands_under(%i[admin share]) do
          Operations::ALL.each do |op|
            command(op, description: "#{op.capitalize} share(s)")
          end
          command(:user_permissions,  description: 'Manage user permissions on a share')
          command(:group_permissions, description: 'Manage group permissions on a share')
        end

        commands_under(%i[admin transfer_settings]) do
          command(:show,   description: 'Show transfer settings')
          command(:modify, description: 'Modify transfer settings')
        end

        # --- setup ---

        # Build the admin REST API and store in ivar.
        # @return [Hash] empty ctx (state stored in @api_shares_admin)
        def setup_admin
          @api_shares_admin = basic_auth_api(ADMIN_API_PATH)
          {}
        end

        # Lookup a share id by field/value using the admin API.
        def lookup_share_id(field, value)
          RestList.lookup_entity_generic(entity: 'share', field: field, value: value){@api_shares_admin.read('data/shares')}['id']
        end

        # --- health ---

        def handle_health
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
          Result::ObjectList.new(nagios.status_list)
        end

        # --- info ---

        def handle_info
          Result::SingleObject.new(basic_auth_api(NODE_API_PATH).read('info', headers: {'Content-Type'=>'application/json'}))
        end

        # --- files (delegate to Node plugin) ---

        def handle_files
          api_shares_node = basic_auth_api(NODE_API_PATH)
          repo_command = options.get_next_command(Node::COMMANDS_SHARES)
          Node.new(context: context, api: api_shares_node).execute_action(repo_command)
        end

        # --- admin node (entity_execute shorthand via DSL) ---
        # The `entity_execute:` hash on the :node command provides `entity:`;
        # the api: is injected from ctx by run_entity_execute (setup_admin stored @api_shares_admin
        # and the DSL setup: key returns {} — so api must be in the entity_execute hash itself).
        # Override: entity_execute is declared directly in the command, api comes from ivar.
        def handle_admin_node
          entity_execute(api: @api_shares_admin, entity: 'data/nodes')
        end

        # --- admin share ---

        # Share display fields reused across CRUD handlers
        SHARE_DISPLAY_FIELDS = %w[id name node_id directory percent_free].freeze

        def handle_admin_share_create
          entity_execute(
            api: @api_shares_admin, entity: 'data/shares', command: :create,
            display_fields: SHARE_DISPLAY_FIELDS
          ){ |f, v| lookup_share_id(f, v)}
        end

        def handle_admin_share_list
          entity_execute(
            api: @api_shares_admin, entity: 'data/shares', command: :list,
            display_fields: SHARE_DISPLAY_FIELDS
          ){ |f, v| lookup_share_id(f, v)}
        end

        def handle_admin_share_show
          entity_execute(
            api: @api_shares_admin, entity: 'data/shares', command: :show,
            display_fields: SHARE_DISPLAY_FIELDS
          ){ |f, v| lookup_share_id(f, v)}
        end

        def handle_admin_share_modify
          entity_execute(
            api: @api_shares_admin, entity: 'data/shares', command: :modify,
            display_fields: SHARE_DISPLAY_FIELDS
          ){ |f, v| lookup_share_id(f, v)}
        end

        def handle_admin_share_delete
          entity_execute(
            api: @api_shares_admin, entity: 'data/shares', command: :delete,
            display_fields: SHARE_DISPLAY_FIELDS
          ){ |f, v| lookup_share_id(f, v)}
        end

        def handle_admin_share_user_permissions
          share_id = options.instance_identifier{ |f, v| lookup_share_id(f, v)}
          entity_execute(api: @api_shares_admin, entity: "data/shares/#{share_id}/user_permissions")
        end

        def handle_admin_share_group_permissions
          share_id = options.instance_identifier{ |f, v| lookup_share_id(f, v)}
          entity_execute(api: @api_shares_admin, entity: "data/shares/#{share_id}/group_permissions")
        end

        # --- admin transfer_settings ---

        def handle_admin_transfer_settings_show
          entity_execute(api: @api_shares_admin, entity: 'data/transfer_settings', command: :show, is_singleton: true)
        end

        def handle_admin_transfer_settings_modify
          entity_execute(api: @api_shares_admin, entity: 'data/transfer_settings', command: :modify, is_singleton: true)
        end

        # --- admin user / group (too dynamic for static DSL sub-tree) ---

        def handle_admin_user
          execute_admin_entity_type(:user)
        end

        def handle_admin_group
          execute_admin_entity_type(:group)
        end

        private

        # Shared implementation for `admin user` and `admin group` commands.
        # @param entity_type [:user, :group]
        def execute_admin_entity_type(entity_type)
          entities_location = options.get_next_command(%i[all local ldap saml])
          entities_prefix = entities_location.eql?(:all) ? '' : "#{entities_location}_"
          entities_path = "data/#{entities_prefix}#{entity_type}s"
          entity_commands =
            case entities_location
            when :all
              cmds = %i[list show delete].concat(USR_GRP_SETTINGS)
              cmds.push(:users) if entity_type.eql?(:group)
              cmds.freeze
            when :local
              cmds = %i[list show delete create modify]
              cmds.push(:users) if entity_type.eql?(:group)
              cmds.freeze
            when :ldap then %i[add].freeze
            when :saml then %i[import].freeze
            end
          entity_verb = options.get_next_command(entity_commands)
          lookup_block = ->(field, value){RestList.lookup_entity_generic(entity: entity_type, field: field, value: value){@api_shares_admin.read(entities_path)}['id']}
          case entity_verb
          when *Operations::ALL
            display_fields = entity_type.eql?(:user) ? %w[id user_id username first_name last_name email] : nil
            display_fields.push('directory_user') if entity_type.eql?(:user) && entities_location.eql?(:all)
            return entity_execute(
              api:            @api_shares_admin,
              entity:         entities_path,
              command:        entity_verb,
              display_fields: display_fields,
              &lookup_block
            )
          when *USR_GRP_SETTINGS # transfer_settings, app_authorizations, share_permissions
            group_id = options.instance_identifier(&lookup_block)
            sub_path = "#{entities_path}/#{group_id}/#{entity_verb}"
            return entity_execute(api: @api_shares_admin, entity: sub_path, is_singleton: !entity_verb.eql?(:share_permissions)){ |f, v| lookup_share_id(f, v)}
          when :import # saml
            return do_bulk_operation(command: entity_verb, descr: 'user information') do |entity_parameters|
              entity_parameters = entity_parameters.transform_keys{ |k| k.gsub(/\s+/, '_').downcase}
              Aspera.assert_type(entity_parameters, Hash)
              SAML_IMPORT_MANDATORY.each{ |p| raise "missing mandatory field: #{p}" if entity_parameters[p].nil?}
              entity_parameters.each_key do |p|
                raise "unsupported field: #{p}, use: #{SAML_IMPORT_ALLOWED.join(',')}" unless SAML_IMPORT_ALLOWED.include?(p)
              end
              @api_shares_admin.create("#{entities_path}/import", entity_parameters)
            end
          when :add # ldap
            return do_bulk_operation(command: entity_verb, descr: "#{entity_type} name", values: String) do |entity_name|
              @api_shares_admin.create(entities_path, {entity_type=>entity_name})
            end
          when :users # group
            return entity_execute(api: @api_shares_admin, entity: "#{entities_path}/#{options.instance_identifier(&lookup_block)}/#{entities_prefix}users")
          else Aspera.error_unexpected_value(entity_verb)
          end
        end
      end
    end
  end
end
