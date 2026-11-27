# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'logger'
require 'set'
require 'singleton'
require 'json'
require 'uri'

module Aspera
  module Secret
    # remove secret from logs and output
    #
    # Secrets are identified:
    # - by key name, in structures (`secret?`, `hidden_copy`) and in strings with known patterns (`hide_secrets_in_string`)
    # - by value, when declared where they come from (`add_secret_values`, `add_secrets_in`): option values, tokens, ...
    # - in a structure encoded in base64 JSON in a URL query (e.g. context of a Faspex 5 public link): declared by `add_secrets_in`,
    #   else hidden in logs only (`hide_serialized_secrets`, e.g. in an API response)
    #
    # @!method self.instance
    #   Returns the singleton instance of Secret::Hider
    #   @return [Secret::Hider] the singleton instance
    class Hider
      include Singleton

      # display string for hidden secrets (see `Environment::UNICODE_TO_ASCII`)
      HIDDEN_PASSWORD = '🔑'
      # env vars for ascp with secrets
      ASCP_ENV_SECRETS = %w[ASPERA_SCP_PASS ASPERA_SCP_KEY ASPERA_SCP_FILEPASS ASPERA_PROXY_PASS ASPERA_SCP_TOKEN].freeze
      # keys in hash that contain secrets (`passcode`: e.g. of a Faspex 5 public link, in its context, or in header `Passcode`)
      KEY_SECRETS = %w[password secret passphrase passcode _key apikey crn token].freeze
      HTTP_SECRETS = %w[Authorization].freeze
      ALL_SECRETS = (ASCP_ENV_SECRETS + KEY_SECRETS + HTTP_SECRETS).freeze
      NON_ENV_SECRETS = (KEY_SECRETS + HTTP_SECRETS).freeze
      # not secrets: `*_file` is the path of a file (e.g. `ca_file`)
      KEY_FALSE_POSITIVES = [/^access_key$/, /^fallback_private_key$/, /public_key$/, /^token_type$/, /_file$/].freeze
      # Keys of a form or URL query whose values are credentials, though their names do not denote a secret (not in JSON, e.g. `code` of an error):
      # OAuth authorization code (RFC 6749 §4.1.2), e.g. in the URL of a redirect, PKCE code verifier (RFC 7636 §4.5), JWT assertion (RFC 7523 §2.1)
      FORM_CREDENTIALS = %w[code code_verifier assertion].freeze
      # boolean values as text: not secrets, even for a name that denotes a secret (e.g. `show_secrets`)
      BOOLEAN_TEXTS = %w[yes no true false].freeze
      # min length of hidden secrets, use `+` or `{n,}`
      SECRET_LENGTH = '{5,}'
      # min length of a declared secret value to be hidden inside a string: shorter ones are hidden only when they are the whole string,
      # else common words would be hidden (e.g. password `aspera` in URLs), or optionally as a word (`short_in_text`)
      VALUE_IN_STRING_LENGTH = 8
      # regex that define named captures :begin and :end, and :key for the name of a key (not hidden if it is not a secret, see `KEY_FALSE_POSITIVES`)
      REGEX_LOG_REPLACES = [
        # private key values (place first)
        /(?<begin>--+BEGIN [^-]+ KEY--+)[[:ascii:]]+?(?<end>--+?END [^-]+ KEY--+)\n*/,
        # CLI manager get/set options
        /(?<begin>[sg]et (?:#{KEY_SECRETS.join('|')})=).*(?<end>)/i,
        # env var ascp exec
        /(?<begin> (?:#{ASCP_ENV_SECRETS.join('|')})=)[^ \n]+(?<end> |$)/,
        # rendered JSON or Ruby (quoted key or legacy symbol key: `"k":"v"`, `"k" => "v"`, `:k=>"v"`)
        /(?<begin>(?:(?<quote>["'])|:)(?<key>[^"':=]*(?:#{ALL_SECRETS.join('|')})[^"':=]*)\k<quote>? *(?:=>|:) *")(?:[^"\\]|\\.)+(?<end>")/i,
        # rendered Ruby 3.4+ symbol key: `k: "v"`
        /(?<begin>\b(?<key>\w*(?:#{ALL_SECRETS.join('|')})\w*): *")(?:[^"\\]|\\.)+(?<end>")/i,
        # rendered Ruby Struct or object: `k="v"`, `@k="v"`
        /(?<begin>@?\b(?<key>\w*(?:#{ALL_SECRETS.join('|')})\w*)=")(?:[^"\\]|\\.)+(?<end>")/i,
        # query parameter of URL: `?token=v` or `&client_secret=v`
        /(?<begin>[?&](?<key>[^=&\s"]*(?:#{KEY_SECRETS.join('|')})[^=&\s"]*)=)[^&\s"#]+(?<end>)/i,
        # query parameter of URL, OAuth credential: `?code=v`
        /(?<begin>[?&](?:#{FORM_CREDENTIALS.join('|')})=)[^&\s"#]+(?<end>)/,
        # logged data (:key is the end of the name, e.g. `_key` of `access_key: v`)
        /(?<begin>(?<key>#{NON_ENV_SECRETS.join('|')})[ =:]+)[^ "\n]#{SECRET_LENGTH}(?<end>$)/i,
        # cred in http dump
        /(?<begin>(?:#{HTTP_SECRETS.join('|')}): )[^\\]+(?<end>\\)/i
      ].freeze
      # Key/value pairs of a structure serialized in a string (e.g. raw HTTP body), with named captures :begin, :key, :value and :end
      REGEX_SERIALIZED_PAIRS = {
        # JSON, string value: `"key":"value"`
        json: /(?<begin>"(?<key>(?:[^"\\]|\\.)*)"\s*:\s*")(?<value>(?:[^"\\]|\\.)*)(?<end>")/,
        # form or URL query: `key=value&key=value`, `?key=value`
        form: /(?<begin>(?:\A|[?&])(?<key>[^=&\s"#?]+)=)(?<value>[^&\s"#]*)(?<end>)/
      }.freeze
      # HTTP header with cookies, e.g. in the debug output of `Net::HTTP`: `Cookie: name=value; name=value`, `Set-Cookie: name=value; Path=/`
      REGEX_COOKIE_HEADER = /^(?<begin>(?<name>(?:Set-)?Cookie):[ \t]*)(?<value>[^\r\n]*)/i
      # `name=value` of a cookie in the header, with named capture :begin. `Set-Cookie`: the first one only, others are attributes (e.g. `Max-Age=60`)
      REGEX_COOKIE_PAIR = /(?<begin>(?:\A|;)[ \t]*[^=;\s]+=)[^;\r\n]+/
      # Value of a query parameter of a URL, long enough to be a structure encoded in base64 (see `encoded_secret?`), with named captures :begin and :value.
      # No `?` in the name: else polynomial on many `?`. No `\` in the value: end of a URL in JSON with `&` escaped (e.g. `\u0026` by Go)
      REGEX_QUERY_ENCODED = /(?<begin>[?&][^=&\s"#?]+=)(?<value>[^&\s"#\\]{16,})/
      # A character that is not in the name of a key in a log line (see `false_positive_key?`)
      REGEX_NOT_IN_KEY = /[\s,;{}\[\]()<>@#|"':=&?]/
      private_constant :HIDDEN_PASSWORD, :ASCP_ENV_SECRETS, :KEY_SECRETS, :HTTP_SECRETS, :ALL_SECRETS, :NON_ENV_SECRETS, :KEY_FALSE_POSITIVES, :BOOLEAN_TEXTS, :SECRET_LENGTH, :VALUE_IN_STRING_LENGTH, :REGEX_LOG_REPLACES, :REGEX_SERIALIZED_PAIRS,
        :FORM_CREDENTIALS, :REGEX_COOKIE_HEADER, :REGEX_COOKIE_PAIR, :REGEX_QUERY_ENCODED, :REGEX_NOT_IN_KEY
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
          value = hide_pattern(value, reg_ex, marker)
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
        return false if false_positive?(keyword)
        # check if keyword (name) contains an element that designate it as a secret
        ALL_SECRETS.any? { |kw| keyword.include?(kw.downcase) }
      end

      # Hides secrets in a structure: by key name, and declared values, also in key names (e.g. a secret given as name of a parameter).
      # Containers are copied, not modified: the structure may be shared (e.g. configuration, transfer spec).
      # @param obj           [Object]  Hash, Array, Struct, String, or other value (returned as is)
      # @param short_in_text [Boolean] `true`: a declared value shorter than 8 characters is also hidden inside a text, as a word
      #   (not next to a letter or digit), e.g. a short password in an error message of `mcp server`
      # @param serialized    [Boolean] `true`: also hide secrets by key name in structures serialized in strings (see `hide_serialized_secrets`)
      # @return [Object] Copy of obj with secrets replaced by placeholder
      def hidden_copy(obj, short_in_text: false, serialized: false)
        copy = ->(item) { hidden_copy(item, short_in_text: short_in_text, serialized: serialized) }
        case obj
        when Hash then obj.to_h { |k, v| [k.is_a?(String) ? copy.call(k) : k, secret?(k, v) ? hidden_marker : copy.call(v)] }
        when Array then obj.map(&copy)
        when Struct then obj.dup.tap { |s| s.each_pair { |k, v| s[k] = secret?(k, v) ? hidden_marker : copy.call(v) } }
        when String
          text = hide_values_in_string(obj, hidden_marker, short_in_text: short_in_text)
          serialized ? hide_serialized_secrets(text) : text
        else obj
        end
      end

      # Hides secrets by key name (see `secret?`) in a structure serialized in a string, e.g. the raw body of an HTTP request or response:
      # JSON (`"key":"value"`), form or URL query (`key=value&...`, also OAuth credentials such as `code`, see `FORM_CREDENTIALS`),
      # the values of cookies in HTTP headers (`Cookie`, `Set-Cookie`), and the value of a URL query that is a structure encoded in base64 JSON
      # with a secret (e.g. the context of a Faspex 5 public link in an API response, not declared: shown in results, see `add_encoded_secrets`).
      # Keys, names of cookies and other values are kept.
      # Needed before such a string is dumped in logs: the dump escapes its quotes, so the patterns of the log formatter would not match.
      # @param value [String] Text
      # @return [String] Text with the values of secret keys replaced by placeholder, or `value` itself if it has none
      def hide_serialized_secrets(value)
        marker = hidden_marker
        text = value
        unless text.valid_encoding? && Encoding.compatible?(text, marker)
          # e.g. binary data with non-ASCII bytes (raw HTTP body): UTF-8 text if valid, else bytes
          text = value.dup.force_encoding(Encoding::UTF_8)
          text, marker = value.b, marker.b unless text.valid_encoding?
        end
        hidden = false
        REGEX_SERIALIZED_PAIRS.each do |format, reg_ex|
          text = text.gsub(reg_ex) do
            match = Regexp.last_match
            key = match[:key]
            key = (URI.decode_www_form_component(key).scrub rescue key) if format.eql?(:form)
            next match[0] unless secret?(key, match[:value]) || (format.eql?(:form) && FORM_CREDENTIALS.include?(key))
            hidden = true
            "#{match[:begin]}#{marker}#{match[:end]}"
          end
        end
        text = text.gsub(REGEX_COOKIE_HEADER) do
          match = Regexp.last_match
          pairs = match[:value].public_send(match[:name].casecmp?('Cookie') ? :gsub : :sub, REGEX_COOKIE_PAIR) do
            hidden = true
            "#{Regexp.last_match(:begin)}#{marker}"
          end
          "#{match[:begin]}#{pairs}"
        end
        if text.include?('=')
          text = text.gsub(REGEX_QUERY_ENCODED) do
            match = Regexp.last_match
            next match[0] unless encoded_secret?(match[:value])
            hidden = true
            "#{match[:begin]}#{marker}"
          end
        end
        hidden ? text : value
      end

      # @param obj [Object] Hash, Array, Struct, String, or other value
      # @return [Boolean] `true` if obj contains a secret: by key name, or declared value
      def contains_secret?(obj)
        !hidden_copy(obj).eql?(obj)
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
          long, short = values.partition { |v| v.length >= VALUE_IN_STRING_LENGTH }
          # Longest first, so that a secret is not partly hidden by another one that it contains
          @values_regex = long.empty? ? nil : Regexp.union(long.sort_by { |v| -v.length })
          @short_values_regex = short.empty? ? nil : /(?<![[:alnum:]])#{Regexp.union(short.sort_by { |v| -v.length })}(?![[:alnum:]])/
          # Replaced, not modified, for readers in other threads
          @values = values.freeze
        end
      end

      # Declare the secret values found by key name in a structure, also in a structure encoded in the query of a URL (see `add_encoded_secrets`)
      # @param obj [Object] Hash, Array or String, e.g. a transfer spec, the value of an option
      def add_secrets_in(obj)
        case obj
        when Array then obj.each { |i| add_secrets_in(i) }
        when Hash then obj.each { |k, v| secret?(k, v) ? add_secret_values(v) : add_secrets_in(v) }
        when String then add_encoded_secrets(obj)
        end
      end

      # Declare the secret values of a named value (e.g. an option): the whole value if the name denotes a secret,
      # else the secret values found by key name in it.
      # A boolean value given as text is not a secret, e.g. `no` for option `cache_tokens`, else it would be hidden everywhere.
      # @param name  [String, Symbol] Name, e.g. option name
      # @param value [Object]         Value
      def add_named_secrets(name, value)
        return add_secrets_in(value) unless secret?(name, '')
        add_secret_values(value) unless BOOLEAN_TEXTS.include?(value)
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
        # Matches shorter declared values as a word
        @short_values_regex = nil
        @mutex = Mutex.new
      end

      # Declare the secrets of a structure encoded in base64 JSON in the query of a URL, e.g. the passcode in the `context` of a Faspex 5 public link:
      # the secrets found by key name in the structure, and the encoded value (as in the URL, and URL-decoded), as it reveals them once decoded.
      # The rest of the URL is not hidden.
      # @param text [String] Text, e.g. URL
      def add_encoded_secrets(text)
        return unless text.include?('=') && text.valid_encoding?
        text.scan(REGEX_QUERY_ENCODED) do
          raw = Regexp.last_match(:value)
          encoded, structure = decode_query_structure(raw)
          next unless encoded_secret?(raw, structure)
          add_secrets_in(structure)
          add_secret_values(raw, encoded)
        end
      end

      # @param raw [String] Value of a query parameter of a URL, as in the URL
      # @return [Array(String, Object), nil] The value URL-decoded, and the structure it encodes in base64 JSON (standard or URL-safe), or `nil`
      def decode_query_structure(raw)
        # `+` kept: it is one of base64, also when not URL-encoded
        encoded = URI.decode_uri_component(raw)
        [encoded, JSON.parse(encoded.tr('-_', '+/').unpack1('m'))]
      rescue StandardError
        # Not a structure encoded in base64 JSON (e.g. `?context=packages`)
        nil
      end

      # @param raw       [String] Value of a query parameter of a URL, as in the URL
      # @param structure [Object] Structure it encodes, if already decoded (see `decode_query_structure`)
      # @return [Boolean] `true` if the value is a structure (Hash or Array) encoded in base64 JSON that contains a secret, by key name or declared value
      def encoded_secret?(raw, structure = decode_query_structure(raw)&.last)
        (structure.is_a?(Hash) || structure.is_a?(Array)) && contains_secret?(structure)
      end

      # @param keyword [String] Key name, in lower case
      # @return [Boolean] `true` if the key is not a secret, though its name contains one that denotes a secret (e.g. `token_type`)
      def false_positive?(keyword)
        KEY_FALSE_POSITIVES.any? { |f| f.match?(keyword) }
      end

      # @param text   [String] Text
      # @param reg_ex [Regexp] One of `REGEX_LOG_REPLACES`
      # @param marker [String] Placeholder
      # @return [String] Text with the values matched by reg_ex replaced by placeholder, but the values of keys that are not secrets (as `secret?`)
      def hide_pattern(text, reg_ex, marker)
        text.gsub(reg_ex) do
          match = Regexp.last_match
          next "#{match[:begin]}#{marker}#{match[:end]}" unless match.names.include?('key') && false_positive_key?(match)
          # Not a secret: its value may contain others, e.g. `&token=` after `access_key=` for "logged data"
          value = match[0][match[:begin].length...(match[0].length - match[:end].length)]
          "#{match[:begin]}#{hide_pattern(value, reg_ex, marker)}#{match[:end]}"
        end
      end

      # @param match [MatchData] Match of a regex of `REGEX_LOG_REPLACES` with a named capture :key
      # @return [Boolean] `true` if the key is not a secret (see `secret?`). Its name ends with the capture, and starts after the last character that
      #   cannot be in a name, e.g. `access_key` for `_key` in `data: access_key: v`, `token_type` for ` {token_type` in `text: {token_type: "v"}`
      def false_positive_key?(match)
        head = match.string[0, match.end(:key)]
        start = head.rindex(REGEX_NOT_IN_KEY)
        keyword = start.nil? ? head : head[(start + 1)..]
        !@additional_keys.include?(keyword) && false_positive?(keyword.downcase)
      end

      # @param value         [String]  Input string
      # @param marker        [String]  Placeholder
      # @param short_in_text [Boolean] `true`: also hide short values as a word
      # @return [String] value with declared secret values replaced by placeholder
      def hide_values_in_string(value, marker, short_in_text: false)
        return marker if @values.include?(value)
        long_regex = @values_regex
        short_regex = @short_values_regex if short_in_text
        # Long values first, as they may contain short ones
        value = value.gsub(long_regex, marker) unless long_regex.nil?
        value = value.gsub(short_regex, marker) unless short_regex.nil?
        value
      end

      # @return [String] Placeholder for hidden secrets, in ASCII when Unicode is not supported
      def hidden_marker
        # Required here, as `aspera/environment` requires `aspera/log`, which requires this file
        require_relative '../environment'
        Environment.char(HIDDEN_PASSWORD)
      end
    end
  end
end
