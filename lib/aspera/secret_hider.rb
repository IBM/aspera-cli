# frozen_string_literal: true

# cspell:ignore FILEPASS
require 'logger'

module Aspera
  # remove secret from logs and output
  class SecretHider
    # configurable:
    ADDITIONAL_KEYS_TO_HIDE = []
    # display string for hidden secrets
    HIDDEN_PASSWORD = '🔑'
    # env vars for ascp with secrets
    ASCP_ENV_SECRETS = %w[ASPERA_SCP_PASS ASPERA_SCP_KEY ASPERA_SCP_FILEPASS ASPERA_PROXY_PASS ASPERA_SCP_TOKEN].freeze
    # keys in hash that contain secrets
    KEY_SECRETS = %w[password secret passphrase _key apikey crn token].freeze
    HTTP_SECRETS = %w[Authorization].freeze
    ALL_SECRETS = [ASCP_ENV_SECRETS, KEY_SECRETS, HTTP_SECRETS].flatten.freeze
    KEY_FALSE_POSITIVES = [/^access_key$/, /^fallback_private_key$/].freeze
    # regex that define named captures :begin and :end
    REGEX_LOG_REPLACES = [
      # CLI manager get/set options
      /(?<begin>[sg]et (?:#{KEY_SECRETS.join('|')})=).*(?<end>)/,
      # env var ascp exec
      /(?<begin> (?:#{ASCP_ENV_SECRETS.join('|')})=)(\\.|[^ ])*(?<end> )/,
      # rendered JSON or Ruby
      /(?<begin>(?:(?<quote>["'])|:)[^"':=]*(?:#{ALL_SECRETS.join('|')})[^"':=]*\k<quote>?(?:=>|:) *")[^"]+(?<end>")/,
      # logged data
      /(?<begin>(?:#{ALL_SECRETS.join('|')})[ =:]+).*(?<end>$)/,
      # private key values
      /(?<begin>--+BEGIN [^-]+ KEY--+)[[:ascii:]]+?(?<end>--+?END [^-]+ KEY--+)/,
      # cred in http dump
      /(?<begin>(?:#{HTTP_SECRETS.join('|')}): )[^\\]+(?<end>\\)/i
    ].freeze
    private_constant :HIDDEN_PASSWORD, :ASCP_ENV_SECRETS, :KEY_SECRETS, :HTTP_SECRETS, :ALL_SECRETS, :KEY_FALSE_POSITIVES, :REGEX_LOG_REPLACES
    @log_secrets = false
    class << self
      attr_accessor :log_secrets

      def log_formatter(original_formatter)
        original_formatter ||= Logger::Formatter.new
        # NOTE: that @log_secrets may be set AFTER this init is done, so it's done at runtime
        return lambda do |severity, date_time, program_name, msg|
          if msg.is_a?(String) && !@log_secrets
            REGEX_LOG_REPLACES.each do |reg_ex|
              msg = msg.gsub(reg_ex){"#{Regexp.last_match(:begin)}#{HIDDEN_PASSWORD}#{Regexp.last_match(:end)}"}
            end
          end
          original_formatter.call(severity, date_time, program_name, msg)
        end
      end

      def secret?(keyword, value)
        keyword = keyword.to_s if keyword.is_a?(Symbol)
        # only Strings can be secrets, not booleans, or hash, arrays
        return false unless keyword.is_a?(String) && value.is_a?(String)
        # those are not secrets
        return false if KEY_FALSE_POSITIVES.any?{|f|f.match?(keyword)}
        return true if ADDITIONAL_KEYS_TO_HIDE.include?(keyword)
        # check if keyword (name) contains an element that designate it as a secret
        ALL_SECRETS.any?{|kw|keyword.include?(kw)}
      end

      def deep_remove_secret(obj)
        case obj
        when Array
          obj.each{|i|deep_remove_secret(i)}
        when Hash
          obj.each do |k, v|
            if secret?(k, v)
              obj[k] = HIDDEN_PASSWORD
            elsif obj[k].is_a?(Hash)
              deep_remove_secret(obj[k])
            end
          end
        end
        return obj
      end
    end
  end
end
