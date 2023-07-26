# frozen_string_literal: true

require 'logger'

module Aspera
  # remove secret from logs and output
  class SecretHider
    # display string for hidden secrets
    HIDDEN_PASSWORD = '🔑'
    # env vars for ascp with secrets
    ASCP_ENV_SECRETS = %w[ASPERA_SCP_PASS ASPERA_SCP_KEY ASPERA_SCP_FILEPASS ASPERA_PROXY_PASS ASPERA_SCP_TOKEN].freeze
    # keys in hash that contain secrets
    KEY_SECRETS = %w[password secret passphrase _key apikey crn token].freeze
    ALL_SECRETS = [ASCP_ENV_SECRETS, KEY_SECRETS].flatten.freeze
    FALSE_POSITIVES = [/^access_key$/].freeze
    # regex that define named captures :begin and :end
    REGEX_LOG_REPLACES = [
      # CLI manager get/set options
      /(?<begin>[sg]et (#{KEY_SECRETS.join('|')})=).*(?<end>)/,
      # env var ascp exec
      /(?<begin> (#{ASCP_ENV_SECRETS.join('|')})=)(\\.|[^ ])*(?<end> )/,
      # rendered JSON
      /(?<begin>["':][^"]*(#{ALL_SECRETS.join('|')})[^"]*["']?[=>: ]+")[^"]+(?<end>")/,
      # option "secret"
      /(?<begin>"[^"]*(secret)[^"]*"=>{)[^}]+(?<end>})/,
      # option "secrets"
      /(?<begin>(secrets)={)[^}]+(?<end>})/,
      # private key values
      /(?<begin>--+BEGIN .+ KEY--+)[[:ascii:]]+?(?<end>--+?END .+ KEY--+)/
    ].freeze
    private_constant :HIDDEN_PASSWORD, :ASCP_ENV_SECRETS, :KEY_SECRETS, :ALL_SECRETS, :REGEX_LOG_REPLACES
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
        return false if FALSE_POSITIVES.any?{|f|f.match?(keyword)}
        # check if keyword (name) contains an element that designate it as a secret
        ALL_SECRETS.any?{|kw|keyword.include?(kw)}
      end

      def deep_remove_secret(obj, is_name_value: false)
        case obj
        when Array
          if is_name_value
            obj.each do |i|
              i['value'] = HIDDEN_PASSWORD if secret?(i['parameter'], i['value'])
            end
          else
            obj.each{|i|deep_remove_secret(i)}
          end
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
