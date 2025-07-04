# frozen_string_literal: true

require 'aspera/transfer/error'
require 'aspera/rest'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/cli/info'
require 'net/ssh'
require 'openssl'

module Aspera
  module Cli
    # Provide hints on errors
    class Hints
      # Well know issues that users may get
      ERROR_HINTS = [
        {
          exception:   Transfer::Error,
          match:       'Remote host is not who we expected',
          remediation: [
            'For this specific error, refer to:',
            "#{Info::SRC_URL}#error-remote-host-is-not-who-we-expected",
            'Add this to arguments:',
            %q{--ts=@json:'{"sshfp":null}'"}
          ]
        },
        {
          exception:   RestCallError,
          match:       /Signature has expired/,
          remediation: [
            'There is too much time difference between your computer and the server',
            'Check your local time: is time synchronization enabled?'
          ]
        },
        {
          exception:   OpenSSL::SSL::SSLError,
          match:       /(does not match the server certificate|certificate verify failed)/,
          remediation: [
            'You can ignore SSL errors with option:',
            '--insecure=yes'
          ]
        },
        {
          exception:   OpenSSL::PKey::RSAError,
          match:       /Neither PUB key nor PRIV key/,
          remediation: [
            'option: private_key expects a key PEM value, not path to file',
            'if you provide a path: prefix with @file:',
            'e.g. --private-key=@file:/path/to/key.pem'
          ]
        },
        {
          exception:   RuntimeError,
          match:       /unexpected last event type: INIT/,
          remediation: [
            'ascp exited unexpectedly',
            'it might be due to SSH handshake failure',
            'one can check SSH connection using ssh command'
          ]
        },
        {
          exception:   RuntimeError,
          match:       /Wrong remote host:/,
          remediation: [
            'If remote node is Cloud Pak For Integration',
            'Make sure that a LoadBalancer is active on cluster',
            'Check the external address of Aspera tcp-proxy pod'
          ]
        }
      ]

      private_constant :ERROR_HINTS

      class << self
        def hint_for(error, formatter)
          ERROR_HINTS.each do |hint|
            next unless error.is_a?(hint[:exception])
            message = error.message
            matches = hint[:match]
            matches = [matches] unless matches.is_a?(Array)
            matches.each do |m|
              Aspera.assert_values(m.class, [String, Regexp])
              case m
              when String
                next unless message.eql?(m)
              when Regexp
                next unless message.match?(m)
              else Aspera.error_unexpected_value(m)
              end
              remediation = hint[:remediation]
              remediation = [remediation] unless remediation.is_a?(Array)
              remediation.each{ |r| formatter.display_message(:error, "#{Formatter::HINT_FLASH} #{r}")}
              break
            end
          end
        end
      end
    end
  end
end
