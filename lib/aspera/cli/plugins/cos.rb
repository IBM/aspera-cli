require 'aspera/cli/plugins/node'
require 'aspera/cli/plugin'
require 'xmlsimple'

module Aspera
  module Cli
    module Plugins
      class Cos < Plugin
        # IBM Cloud authentication : + token
        IBM_CLOUD_OAUTH_URL='https://iam.cloud.ibm.com/identity'
        private_constant :IBM_CLOUD_OAUTH_URL
        def initialize(env)
          super(env)
          @service_creds=nil
          self.options.add_opt_simple(:bucket,'IBM Cloud Object storage bucket')
          self.options.add_opt_simple(:endpoint,'storage endpoint url')
          self.options.add_opt_simple(:apikey,'storage API key')
          self.options.add_opt_simple(:crn,'ressource instance id')
          #self.options.add_opt_simple(:oauth,'Oauth url')
          self.options.add_opt_simple(:service_credentials,'IBM Cloud service credentials (Hash)')
          self.options.add_opt_simple(:region,'IBM Cloud Object storage region')
        end

        ACTIONS=[:node]

        def execute_action
          command=self.options.get_next_command(ACTIONS)
          case command
          when :node
            bucket_name=self.options.get_option(:bucket,:mandatory)
            # get service credentials, Hash, e.g. @json:@file:...
            service_credentials=self.options.get_option(:service_credentials,:optional)
            storage_endpoint=self.options.get_option(:endpoint,:optional)
            raise "one of: endpoint or service_credentials is required" if service_credentials.nil? and storage_endpoint.nil?
            raise "endpoint and service_credentials are mutually exclusive" unless service_credentials.nil? or storage_endpoint.nil?
            if service_credentials.nil?
              serv_cred_storage_api_key = self.options.get_option(:apikey,:mandatory)
              instance_id = self.options.get_option(:crn,:mandatory)
            else
              # check necessary contents
              raise CliBadArgument,'service_credentials must be a Hash' unless service_credentials.is_a?(Hash)
              ['apikey','resource_instance_id','endpoints'].each do |field|
                raise CliBadArgument,"service_credentials must have a field: #{field}" unless service_credentials.has_key?(field)
              end
              Aspera::Log.dump('service_credentials',service_credentials)
              # get options
              bucket_region=self.options.get_option(:region,:mandatory)
              # get API key from service credentials
              serv_cred_storage_api_key=service_credentials['apikey']
              instance_id=service_credentials['resource_instance_id']
              # read endpoints from service provided in service credentials
              endpoints=Aspera::Rest.new({:base_url=>service_credentials['endpoints']}).read('')[:data]
              Aspera::Log.dump('endpoints',endpoints)
              storage_endpoint=endpoints.dig('service-endpoints','regional',bucket_region,'public',bucket_region)
              raise "no such region: #{bucket_region}" if storage_endpoint.nil?
              storage_endpoint='https://'+storage_endpoint
            end

            s3_api=Aspera::Rest.new({
              :base_url => storage_endpoint,
              :not_auth_codes => ['401','403'],
              :headers  => {'ibm-service-instance-id' => instance_id},
              :auth     => {
              :type       => :oauth2,
              :base_url   => IBM_CLOUD_OAUTH_URL,
              :grant      => :ibm_apikey,
              :api_key    => serv_cred_storage_api_key
              }})
            # read FASP connection information for bucket
            xml_result_text=s3_api.call({:operation=>'GET',:subpath=>bucket_name,:headers=>{'Accept'=>'application/xml'},:url_params=>{'faspConnectionInfo'=>nil}})[:http].body
            ats_info=XmlSimple.xml_in(xml_result_text, {'ForceArray' => false})
            Aspera::Log.dump('ats_info',ats_info)
            # get delegated token
            delegated_oauth=Oauth.new({
              :type       => :oauth2,
              :base_url   => IBM_CLOUD_OAUTH_URL,
              :grant      => :delegated_refresh,
              :api_key    => serv_cred_storage_api_key,
              :token_field=> 'delegated_refresh_token'
            })
            # to be placed in rest call header and in transfer tags
            aspera_storage_credentials={
              'type'  => 'token',
              'token' => {'delegated_refresh_token'=>delegated_oauth.get_authorization().gsub(/^Bearer /,'')}
            }
            # transfer spec addition
            add_ts={'tags'=>{'aspera'=>{'node'=>{'storage_credentials'=>aspera_storage_credentials}}}}
            # set a general addon to transfer spec
            # here we choose to use the add_request_param
            #self.transfer.option_transfer_spec_deep_merge(add_ts)
            api_node=Rest.new({
              :base_url => ats_info['ATSEndpoint'],
              :headers  => {'X-Aspera-Storage-Credentials'=>JSON.generate(aspera_storage_credentials)},
              :auth     => {
              :type     => :basic,
              :username => ats_info['AccessKey']['Id'],
              :password => ats_info['AccessKey']['Secret']}})
            #command=self.options.get_next_command(Node::ACTIONS)
            #command=self.options.get_next_command(Node::COMMON_ACTIONS)
            command=self.options.get_next_command([:upload,:download,:info,:access_key,:api_details])
            node_plugin=Node.new(@agents.merge(skip_basic_auth_options: true, node_api: api_node, add_request_param: add_ts))
            return node_plugin.execute_action(command)
          end
        end
      end
    end
  end
end
