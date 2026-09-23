# frozen_string_literal: true

# cspell:ignore FILEPASS
require 'logger'
require 'set'
require 'singleton'

module Aspera
  # remove secret from logs and output
  #
  # @!method self.instance
  #   Returns the singleton instance of SecretHider
  #   @return [SecretHider] the singleton instance
  class SecretHider
    include Singleton

    # display string for hidden secrets
    HIDDEN_PASSWORD = '🔑'
    # env vars for ascp with secrets
    ASCP_ENV_SECRETS = %w[ASPERA_SCP_PASS ASPERA_SCP_KEY ASPERA_SCP_FILEPASS ASPERA_PROXY_PASS ASPERA_SCP_TOKEN].freeze
    # keys in hash that contain secrets
    KEY_SECRETS = %w[password secret passphrase _key apikey crn token].freeze
    HTTP_SECRETS = %w[Authorization].freeze
    ALL_SECRETS = (ASCP_ENV_SECRETS + KEY_SECRETS + HTTP_SECRETS).freeze
    NON_ENV_SECRETS = (KEY_SECRETS + HTTP_SECRETS).freeze
    KEY_FALSE_POSITIVES = [/^access_key$/, /^fallback_private_key$/, /public_key$/, /^token_type$/].freeze
    # min length of hidden secrets, use `+` or `{n,}`
    SECRET_LENGTH = '{5,}'
    # regex that define named captures :begin and :end
    REGEX_LOG_REPLACES = [
      # private key values (place first)
      /(?<begin>--+BEGIN [^-]+ KEY--+)[[:ascii:]]+?(?<end>--+?END [^-]+ KEY--+)\n*/,
      # CLI manager get/set options
      /(?<begin>[sg]et (?:#{KEY_SECRETS.join('|')})=).*(?<end>)/i,
      # env var ascp exec
      /(?<begin> (?:#{ASCP_ENV_SECRETS.join('|')})=)[^ \n]+(?<end> |$)/,
      # rendered JSON or Ruby (quoted key or legacy symbol key: `"k":"v"`, `"k" => "v"`, `:k=>"v"`)
      /(?<begin>(?:(?<quote>["'])|:)[^"':=]*(?:#{ALL_SECRETS.join('|')})[^"':=]*\k<quote>? *(?:=>|:) *")(?:[^"\\]|\\.)+(?<end>")/i,
      # rendered Ruby 3.4+ symbol key: `k: "v"`
      /(?<begin>\b\w*(?:#{ALL_SECRETS.join('|')})\w*: *")(?:[^"\\]|\\.)+(?<end>")/i,
      # logged data
      /(?<begin>(?:#{NON_ENV_SECRETS.join('|')})[ =:]+)[^ "]#{SECRET_LENGTH}(?<end>$)/i,
      # cred in http dump
      /(?<begin>(?:#{HTTP_SECRETS.join('|')}): )[^\\]+(?<end>\\)/i
    ].freeze
    private_constant :HIDDEN_PASSWORD, :ASCP_ENV_SECRETS, :KEY_SECRETS, :HTTP_SECRETS, :ALL_SECRETS, :NON_ENV_SECRETS, :KEY_FALSE_POSITIVES, :SECRET_LENGTH, :REGEX_LOG_REPLACES
    attr_accessor :log_secrets

    # @return [Proc] new log formatter that hides secrets
    def log_formatter(original_formatter)
      original_formatter ||= Logger::Formatter.new
      # NOTE: that @log_secrets may be set AFTER this init is done, so it's done at runtime
      # Hiding is applied on the formatted line, so that non-String messages (e.g. Exception) are covered too
      return lambda do |severity, date_time, program_name, msg|
        line = original_formatter.call(severity, date_time, program_name, msg)
        line = hide_secrets_in_string(line, all: true) if line.is_a?(String) && !@log_secrets
        line
      end
    end

    # Replace secrets in a string with the hidden password placeholder
    # @param value [String] Input string possibly containing secrets
    # @param all   [Boolean] `false`: only private keys, `true`: all known secret patterns
    # @return [String] String with secrets replaced by placeholder
    def hide_secrets_in_string(value, all: false)
      (all ? REGEX_LOG_REPLACES : REGEX_LOG_REPLACES.first(1)).each do |reg_ex|
        value = value.gsub(reg_ex) { "#{Regexp.last_match(:begin)}#{HIDDEN_PASSWORD}#{Regexp.last_match(:end)}" }
      end
      return value
    end

    # @param keyword [String, Symbol] Key name to check
    # @param value   [String]         Associated value (must be a String to be a secret)
    # @return [Boolean] true if the key denotes a secret
    def secret?(keyword, value)
      keyword = keyword.to_s if keyword.is_a?(Symbol)
      # only Strings can be secrets, not booleans, or hash, arrays
      return false unless keyword.is_a?(String) && value.is_a?(String)
      return true if @additional_keys.include?(keyword)
      keyword = keyword.downcase
      # those are not secrets
      return false if KEY_FALSE_POSITIVES.any? { |f| f.match?(keyword) }
      # check if keyword (name) contains an element that designate it as a secret
      ALL_SECRETS.any? { |kw| keyword.include?(kw.downcase) }
    end

    # Hides recursively secrets in Hash or Array of Hash
    def deep_remove_secret(obj)
      case obj
      when Array
        obj.each { |i| deep_remove_secret(i) }
      when Hash
        obj.each do |k, v|
          if secret?(k, v)
            obj[k] = HIDDEN_PASSWORD
          elsif v.is_a?(Hash) || v.is_a?(Array)
            deep_remove_secret(v)
          end
        end
      end
      return obj
    end

    # Declare additional exact key names whose values are secrets
    # @param keys [Array<String, Symbol>] Key names
    def add_secret_keys(keys)
      @additional_keys.merge(keys.map(&:to_s))
    end

    private

    def initialize
      @log_secrets = false
      @additional_keys = Set.new
    end
  end
end
