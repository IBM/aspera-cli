# frozen_string_literal: true

require 'aspera/rest'
require 'aspera/oauth/base'
require 'digest'

module Aspera
  # Implement OAuth eschange for Faspex public link
  class FaspexPubLink < OAuth::Base
    class << self
      attr_accessor :additionnal_info
    end
    # @param context         The `context` query parameter in public link
    # @param redirect_uri    URI of web UI login
    # @param path_authorize  Path to provide passcode
    def initialize(
      context:,
      redirect_uri:,
      path_authorize: 'authorize_public_link',
      **base_params
    )
      # a unique identifier could also be the passcode inside
      super(**base_params, cache_ids: [Digest::SHA256.hexdigest(context)[0..23]])
      @context = context
      @redirect_uri = redirect_uri
      @path_authorize = path_authorize
    end

    def create_token
      # Exchange context (passcode) for code
      resp = api.call(
        operation: 'GET',
        subpath:   @path_authorize,
        query: {
          response_type: :code,
          state:         @context,
          client_id:     client_id,
          redirect_uri:  @redirect_uri
        },
        exception: false
      )
      # code / state located in redirected URL query
      info = Rest.query_to_h(URI.parse(resp[:http]['Location']).query)
      Log.dump(:info, info)
      raise Error, info['action_message'] if info['action_message']
      Aspera.assert(info['code']){'Missing code in answer'}
      # Exchange code for token
      return create_token_call(optional_scope_client_id.merge(
        grant_type:   'authorization_code',
        code:         info['code'],
        redirect_uri: @redirect_uri
      ))
    end
  end
  OAuth::Factory.instance.register_token_creator(FaspexPubLink)
  module Api
    class Faspex < Aspera::Rest
      # endpoint for authentication API
      PATH_AUTH = 'auth'
      PATH_API_V5 = 'api/v5'
      PATH_HEALTH = 'configuration/ping'
      private_constant :PATH_API_V5,
        :PATH_HEALTH,
        :PATH_AUTH
      RECIPIENT_TYPES = %w[user workgroup external_user distribution_list shared_inbox].freeze
      PACKAGE_TERMINATED = %w[completed failed].freeze
      # list of supported mailbox types (to list packages)
      API_LIST_MAILBOX_TYPES = %w[inbox inbox_history inbox_all inbox_all_history outbox outbox_history pending pending_history all].freeze
      # PACKAGE_SEND_FROM_REMOTE_SOURCE = 'remote_source'
      # Faspex API v5: get transfer spec for connect
      TRANSFER_CONNECT = 'connect'
      ADMIN_RESOURCES = %i[
        accounts distribution_lists contacts jobs workgroups shared_inboxes nodes oauth_clients registrations saml_configs
        metadata_profiles email_notifications alternate_addresses webhooks
      ].freeze
      # states for jobs not in final state
      JOB_RUNNING = %w[queued working].freeze
      PATH_STANDARD_ROOT = '/aspera/faspex'
      PATH_API_DETECT = "#{PATH_API_V5}/#{PATH_HEALTH}"
      # OAuth methods supported
      STD_AUTH_TYPES = %i[web jwt boot].freeze
      HEADER_ITERATION_TOKEN = 'X-Aspera-Next-Iteration-Token'
      HEADER_FASPEX_VERSION = 'X-IBM-Aspera'
      EMAIL_NOTIF_LIST = %w[
        welcome_email
        forgot_password
        package_received
        package_received_cc
        package_sent_cc
        package_downloaded
        package_downloaded_cc
        workgroup_package
        upload_result
        upload_result_cc
        relay_started_cc
        relay_finished_cc
        relay_error_cc
        shared_inbox_invitation
        shared_inbox_submit
        personal_invitation
        personal_submit
        account_approved
        account_denied
        package_file_processing_failed_sender
        package_file_processing_failed_recipient
        relay_failed_admin
        relay_failed
        admin_sync_failed
        sync_failed
        account_exist
        mfa_code
      ]
      class << self
        # @return true if the URL is a public link
        def public_link?(url)
          url.include?('?context=')
        end
      end
      attr_reader :pub_link_context

      def initialize(
        url:,
        auth:,
        password: nil,
        client_id: nil,
        client_secret: nil,
        redirect_uri: nil,
        username: nil,
        private_key: nil,
        passphrase: nil
      )
        auth = :public_link if self.class.public_link?(url)
        @pub_link_context = nil
        super(**
          case auth
          when :public_link
            # Get URL of final redirect of public link
            redir_url = Rest.new(base_url: url, redirect_max: 3).call(operation: 'GET')[:http].uri.to_s
            Log.dump(:redir_url, redir_url, level: :trace1)
            # get context from query
            encoded_context = Rest.query_to_h(URI.parse(redir_url).query)['context']
            raise ParameterError, 'Bad faspex5 public link, missing context in query' if encoded_context.nil?
            # public link information (contains passcode and allowed usage)
            @pub_link_context = JSON.parse(Base64.decode64(encoded_context))
            Log.dump(:pub_link_context, @pub_link_context, level: :trace1)
            # Get the base url, i.e. .../aspera/faspex
            base_url = redir_url.gsub(%r{/public/.*}, '').gsub(/\?.*/, '')
            # Get web UI client_id and redirect_uri
            # TODO: change this for something more reliable
            config = JSON.parse(Rest.new(base_url: "#{base_url}/config.js", redirect_max: 3).call(operation: 'GET')[:data].sub(/^[^=]+=/, '').gsub(/([a-z_]+):/, '"\1":').delete("\n ").tr("'", '"')).symbolize_keys
            Log.dump(:configjs, config)
            {
              base_url: "#{base_url}/#{PATH_API_V5}",
              auth:     {
                type:         :oauth2,
                base_url:     "#{base_url}/#{PATH_AUTH}",
                grant_method: :faspex_pub_link,
                context:      encoded_context,
                client_id:    config[:client_id],
                redirect_uri: config[:redirect_uri]
              }
            }
          # old: headers:  {'Passcode' => @pub_link_context['passcode']}
          when :boot
            Aspera.assert(password, type: ParameterError){'Missing password'}
            # the password here is the token copied directly from browser in developer mode
            {
              base_url: "#{url}/#{PATH_API_V5}",
              headers:  {'Authorization' => password}
            }
          when :web
            Aspera.assert(client_id, type: ParameterError){'Missing client_id'}
            Aspera.assert(redirect_uri, type: ParameterError){'Missing redirect_uri'}
            # opens a browser and ask user to auth using web
            {
              base_url: "#{url}/#{PATH_API_V5}",
              auth:     {
                type:         :oauth2,
                base_url:     "#{url}/#{PATH_AUTH}",
                grant_method: :web,
                client_id:    client_id,
                redirect_uri: redirect_uri
              }
            }
          when :jwt
            Aspera.assert(client_id, type: ParameterError){'Missing client_id'}
            Aspera.assert(private_key, type: ParameterError){'Missing private_key'}
            {
              base_url: "#{url}/#{PATH_API_V5}",
              auth:     {
                type:            :oauth2,
                base_url:        "#{url}/#{PATH_AUTH}",
                grant_method:    :jwt,
                client_id:       client_id,
                payload:         {
                  iss: client_id, # issuer
                  aud: client_id, # audience (this field is not clear...)
                  sub: "user:#{username}" # subject is a user
                },
                private_key_obj: OpenSSL::PKey::RSA.new(private_key, passphrase),
                headers:         {typ: 'JWT'}
              }
            }
          else Aspera.error_unexpected_value(auth, type: ParameterError){'auth'}
          end
        )
      end

      def auth_api
        Rest.new(**params, base_url: base_url.sub(PATH_API_V5, PATH_AUTH))
      end
    end
  end
end
