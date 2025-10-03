# frozen_string_literal: true

require 'aspera/rest'

module Aspera
  module Api
    class Faspex < Aspera::Rest
      PATH_API_V5 = 'api/v5'
      PATH_HEALTH = 'configuration/ping'
      private_constant :PATH_API_V5,
        :PATH_HEALTH
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
      # endpoint for authentication API
      PATH_AUTH = 'auth'
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
        # Remove unnecessary trailing slashes
        url = url.chomp('/')
        auth = :public_link if self.class.public_link?(url)
        @pub_link_context = nil
        super(**
          case auth
          when :public_link
            # resolve any redirect
            resp = Rest.new(base_url: url, redirect_max: 3).call(operation: 'GET')
            redir_url = resp[:http].uri.to_s
            encoded_context = Rest.query_to_h(URI.parse(redir_url).query)['context']
            raise ArgumentError, 'Bad faspex5 public link, missing context in query' if encoded_context.nil?
            # public link information (allowed usage)
            @pub_link_context = JSON.parse(Base64.decode64(encoded_context))
            Log.dump(:pub_link_context, @pub_link_context, level: :trace1)
            # ok, we have the additional parameters, get the base url
            base_url = redir_url.gsub(%r{/public/.*}, '').gsub(/\?.*/, '')
            val = JSON.parse(Rest.new(base_url: "#{base_url}/config.js", redirect_max: 3).call(operation: 'GET')[:data].sub(/^[^=]+=/, '').gsub(/([a-z_]+):/, '"\1":').delete("\n ").tr("'", '"'))
            Log.dump(:datapage, val)
            {
              base_url: "#{base_url}/#{PATH_API_V5}",
              headers:  {'Passcode' => @pub_link_context['passcode']}
            }
          when :boot
            Aspera.assert(password, type: ArgumentError){'Missing password'}
            # the password here is the token copied directly from browser in developer mode
            {
              base_url: "#{url}/#{PATH_API_V5}",
              headers:  {'Authorization' => password}
            }
          when :web
            Aspera.assert(client_id, type: ArgumentError){'Missing client_id'}
            Aspera.assert(redirect_uri, type: ArgumentError){'Missing redirect_uri'}
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
            Aspera.assert(client_id, type: ArgumentError){'Missing client_id'}
            Aspera.assert(private_key, type: ArgumentError){'Missing private_key'}
            {
              base_url: "#{url}/#{PATH_API_V5}",
              auth:     {
                type:            :oauth2,
                grant_method:    :jwt,
                base_url:        "#{url}/#{PATH_AUTH}",
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
          else Aspera.error_unexpected_value(auth, type: ArgumentError){'auth'}
          end
        )
      end
    end
  end
end
