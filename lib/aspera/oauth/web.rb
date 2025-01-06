# frozen_string_literal: true

require 'aspera/oauth/base'
require 'aspera/environment'
require 'aspera/web_auth'
require 'aspera/assert'
module Aspera
  module OAuth
    # Authentication using Web browser
    class Web < Base
      # @param redirect_uri    url to receive the code after auth (to be exchanged for token)
      # @param path_authorize  path to login page on web app
      def initialize(
        redirect_uri:,
        path_authorize: 'authorize',
        **base_params
      )
        super(**base_params)
        @redirect_uri = redirect_uri
        @path_authorize = path_authorize
        uri = URI.parse(@redirect_uri)
        Aspera.assert(%w[http https].include?(uri.scheme)){'redirect_uri scheme must be http or https'}
        Aspera.assert(!uri.port.nil?){'redirect_uri must have a port'}
        # TODO: we could check that host is localhost or local address, as we are going to listen locally
      end

      def create_token
        # generate secure state to check later
        random_state = SecureRandom.uuid
        login_page_url = Rest.build_uri(
          "#{@api.base_url}/#{@path_authorize}",
          optional_scope_client_id.merge(response_type: 'code', redirect_uri: @redirect_uri, state: random_state))
        # here, we need a human to authorize on a web page
        Log.log.info{"login_page_url=#{login_page_url}".bg_red.gray}
        # start a web server to receive request code
        web_server = WebAuth.new(@redirect_uri)
        # start browser on login page
        Environment.instance.open_uri(login_page_url)
        # wait for code in request
        received_params = web_server.received_request
        Aspera.assert(random_state.eql?(received_params['state'])){'wrong received state'}
        # exchange code for token
        return create_token_call(optional_scope_client_id(add_secret: true).merge(
          grant_type:   'authorization_code',
          code:         received_params['code'],
          redirect_uri: @redirect_uri))
      end
    end
    Factory.instance.register_token_creator(Web)
  end
end
