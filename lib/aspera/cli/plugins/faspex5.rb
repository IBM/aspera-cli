require 'aspera/cli/basic_auth_plugin'
require 'aspera/persistency_action_once'
require 'aspera/id_generator'
require 'securerandom'

module Aspera
  module Cli
    module Plugins
      class Faspex5 < BasicAuthPlugin
        VAL_ALL='ALL'
        def initialize(env)
          super(env)
          options.add_opt_simple(:client_id,'API client identifier in application')
          options.add_opt_simple(:client_secret,'API client secret in application')
          options.add_opt_simple(:redirect_uri,'API client redirect URI')
          options.add_opt_list(:auth,Oauth.auth_types.clone.push(:boot),'type of Oauth authentication')
          options.add_opt_simple(:private_key,'RSA private key PEM value for JWT (prefix file path with @val:@file:)')
          options.set_option(:auth,:jwt)
          options.parse_options!
        end

        def set_api
          @faxpex5_api_base_url=options.get_option(:url,:mandatory)
          faxpex5_api_v5_url="#{@faxpex5_api_base_url}/api/v5"
          faxpex5_api_auth_url="#{@faxpex5_api_base_url}/auth"
          case options.get_option(:auth,:mandatory)
          when :boot
            # the password here is the token copied directly from browser in developer mode
            @api_v5=Rest.new({
              :base_url => faxpex5_api_v5_url,
              :headers => {'Authorization'=>options.get_option(:password,:mandatory)},
            })
          when :web
            # opens a browser and ask user to auth using web
            @api_v5=Rest.new({
              :base_url => faxpex5_api_v5_url,
              :auth     => {
              :type           => :oauth2,
              :base_url       => faxpex5_api_auth_url,
              :grant          => :web,
              :state          => SecureRandom.uuid,
              :client_id      => options.get_option(:client_id,:mandatory),
              :redirect_uri   => options.get_option(:redirect_uri,:mandatory),
              }})
          when :jwt
            # currently Faspex 5 beta 3 only supports non-user based apis (e.g. jobs)
            app_client_id=options.get_option(:client_id,:mandatory)
            @api_v5=Rest.new({
              :base_url => faxpex5_api_v5_url,
              :auth     => {
              :type                => :oauth2,
              :base_url            => faxpex5_api_auth_url,
              :grant               => :jwt,
              :f5_username         => options.get_option(:username,:mandatory),
              :f5_password         => options.get_option(:password,:mandatory),
              :client_id           => app_client_id,
              :client_secret       => options.get_option(:client_secret,:mandatory),
              :jwt_subject         => "client:#{app_client_id}", # TODO Mmmm
              :jwt_audience        => app_client_id, # TODO Mmmm
              :jwt_private_key_obj => OpenSSL::PKey::RSA.new(options.get_option(:private_key,:mandatory)),
              :jwt_headers         => {typ: 'JWT'}
              }})
          end
        end

        ACTIONS=[ :node, :package, :auth_client, :jobs ]

        #
        def execute_action
          set_api
          command=options.get_next_command(ACTIONS)
          case command
          when :auth_client
            api_auth=Rest.new(@api_v5.params.merge({base_url: "#{@faxpex5_api_base_url}/auth"}))
            return self.entity_action(api_auth,'oauth_clients',nil,:id,nil,true)
          when :node
            return self.entity_action(@api_v5,'nodes',nil,:id,nil,true)
          when :jobs
            # to test JWT
            return self.entity_action(@api_v5,'jobs',nil,:id,nil,true)
          when :package
            command=options.get_next_command([:list,:show,:send,:receive])
            case command
            when :list
              parameters=options.get_option(:value,:optional)
              return {:type => :object_list, :data=>@api_v5.read('packages',parameters)[:data]['packages']}
            when :show
              id=options.get_option(:id,:mandatory)
              return {:type => :single_object, :data=>@api_v5.read("packages/#{id}")[:data]}
            when :send
              parameters=options.get_option(:value,:mandatory)
              raise CliBadArgument,'value must be hash, refer to API' unless parameters.is_a?(Hash)
              package=@api_v5.create('packages',parameters)[:data]
              transfer_spec=@api_v5.create("packages/#{package['id']}/transfer_spec/upload",{transfer_type: 'Connect'})[:data]
              transfer_spec.delete('authentication')
              return Main.result_transfer(self.transfer.start(transfer_spec,{:src=>:node_gen3}))
            when :receive
              pkg_type='received'
              pack_id=options.get_option(:id,:mandatory)
              package_ids=[pack_id]
              skip_ids_data=[]
              skip_ids_persistency=nil
              if options.get_option(:once_only,:mandatory)
                # read ids from persistency
                skip_ids_persistency=PersistencyActionOnce.new(
                manager: @agents[:persistency],
                data:    skip_ids_data,
                id:      IdGenerator.from_list(['faspex_recv',options.get_option(:url,:mandatory),options.get_option(:username,:mandatory),pkg_type]))
              end
              if pack_id.eql?(VAL_ALL)
                # TODO: if packages have same name, they will overwrite
                parameters=options.get_option(:value,:optional)
                parameters||={'type'=>'received','subtype'=>'mypackages','limit'=>1000}
                raise CliBadArgument,'value filter must be Hash (API GET)' unless parameters.is_a?(Hash)
                package_ids=@api_v5.read('packages',parameters)[:data]['packages'].map{|p|p['id']}
                package_ids.select!{|i|!skip_ids_data.include?(i)}
              end
              result_transfer=[]
              package_ids.each do |id|
                # TODO: allow from sent as well ?
                transfer_spec=@api_v5.create("packages/#{id}/transfer_spec/download",{transfer_type: 'Connect', type: pkg_type})[:data]
                transfer_spec.delete('authentication')
                statuses=self.transfer.start(transfer_spec,{:src=>:node_gen3})
                result_transfer.push({'package'=>id,Main::STATUS_FIELD=>statuses})
                # skip only if all sessions completed
                skip_ids_data.push(id) if TransferAgent.session_status(statuses).eql?(:success)
              end
              skip_ids_persistency.save unless skip_ids_persistency.nil?
              return Main.result_transfer_multiple(result_transfer)
            end
          end
        end
      end
    end # Plugins
  end # Cli
end # Aspera
