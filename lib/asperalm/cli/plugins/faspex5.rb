module Asperalm
  module Cli
    module Plugins
      class Faspex5 < BasicAuthPlugin
        VAL_ALL='ALL'
        def initialize(env)
          super(env)
          #self.options.add_opt_simple(:delivery_info,'package delivery information (extended value)')
          #self.options.parse_options!
        end
        ACTIONS=[ :node, :package ]

        # http://apie-next-ui-shell-dev.mybluemix.net/explorer/catalog/aspera/product/ibm-aspera/api/faspex5-api/spec/openapi
        def execute_action
          # get parameters
          faxpex5_api_base_url=self.options.get_option(:url,:mandatory)
          faxpex5_username=self.options.get_option(:username,:mandatory)
          faxpex5_password=self.options.get_option(:password,:mandatory)
          faxpex5_api_base_url+='/api/v5'
          # create object for REST calls to Shares2
          api_v5=Rest.new({
            :base_url => faxpex5_api_base_url,
            :auth     => {
            :type           => :oauth2,
            :base_url       => faxpex5_api_base_url,
            :grant          => :body_data,
            :token_field    =>'auth_token',
            :path_token     => 'authenticate',
            :path_authorize => :unused,
            :userpass_body  => {name: faxpex5_username,password: faxpex5_password}
            }})
          command=self.options.get_next_command(ACTIONS)
          case command
          when :node
            return self.entity_action(api_v5,'nodes',nil,:id,nil,true)
          when :package
            command=self.options.get_next_command([:list,:show,:send,:receive])
            case command
            when :list
              parameters=self.options.get_option(:value,:optional)
              return {:type => :object_list, :data=>api_v5.read('packages',parameters)[:data]['packages']}
            when :show
              id=self.options.get_option(:id,:mandatory)
              return {:type => :single_object, :data=>api_v5.read("packages/#{id}")[:data]}
            when :send
              parameters=self.options.get_option(:value,:mandatory)
              raise CliBadArgument,'package value must be hash, refer to API' unless parameters.is_a?(Hash)
              package=api_v5.create('packages',parameters)[:data]
              transfer_spec=api_v5.create("packages/#{package['id']}/transfer_spec/upload",{transfer_type: 'Connect'})[:data]
              transfer_spec.delete('authentication')
              return Main.result_transfer(self.transfer.start(transfer_spec,{:src=>:node_gen3}))
            when :receive
              pkg_type='received'
              pack_id=self.options.get_option(:id,:mandatory)
              package_ids=[pack_id]
              skip_ids_data=[]
              skip_ids_persistency=nil
              if self.options.get_option(:once_only,:mandatory)
                skip_ids_persistency=PersistencyFile.new(
                data: skip_ids_data,
                ids:  ['faspex_recv',self.options.get_option(:url,:mandatory),self.options.get_option(:username,:mandatory),pkg_type])
              end
              if pack_id.eql?(VAL_ALL)
                # todo: if packages have same name, they will overwrite
                parameters=self.options.get_option(:value,:optional)
                parameters||={"type"=>"received","subtype"=>"mypackages","limit"=>1000}
                raise CliBadArgument,'value filter must be hash (API GET)' unless parameters.is_a?(Hash)
                package_ids=api_v5.read('packages',parameters)[:data]['packages'].map{|p|p['id']}
                package_ids.select!{|i|!skip_ids_data.include?(i)}
              end
              result_transfer=[]
              package_ids.each do |id|
                # TODO: allow from sent as well ?
                transfer_spec=api_v5.create("packages/#{id}/transfer_spec/download",{transfer_type: 'Connect', type: pkg_type})[:data]
                transfer_spec.delete('authentication')
                statuses=self.transfer.start(transfer_spec,{:src=>:node_gen3})
                result_transfer.push({'package'=>id,'status'=>statuses.map{|i|i.to_s}.join(',')})
                # skip only if all sessions completed
                skip_ids_data.push(id) if TransferAgent.session_status(statuses).eql?(:success)
              end
              skip_ids_persistency.save unless skip_ids_persistency.nil?
              return {:type=>:object_list,:data=>result_transfer}
            end
          end
        end
      end
    end # Plugins
  end # Cli
end # Asperalm
