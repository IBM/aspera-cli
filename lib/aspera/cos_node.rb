# frozen_string_literal: true

require 'aspera/log'
require 'aspera/rest'
require 'xmlsimple'

module Aspera
  class CosNode < Rest
    attr_reader :add_ts
    IBM_CLOUD_TOKEN_URL = 'https://iam.cloud.ibm.com/identity'
    TOKEN_FIELD = 'delegated_refresh_token'
    def initialize(bucket_name,storage_endpoint,instance_id,api_key,auth_url=IBM_CLOUD_TOKEN_URL)
      @auth_url = auth_url
      @api_key = api_key
      s3_api = Aspera::Rest.new({
        base_url:       storage_endpoint,
        not_auth_codes: ['401','403'], # error codes when not authorized
        headers:        {'ibm-service-instance-id' => instance_id},
        auth:           {
        type:     :oauth2,
        base_url: @auth_url,
        crtype:   :generic,
        generic:  {
        grant_type:    'urn:ibm:params:oauth:grant-type:apikey',
        response_type: 'cloud_iam',
        apikey:        @api_key
      }}})
      # read FASP connection information for bucket
      xml_result_text = s3_api.call({operation: 'GET',subpath: bucket_name,headers: {'Accept' => 'application/xml'},url_params: {'faspConnectionInfo' => nil}})[:http].body
      ats_info = XmlSimple.xml_in(xml_result_text, {'ForceArray' => false})
      Aspera::Log.dump('ats_info',ats_info)
      super({
        base_url: ats_info['ATSEndpoint'],
        auth:     {
        type:     :basic,
        username: ats_info['AccessKey']['Id'],
        password: ats_info['AccessKey']['Secret']}})
      # prepare transfer spec addition
      @add_ts = {'tags' => {'aspera' => {'node' => {'storage_credentials' => {
        'type'  => 'token',
        'token' => {TOKEN_FIELD => nil}
        }}}}}
      generate_token
    end

    # potentially call this if delegated token is expired
    def generate_token
      # OAuth API to get delegated token
      delegated_oauth = Oauth.new({
        type:        :oauth2,
        base_url:    @auth_url,
        token_field: TOKEN_FIELD,
        crtype:      :generic,
        generic:     {
        grant_type:          'urn:ibm:params:oauth:grant-type:apikey',
        response_type:       'delegated_refresh_token',
        apikey:              @api_key,
        receiver_client_ids: 'aspera_ats'
      }})
      # get delagated token to be placed in rest call header and in transfer tags
      @add_ts['tags']['aspera']['node']['storage_credentials']['token'][TOKEN_FIELD] = delegated_oauth.get_authorization.gsub(/^Bearer /,'')
      @params[:headers] = {'X-Aspera-Storage-Credentials' => JSON.generate(@add_ts['tags']['aspera']['node']['storage_credentials'])}
    end
  end
end
