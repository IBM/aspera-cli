# frozen_string_literal: true

require 'aspera/environment'
require 'aspera/log'
require 'aspera/assert'
require 'erb'

module Aspera
  module Cli
    # Email service injected into Context as :mailer so that any component
    # (TransferAgent, plugins, …) can send emails via SMTP and ERB templates.
    # Provides :smtp, :notify_to, :notify_template options via the Options manager.
    class Mailer
      SMTP_CONF_PARAMS = %i[server tls ssl port domain username password from_name from_email].freeze
      SMTP_BOOL_PARAMS = %i[tls ssl].freeze
      SMTP_INT_PARAMS  = %i[port].freeze
      SMTP_STR_PARAMS  = %i[server domain username password from_email from_name].freeze

      # @param options     [Options]  CLI options manager (provides :smtp, :notify_to, :notify_template)
      # @param main_folder [String]   application main folder (unused directly but kept for symmetry)
      def initialize(options, main_folder)
        @options     = options
        @main_folder = main_folder
      end

      # @return [Options]
      attr_reader :options

      # @return [Hash] email server settings with defaults applied
      def email_settings
        smtp = options.get_option(:smtp, mandatory: true)
        # Change keys from string into symbol
        smtp = smtp.symbolize_keys
        unsupported = smtp.keys - SMTP_CONF_PARAMS
        raise Cli::Error, "Unsupported SMTP parameter: #{unsupported.join(', ')}, use: #{SMTP_CONF_PARAMS.join(', ')}" unless unsupported.empty?
        # Boolean fields must be actual booleans, not strings like "false"
        SMTP_BOOL_PARAMS.each do |k|
          Aspera.assert_values(smtp[k], [true, false], type: Cli::Error){"smtp.#{k}"} if smtp.key?(k)
        end
        SMTP_INT_PARAMS.each do |k|
          Aspera.assert_type(smtp[k], Integer, type: Cli::Error){"smtp.#{k}"} if smtp.key?(k)
        end
        SMTP_STR_PARAMS.each do |k|
          Aspera.assert_type(smtp[k], String, type: Cli::Error){"smtp.#{k}"} if smtp.key?(k)
        end
        # smtp[:ssl] = nil (false)
        smtp[:tls] = !smtp[:ssl] unless smtp.key?(:tls)
        smtp[:port] ||= if smtp[:tls]
          587
        elsif smtp[:ssl]
          465
        else
          25
        end
        smtp[:from_email] ||= smtp[:username] if smtp.key?(:username)
        smtp[:from_name] ||= smtp[:from_email].sub(/@.*$/, '').gsub(/[^a-zA-Z]/, ' ').capitalize if smtp.key?(:username)
        smtp[:domain] ||= smtp[:from_email].sub(/^.*@/, '') if smtp.key?(:from_email)
        %i[server port domain].each do |n|
          Aspera.assert(smtp.key?(n)){"Missing mandatory smtp parameter: #{n}"}
        end
        Log.log.debug{"smtp=#{smtp}"}
        return smtp
      end

      # Send email using ERB template
      # @param email_template_default [String] default template, can be overridden by option
      # @param values [Hash] values to be used in template, keys with default: to, from_name, from_email
      def send_email_template(email_template_default: nil, values: {})
        values[:to] ||= options.get_option(:notify_to, mandatory: true)
        notify_template = options.get_option(:notify_template, mandatory: email_template_default.nil?) || email_template_default
        mail_conf = email_settings
        values[:from_name] ||= mail_conf[:from_name]
        values[:from_email] ||= mail_conf[:from_email]
        %i[to from_email].each do |n|
          Aspera.assert_type(values[n], String){"Missing email parameter: #{n} in config"}
        end
        start_options = [mail_conf[:domain]]
        start_options.push(mail_conf[:username], mail_conf[:password], :login) if mail_conf.key?(:username) && mail_conf.key?(:password)
        template_binding = Environment.empty_binding
        values.each do |k, v|
          Aspera.assert_type(k, Symbol)
          template_binding.local_variable_set(k, v)
        end
        msg_with_headers = ERB.new(notify_template).result(template_binding)
        Log.dump(:msg_with_headers, msg_with_headers)
        require 'net/smtp'
        smtp = Net::SMTP.new(mail_conf[:server], mail_conf[:port])
        smtp.enable_starttls if mail_conf[:tls]
        smtp.enable_tls if mail_conf[:ssl]
        smtp.start(*start_options) do |smtp_session|
          smtp_session.send_message(msg_with_headers, values[:from_email], values[:to])
        end
        nil
      end
    end
  end
end
