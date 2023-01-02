# frozen_string_literal: true

require 'aspera/cli/basic_auth_plugin'
require 'aspera/persistency_action_once'
require 'aspera/id_generator'
require 'aspera/nagios'
require 'securerandom'

module Aspera
  module Cli
    module Plugins
      class Faspex5 < BasicAuthPlugin
        class << self
          def detect(base_url)
            api = Rest.new(base_url: base_url, redirect_max: 1)
            result = api.read('api/v5/configuration/ping')
            if result[:http].code.start_with?('2') && result[:http].body.strip.empty?
              return {version: '5'}
            end
            return nil
          end
        end

        VAL_ALL = 'ALL'
        TRANSFER_CONNECT = 'connect'
        private_constant :VAL_ALL,:TRANSFER_CONNECT

        def initialize(env)
          super(env)
          options.add_opt_simple(:client_id,'OAuth client identifier')
          options.add_opt_simple(:client_secret,'OAuth client secret')
          options.add_opt_simple(:redirect_uri,'OAuth redirect URI for web authentication')
          options.add_opt_list(:auth,[Oauth::STD_AUTH_TYPES,:boot].flatten,'OAuth type of authentication')
          options.add_opt_simple(:private_key,'OAuth JWT RSA private key PEM value (prefix file path with @file:)')
          options.add_opt_simple(:passphrase,'RSA private key passphrase')
          options.set_option(:auth,:jwt)
          options.parse_options!
        end

        def set_api
          @faxpex5_api_base_url = options.get_option(:url,is_type: :mandatory).gsub(%r{/+$},'')
          @faxpex5_api_auth_url = "#{@faxpex5_api_base_url}/auth"
          faxpex5_api_v5_url = "#{@faxpex5_api_base_url}/api/v5"
          case options.get_option(:auth,is_type: :mandatory)
          when :boot
            # the password here is the token copied directly from browser in developer mode
            @api_v5 = Rest.new({
              base_url: faxpex5_api_v5_url,
              headers:  {'Authorization' => options.get_option(:password,is_type: :mandatory)}
            })
          when :web
            # opens a browser and ask user to auth using web
            @api_v5 = Rest.new({
              base_url: faxpex5_api_v5_url,
              auth:     {
                type:      :oauth2,
                base_url:  @faxpex5_api_auth_url,
                crtype:    :web,
                client_id: options.get_option(:client_id,is_type: :mandatory),
                web:       {redirect_uri: options.get_option(:redirect_uri,is_type: :mandatory)}
              }})
          when :jwt
            app_client_id = options.get_option(:client_id,is_type: :mandatory)
            @api_v5 = Rest.new({
              base_url: faxpex5_api_v5_url,
              auth:     {
                type:      :oauth2,
                base_url:  @faxpex5_api_auth_url,
                crtype:    :jwt,
                client_id: app_client_id,
                jwt:       {
                  payload:         {
                    iss: app_client_id,    # issuer
                    aud: app_client_id,    # audience TODO: ???
                    sub: "user:#{options.get_option(:username,is_type: :mandatory)}" # subject also "client:#{app_client_id}" + auth user/pass
                  },
                  #auth:                {type: :basic, options.get_option(:username,is_type: :mandatory), options.get_option(:password,is_type: :mandatory),
                  private_key_obj: OpenSSL::PKey::RSA.new(options.get_option(:private_key,is_type: :mandatory),options.get_option(:passphrase)),
                  headers:         {typ: 'JWT'}
                }
              }})
          end
        end

        ACTIONS = %i[health version user bearer_token package admin].freeze

        def execute_action
          set_api
          command = options.get_next_command(ACTIONS)
          case command
          when :version
            return { type: :single_object, data: @api_v5.read('version')[:data] }
          when :health
            nagios = Nagios.new
            begin
              result=Rest.new(base_url: @faxpex5_api_base_url).read('health')[:data]
              result.each do |k,v|
                nagios.add_ok(k,v.to_s)
              end
            rescue StandardError => e
              nagios.add_critical('faspex api',e.to_s)
            end
            return nagios.result
          when :user
            case options.get_next_command(%i[profile])
            when :profile
              case options.get_next_command(%i[show modify])
              when :show
                return { type: :single_object, data: @api_v5.read('account/preferences')[:data] }
              when :modify
                @api_v5.update('account/preferences',options.get_next_argument('modified parameters (Hash)'))
                return Main.result_status('modified')
              end
            end
          when :bearer_token
            return {type: :text,data: @api_v5.oauth_token}
          when :package
            command = options.get_next_command(%i[list show send receive])
            case command
            when :list
              parameters = options.get_option(:value)
              return {
                type:   :object_list,
                data:   @api_v5.read('packages',parameters)[:data]['packages'],
                fields: %w[id title release_date total_bytes total_files created_time state]
              }
            when :show
              id = instance_identifier
              return {type: :single_object, data: @api_v5.read("packages/#{id}")[:data]}
            when :send
              parameters = options.get_option(:value,is_type: :mandatory)
              raise CliBadArgument,'value must be hash, refer to API' unless parameters.is_a?(Hash)
              package = @api_v5.create('packages',parameters)[:data]
              # TODO: option to send from remote source
              transfer_spec = @api_v5.create("packages/#{package['id']}/transfer_spec/upload",{transfer_type: TRANSFER_CONNECT})[:data]
              transfer_spec.delete('authentication')
              return Main.result_transfer(transfer.start(transfer_spec,:node_gen3))
            when :receive
              pkg_type = 'received'
              pack_id = instance_identifier
              package_ids = [pack_id]
              skip_ids_data = []
              skip_ids_persistency = nil
              if options.get_option(:once_only,is_type: :mandatory)
                # read ids from persistency
                skip_ids_persistency = PersistencyActionOnce.new(
                  manager: @agents[:persistency],
                  data:    skip_ids_data,
                  id:      IdGenerator.from_list(['faspex_recv',options.get_option(:url,is_type: :mandatory),options.get_option(:username,is_type: :mandatory),pkg_type]))
              end
              if pack_id.eql?(VAL_ALL)
                # TODO: if packages have same name, they will overwrite
                parameters = options.get_option(:value)
                parameters ||= {'type' => 'received','subtype' => 'mypackages','limit' => 1000}
                raise CliBadArgument,'value filter must be Hash (API GET)' unless parameters.is_a?(Hash)
                package_ids = @api_v5.read('packages',parameters)[:data]['packages'].map{|p|p['id']}
                package_ids.reject!{|i|skip_ids_data.include?(i)}
              end
              result_transfer = []
              package_ids.each do |pkgid|
                # TODO: allow from sent as well ?
                transfer_spec = @api_v5.create("packages/#{pkgid}/transfer_spec/download",{transfer_type: TRANSFER_CONNECT, type: pkg_type})[:data]
                transfer_spec.delete('authentication')
                statuses = transfer.start(transfer_spec,:node_gen3)
                result_transfer.push({'package' => pkgid,Main::STATUS_FIELD => statuses})
                # skip only if all sessions completed
                skip_ids_data.push(pkgid) if TransferAgent.session_status(statuses).eql?(:success)
              end
              skip_ids_persistency&.save
              return Main.result_transfer_multiple(result_transfer)
            end # case package
          when :admin
            case options.get_next_command([:resource])
            when :resource
              res_type = options.get_next_command(%i[accounts contacts jobs workgroups shared_inboxes nodes oauth_clients registrations saml_configs metadata_profiles])
              res_path = list_key = res_type.to_s
              case res_type
              when :metadata_profiles
                res_path='configuration/metadata_profiles'
                list_key='profiles'
              end
              display_fields =
                case res_type
                when :accounts then [:all_but,'user_profile_data_attributes']
                when :oauth_clients then [:all_but,'public_key']
                end
              adm_api = @api_v5
              if res_type.eql?(:oauth_clients)
                adm_api = Rest.new(@api_v5.params.merge({base_url: @faxpex5_api_auth_url}))
              end
              return entity_action(adm_api,res_path,item_list_key: list_key, display_fields: display_fields)
            end
          end # case command
        end # action
      end # Faspex5
    end # Plugins
  end # Cli
end # Aspera
