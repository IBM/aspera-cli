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

        command :health,   description: 'Check Shares health'
        command :info,     description: 'Show server information', action: ->{Result::SingleObject.new(basic_auth_api(NODE_API_PATH).read('info', headers: {'Content-Type'=>'application/json'}))}
        command :files,    description: 'Browse and transfer files on Shares', aliases: [:repository], setup: :setup_shares_node
        command :admin,    description: 'Administer Shares', setup: :setup_admin

        commands_under(:admin) do
          entity_command :node, api: :@api_shares_admin, entity: 'data/nodes'
          command :share,             description: 'Manage shares'
          command :transfer_settings, description: 'Manage transfer settings'
          command :user,              description: 'Manage users'
          command :group,             description: 'Manage groups'
        end

        # admin > user / group: sub-commands per location, generated for both entity types
        %i[user group].each do |entity_type|
          commands_under([:admin, entity_type]) do
            command :all,   description: "#{entity_type.capitalize}s from all sources"
            command :local, description: "Local #{entity_type}s"
            command :ldap,  description: "LDAP #{entity_type}s"
            command :saml,  description: "SAML #{entity_type}s"
          end

          # all: list/show/delete + USR_GRP_SETTINGS [+ users for group]
          commands_under([:admin, entity_type, :all]) do
            (Operations::ALL - [:create]).each do |op|
              command(op, description: "#{op.capitalize} #{entity_type}(s)")
            end
            USR_GRP_SETTINGS.each do |setting|
              command(setting, description: "Manage #{setting} for a #{entity_type}")
            end
            command(:users, description: 'List users of a group') if entity_type.eql?(:group)
          end

          # local: list/show/delete/create/modify [+ users for group]
          commands_under([:admin, entity_type, :local]) do
            Operations::ALL.each do |op|
              command(op, description: "#{op.capitalize} #{entity_type}(s)")
            end
            command(:users, description: 'List users of a group') if entity_type.eql?(:group)
          end

          # ldap: add only
          commands_under([:admin, entity_type, :ldap]) do
            command :add, description: "Add a LDAP #{entity_type}"
          end

          # saml: import only
          commands_under([:admin, entity_type, :saml]) do
            command :import, description: "Import a SAML #{entity_type}"
          end
        end

        ENTITY_LOCATIONS = %i[all local].freeze
        SHARE_DISPLAY_FIELDS = %w[id name node_id directory percent_free].freeze
        private_constant :ENTITY_LOCATIONS, :SHARE_DISPLAY_FIELDS

        commands_under(%i[admin share]) do
          Operations::ALL.each do |op|
            command(op, description: "#{op.capitalize} share(s)", action: lambda do
              entity_execute(
                api: @api_shares_admin, entity: 'data/shares', command: op,
                display_fields: SHARE_DISPLAY_FIELDS
              ){ |f, v| lookup_share_id(f, v)}
            end)
          end
          command(:user_permissions, description: 'Manage user permissions on a share', action: lambda do
            share_id = options.instance_identifier{ |f, v| lookup_share_id(f, v)}
            entity_execute(api: @api_shares_admin, entity: "data/shares/#{share_id}/user_permissions")
          end)
          command(:group_permissions, description: 'Manage group permissions on a share', action: lambda do
            share_id = options.instance_identifier{ |f, v| lookup_share_id(f, v)}
            entity_execute(api: @api_shares_admin, entity: "data/shares/#{share_id}/group_permissions")
          end)
        end

        commands_under(%i[admin transfer_settings]) do
          entity_command :show,   description: 'Show transfer settings',   api: :@api_shares_admin, entity: 'data/transfer_settings', command: :show,   is_singleton: true
          entity_command :modify, description: 'Modify transfer settings', api: :@api_shares_admin, entity: 'data/transfer_settings', command: :modify, is_singleton: true
        end

        # --- setup ---

        # Build the Shares node API plugin and inject into ctx.
        # @return [Hash] context hash containing :shares_node_plugin
        def setup_shares_node(**)
          api_shares_node = basic_auth_api(NODE_API_PATH)
          {shares_node_plugin: Node.new(context: context, api: api_shares_node)}
        end

        # Build the admin REST API and store in ivar.
        # @return [Hash] empty ctx (state stored in @api_shares_admin)
        def setup_admin(**)
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

        # --- files sub-commands (restricted to COMMANDS_SHARES, delegated to Node) ---

        commands_under(:files) do
          Node::COMMANDS_SHARES.each do |cmd|
            command(cmd, description: "Node #{cmd} command")
          end
        end

        # One handler per COMMANDS_SHARES command.
        Node::COMMANDS_SHARES.each do |cmd|
          define_method(:"handle_files_#{cmd}") do |shares_node_plugin:|
            shares_node_plugin.dispatch_v3_command(cmd)
          end
        end

        private

        # @return [String] admin API path for the given entity_type and location
        def admin_entity_path(entity_type, location)
          prefix = location.eql?(:all) ? '' : "#{location}_"
          "data/#{prefix}#{entity_type}s"
        end

        # --- admin > user|group handlers ---

        # Shared handler for list/show/delete/create/modify on user or group.
        # @param entity_type [Symbol] :user or :group
        # @param location    [Symbol] :all or :local
        # @param op          [Symbol] CRUD operation
        def handle_admin_entity_crud(entity_type, location, op)
          path = admin_entity_path(entity_type, location)
          lookup = ->(f, v){RestList.lookup_entity_generic(entity: entity_type, field: f, value: v){@api_shares_admin.read(path)}['id']}
          display_fields = entity_type.eql?(:user) ? %w[id user_id username first_name last_name email] : nil
          display_fields&.push('directory_user') if entity_type.eql?(:user) && location.eql?(:all)
          entity_execute(api: @api_shares_admin, entity: path, command: op, display_fields: display_fields, &lookup)
        end

        # Shared handler for USR_GRP_SETTINGS (transfer_settings, app_authorizations, share_permissions)
        # @param entity_type [Symbol] :user or :group
        # @param location    [Symbol] :all or :local
        # @param setting     [Symbol] one of USR_GRP_SETTINGS
        def handle_admin_entity_setting(entity_type, location, setting)
          path = admin_entity_path(entity_type, location)
          lookup = ->(f, v){RestList.lookup_entity_generic(entity: entity_type, field: f, value: v){@api_shares_admin.read(path)}['id']}
          entity_id = options.instance_identifier(&lookup)
          entity_execute(
            api:          @api_shares_admin,
            entity:       "#{path}/#{entity_id}/#{setting}",
            is_singleton: !setting.eql?(:share_permissions)
          ){ |f, v| lookup_share_id(f, v)}
        end

        # Shared handler for :users (group only)
        def handle_admin_entity_users(entity_type, location)
          path = admin_entity_path(entity_type, location)
          prefix = location.eql?(:all) ? '' : "#{location}_"
          lookup = ->(f, v){RestList.lookup_entity_generic(entity: entity_type, field: f, value: v){@api_shares_admin.read(path)}['id']}
          entity_execute(api: @api_shares_admin, entity: "#{path}/#{options.instance_identifier(&lookup)}/#{prefix}users")
        end

        # Generate handle_admin_<user|group>_<location>_<verb> for all combinations
        %i[user group].each do |entity_type|
          # all + local: CRUD + USR_GRP_SETTINGS [+ users for group]
          ENTITY_LOCATIONS.each do |location|
            ops = location.eql?(:all) ? (Operations::ALL - [:create]) : Operations::ALL
            ops.each do |op|
              define_method(:"handle_admin_#{entity_type}_#{location}_#{op}") do
                handle_admin_entity_crud(entity_type, location, op)
              end
            end
            USR_GRP_SETTINGS.each do |setting|
              define_method(:"handle_admin_#{entity_type}_#{location}_#{setting}") do
                handle_admin_entity_setting(entity_type, location, setting)
              end
            end
            next unless entity_type.eql?(:group)
            define_method(:"handle_admin_#{entity_type}_#{location}_users") do
              handle_admin_entity_users(entity_type, location)
            end
          end

          # ldap: add
          define_method(:"handle_admin_#{entity_type}_ldap_add") do
            path = admin_entity_path(entity_type, :ldap)
            do_bulk_operation(command: :add, descr: "#{entity_type} name", values: String) do |entity_name|
              @api_shares_admin.create(path, {entity_type => entity_name})
            end
          end

          # saml: import
          define_method(:"handle_admin_#{entity_type}_saml_import") do
            path = admin_entity_path(entity_type, :saml)
            do_bulk_operation(command: :import, descr: 'user information') do |entity_parameters|
              entity_parameters = entity_parameters.transform_keys{ |k| k.gsub(/\s+/, '_').downcase}
              Aspera.assert_type(entity_parameters, Hash)
              SAML_IMPORT_MANDATORY.each{ |p| raise "missing mandatory field: #{p}" if entity_parameters[p].nil?}
              entity_parameters.each_key do |p|
                raise "unsupported field: #{p}, use: #{SAML_IMPORT_ALLOWED.join(',')}" unless SAML_IMPORT_ALLOWED.include?(p)
              end
              @api_shares_admin.create("#{path}/import", entity_parameters)
            end
          end
        end
      end
    end
  end
end
