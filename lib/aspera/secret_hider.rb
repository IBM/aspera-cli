# frozen_string_literal: true

# cspell:ignore FILEPASS
require 'logger'
require 'set'
require 'singleton'
require 'json'
require 'uri'

module Aspera
  # remove secret from logs and output
  #
  # Secrets are identified:
  # - by key name, in structures (`secret?`, `hidden_copy`) and in strings with known patterns (`hide_secrets_in_string`)
  # - by value, when declared where they come from (`add_secret_values`, `add_secrets_in`): option values, tokens, ...
  #
  # @!method self.instance
  #   Returns the singleton instance of SecretHider
  #   @return [SecretHider] the singleton instance
  class SecretHider
    include Singleton

    # display string for hidden secrets (see `Environment::UNICODE_TO_ASCII`)
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
    # min length of a declared secret value to be hidden inside a string: shorter ones are hidden only when they are the whole string,
    # else common words would be hidden (e.g. password `aspera` in URLs)
    VALUE_IN_STRING_LENGTH = 8
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
      # rendered Ruby Struct or object: `k="v"`, `@k="v"`
      /(?<begin>@?\b\w*(?:#{ALL_SECRETS.join('|')})\w*=")(?:[^"\\]|\\.)+(?<end>")/i,
      # query parameter of URL: `?token=v` or `&client_secret=v`
      /(?<begin>[?&][^=&\s"]*(?:#{KEY_SECRETS.join('|')})[^=&\s"]*=)[^&\s"#]+(?<end>)/i,
      # logged data
      /(?<begin>(?:#{NON_ENV_SECRETS.join('|')})[ =:]+)[^ "\n]#{SECRET_LENGTH}(?<end>$)/i,
      # cred in http dump
      /(?<begin>(?:#{HTTP_SECRETS.join('|')}): )[^\\]+(?<end>\\)/i
    ].freeze
    private_constant :HIDDEN_PASSWORD, :ASCP_ENV_SECRETS, :KEY_SECRETS, :HTTP_SECRETS, :ALL_SECRETS, :NON_ENV_SECRETS, :KEY_FALSE_POSITIVES, :SECRET_LENGTH, :VALUE_IN_STRING_LENGTH, :REGEX_LOG_REPLACES
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
    # @param all   [Boolean] `false`: only declared values and private keys, `true`: also all known secret patterns
    # @return [String] String with secrets replaced by placeholder
    def hide_secrets_in_string(value, all: false)
      marker = hidden_marker
      value = hide_values_in_string(value, marker)
      (all ? REGEX_LOG_REPLACES : REGEX_LOG_REPLACES.first(1)).each do |reg_ex|
        value = value.gsub(reg_ex) { "#{Regexp.last_match(:begin)}#{marker}#{Regexp.last_match(:end)}" }
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

    # Hides secrets in a structure: by key name, and declared values.
    # Containers are copied, not modified: the structure may be shared (e.g. configuration, transfer spec).
    # @param obj [Object] Hash, Array, Struct, String, or other value (returned as is)
    # @return [Object] Copy of obj with secrets replaced by placeholder
    def hidden_copy(obj)
      case obj
      when Hash then obj.to_h { |k, v| [k, secret?(k, v) ? hidden_marker : hidden_copy(v)] }
      when Array then obj.map { |i| hidden_copy(i) }
      when Struct then obj.dup.tap { |s| s.each_pair { |k, v| s[k] = secret?(k, v) ? hidden_marker : hidden_copy(v) } }
      when String then hide_values_in_string(obj, hidden_marker)
      else obj
      end
    end

    # Declare secret values: hidden wherever they appear (logs, results), also when escaped in JSON, Ruby or URL
    # @param values [Array<Object>] Secret values: only non-empty Strings are retained
    def add_secret_values(*values)
      forms = values.select { |v| v.is_a?(String) && !v.empty? }.flat_map do |v|
        [v, (JSON.generate(v)[1..-2] rescue nil), v.inspect[1..-2], URI.encode_www_form_component(v)]
      end.compact
      return if forms.empty?
      @mutex.synchronize do
        values = @values | forms
        next if values.size.eql?(@values.size)
        long = values.select { |v| v.length >= VALUE_IN_STRING_LENGTH }
        # Longest first, so that a secret is not partly hidden by another one that it contains
        @values_regex = long.empty? ? nil : Regexp.union(long.sort_by { |v| -v.length })
        # Replaced, not modified, for readers in other threads
        @values = values.freeze
      end
    end

    # Declare the secret values found by key name in a structure
    # @param obj [Object] Hash or Array, e.g. a transfer spec
    def add_secrets_in(obj)
      case obj
      when Array then obj.each { |i| add_secrets_in(i) }
      when Hash then obj.each { |k, v| secret?(k, v) ? add_secret_values(v) : add_secrets_in(v) }
      end
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
      # Declared secret values, and their escaped forms
      @values = Set.new.freeze
      # Matches declared values long enough to be hidden inside a string
      @values_regex = nil
      @mutex = Mutex.new
    end

    # @param value  [String] Input string
    # @param marker [String] Placeholder
    # @return [String] value with declared secret values replaced by placeholder
    def hide_values_in_string(value, marker)
      return marker if @values.include?(value)
      regex = @values_regex
      regex.nil? ? value : value.gsub(regex, marker)
    end

    # @return [String] Placeholder for hidden secrets, in ASCII when Unicode is not supported
    def hidden_marker
      # Required here, as `aspera/environment` requires `aspera/log`, which requires this file
      require 'aspera/environment'
      Environment.char(HIDDEN_PASSWORD)
    end
  end
end
