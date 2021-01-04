require 'aspera/log'
require 'aspera/rest'
require 'xmlsimple'

module Aspera
  class CosNode < Rest
    attr_reader :add_ts
    def initialize(bucket_name,storage_endpoint,instance_id,api_key,auth_url='https://iam.cloud.ibm.com/identity')
      s3_api=Aspera::Rest.new({
        :base_url => storage_endpoint,
        :not_auth_codes => ['401','403'],
        :headers  => {'ibm-service-instance-id' => instance_id},
        :auth     => {
        :type       => :oauth2,
        :base_url   => auth_url,
        :grant      => :ibm_apikey,
        :api_key    => api_key
        }})
      # read FASP connection information for bucket
      xml_result_text=s3_api.call({:operation=>'GET',:subpath=>bucket_name,:headers=>{'Accept'=>'application/xml'},:url_params=>{'faspConnectionInfo'=>nil}})[:http].body
      ats_info=XmlSimple.xml_in(xml_result_text, {'ForceArray' => false})
      Aspera::Log.dump('ats_info',ats_info)
      # get delegated token
      delegated_oauth=Oauth.new({
        :type       => :oauth2,
        :base_url   => auth_url,
        :grant      => :delegated_refresh,
        :api_key    => api_key,
        :token_field=> 'delegated_refresh_token'
      })
      # to be placed in rest call header and in transfer tags
      aspera_storage_credentials={
        'type'  => 'token',
        'token' => {'delegated_refresh_token'=>delegated_oauth.get_authorization().gsub(/^Bearer /,'')}
      }
      # transfer spec addition
      @add_ts={'tags'=>{'aspera'=>{'node'=>{'storage_credentials'=>aspera_storage_credentials}}}}
      # set a general addon to transfer spec
      # here we choose to use the add_request_param
      #self.transfer.option_transfer_spec_deep_merge(@add_ts)
      super({
        :base_url => ats_info['ATSEndpoint'],
        :headers  => {'X-Aspera-Storage-Credentials'=>JSON.generate(aspera_storage_credentials)},
        :auth     => {
        :type     => :basic,
        :username => ats_info['AccessKey']['Id'],
        :password => ats_info['AccessKey']['Secret']}})
    end
  end
end
