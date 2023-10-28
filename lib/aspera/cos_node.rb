# frozen_string_literal: true

require 'aspera/log'
require 'aspera/rest'
require 'aspera/oauth'
require 'xmlsimple'

module Aspera
  class CosNode < Aspera::Node
    class << self
      def parameters_from_svc_creds(service_credentials, bucket_region)
        # check necessary contents
        raise 'service_credentials must be a Hash' unless service_credentials.is_a?(Hash)
        %w[apikey resource_instance_id endpoints].each do |field|
          raise "service_credentials must have a field: #{field}" unless service_credentials.key?(field)
        end
        Aspera::Log.dump('service_credentials', service_credentials)
        # read endpoints from service provided in service credentials
        endpoints = Aspera::Rest.new({base_url: service_credentials['endpoints']}).read('')[:data]
        Aspera::Log.dump('endpoints', endpoints)
        storage_endpoint = endpoints.dig('service-endpoints', 'regional', bucket_region, 'public', bucket_region)
        raise "no such region: #{bucket_region}" if storage_endpoint.nil?
        return {
          instance_id:      service_credentials['resource_instance_id'],
          service_api_key:  service_credentials['apikey'],
          storage_endpoint: "https://#{storage_endpoint}"
        }
      end
    end
    IBM_CLOUD_TOKEN_URL = 'https://iam.cloud.ibm.com/identity'
    TOKEN_FIELD = 'delegated_refresh_token'

    def initialize(bucket_name, storage_endpoint, instance_id, api_key, auth_url= IBM_CLOUD_TOKEN_URL)
      @auth_url = auth_url
      @api_key = api_key
      s3_api = Aspera::Rest.new({
        base_url:       storage_endpoint,
        not_auth_codes: %w[401 403], # error codes when not authorized
        headers:        {'ibm-service-instance-id' => instance_id},
        auth:           {
          type:         :oauth2,
          base_url:     @auth_url,
          grant_method: :generic,
          generic:      {
            grant_type:    'urn:ibm:params:oauth:grant-type:apikey',
            response_type: 'cloud_iam',
            apikey:        @api_key
          }}})
      # read FASP connection information for bucket
      xml_result_text = s3_api.call(
        operation: 'GET',
        subpath: bucket_name,
        headers: {'Accept' => 'application/xml'},
        url_params: {'faspConnectionInfo' => nil}
      )[:http].body
      ats_info = XmlSimple.xml_in(xml_result_text, {'ForceArray' => false})
      Aspera::Log.dump('ats_info', ats_info)
      @storage_credentials = {
        'type'  => 'token',
        'token' => {TOKEN_FIELD => nil}
      }
      super(
        params: {
          base_url: ats_info['ATSEndpoint'],
          auth:     {
            type:     :basic,
            username: ats_info['AccessKey']['Id'],
            password: ats_info['AccessKey']['Secret']}},
        add_tspec: {'tags'=>{Fasp::TransferSpec::TAG_RESERVED=>{'node'=>{'storage_credentials'=>@storage_credentials}}}})
      # update storage_credentials AND Rest params
      generate_token
    end

    # potentially call this if delegated token is expired
    def generate_token
      # OAuth API to get delegated token
      delegated_oauth = Oauth.new({
        type:         :oauth2,
        base_url:     @auth_url,
        token_field:  TOKEN_FIELD,
        grant_method: :generic,
        generic:      {
          grant_type:          'urn:ibm:params:oauth:grant-type:apikey',
          response_type:       'delegated_refresh_token',
          apikey:              @api_key,
          receiver_client_ids: 'aspera_ats'
        }})
      # get delegated token to be placed in rest call header and in transfer tags
      @storage_credentials['token'][TOKEN_FIELD] = OAuth.bearer_extract(delegated_oauth.get_authorization)
      @params[:headers] = {'X-Aspera-Storage-Credentials' => JSON.generate(@storage_credentials)}
    end
  end
end
