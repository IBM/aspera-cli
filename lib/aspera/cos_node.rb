# frozen_string_literal: true

require 'aspera/log'
require 'aspera/assert'
require 'aspera/rest'
require 'aspera/oauth'
require 'xmlsimple'

module Aspera
  class CosNode < Aspera::Node
    IBM_CLOUD_TOKEN_URL = 'https://iam.cloud.ibm.com/identity'
    TOKEN_FIELD = 'delegated_refresh_token'
    class << self
      def parameters_from_svc_credentials(service_credentials, bucket_region)
        # check necessary contents
        Aspera.assert_type(service_credentials, Hash){'service_credentials'}
        Aspera::Log.dump('service_credentials', service_credentials)
        %w[apikey resource_instance_id endpoints].each do |field|
          Aspera.assert(service_credentials.key?(field)){"service_credentials must have a field: #{field}"}
        end
        # read endpoints from service provided in service credentials
        endpoints = Aspera::Rest.new({base_url: service_credentials['endpoints']}).read('')[:data]
        Aspera::Log.dump('endpoints', endpoints)
        endpoint = endpoints.dig('service-endpoints', 'regional', bucket_region, 'public', bucket_region)
        raise "no such region: #{bucket_region}" if endpoint.nil?
        return {
          instance_id: service_credentials['resource_instance_id'],
          api_key:     service_credentials['apikey'],
          endpoint:    endpoint
        }
      end
    end

    def initialize(instance_id:, api_key:, endpoint:, bucket:, auth_url: IBM_CLOUD_TOKEN_URL)
      Aspera.assert_type(instance_id, String){'resource instance id (crn)'}
      Aspera.assert_type(endpoint, String){'endpoint'}
      endpoint = "https://#{endpoint}" unless endpoint.start_with?('http')
      @auth_url = auth_url
      @api_key = api_key
      s3_api = Aspera::Rest.new({
        base_url:       endpoint,
        not_auth_codes: %w[401 403], # error codes when not authorized
        headers:        {'ibm-service-instance-id' => instance_id},
        auth:           {
          type:          :oauth2,
          base_url:      @auth_url,
          grant_method:  :generic,
          grant_options: {
            grant_type:    'urn:ibm:params:oauth:grant-type:apikey',
            response_type: 'cloud_iam',
            apikey:        @api_key
          }}})
      # read FASP connection information for bucket
      xml_result_text = s3_api.call(
        operation: 'GET',
        subpath: bucket,
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
      delegated_oauth = Oauth.new(
        base_url:     @auth_url,
        token_field:  TOKEN_FIELD,
        grant_method: :generic,
        grant_options:      {
          grant_type:          'urn:ibm:params:oauth:grant-type:apikey',
          response_type:       'delegated_refresh_token',
          apikey:              @api_key,
          receiver_client_ids: 'aspera_ats'
        })
      # get delegated token to be placed in rest call header and in transfer tags
      @storage_credentials['token'][TOKEN_FIELD] = Oauth.bearer_extract(delegated_oauth.get_authorization)
      @params[:headers] = {'X-Aspera-Storage-Credentials' => JSON.generate(@storage_credentials)}
    end
  end
end
