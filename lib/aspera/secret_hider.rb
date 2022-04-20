# frozen_string_literal: true

require 'logger'

module Aspera
  # remove secret from logs and output
  class SecretHider
    # display string for hidden secrets
    HIDDEN_PASSWORD = '🔑'
    # passwords and secrets are hidden with this string
    SECRET_KEYWORDS = %w[password secret private_key passphrase].freeze
    private_constant :HIDDEN_PASSWORD,:SECRET_KEYWORDS
    @log_secrets = false
    class << self
      attr_accessor :log_secrets
      def log_formatter(original_formatter)
        original_formatter ||= Logger::Formatter.new
        # note that @log_secrets may be set AFTER this init is done, so it's done at runtime
        return lambda do |severity, datetime, progname, msg|
          if msg.is_a?(String) && !@log_secrets
            msg = msg
                .gsub(/(["':][^"]*(password|secret|private_key)[^"]*["']?[=>: ]+")([^"]+)(")/){"#{Regexp.last_match(1)}#{HIDDEN_PASSWORD}#{Regexp.last_match(4)}"}
                .gsub(/("[^"]*(secret)[^"]*"=>{)([^}]+)(})/){"#{Regexp.last_match(1)}#{HIDDEN_PASSWORD}#{Regexp.last_match(4)}"}
                .gsub(/((secrets)={)([^}]+)(})/){"#{Regexp.last_match(1)}#{HIDDEN_PASSWORD}#{Regexp.last_match(4)}"}
                .gsub(/--+BEGIN[A-Z ]+KEY--+.+--+END[A-Z ]+KEY--+/m){HIDDEN_PASSWORD}
          end
          original_formatter.call(severity, datetime, progname, msg)
        end
      end

      def secret?(keyword,value)
        keyword=keyword.to_s if keyword.is_a?(Symbol)
        # only Strings can be secrets, not booleans, or hash, arrays
        keyword.is_a?(String) && SECRET_KEYWORDS.any?{|kw|keyword.include?(kw)} && value.is_a?(String)
      end

      def deep_remove_secret(obj,is_name_value: false)
        case obj
        when Array
          if is_name_value
            obj.each do |i|
              i['value']=HIDDEN_PASSWORD if secret?(i['parameter'],i['value'])
            end
          else
            obj.each{|i|deep_remove_secret(i)}
          end
        when Hash
          obj.each do |k,v|
            if secret?(k,v)
              obj[k] = HIDDEN_PASSWORD
            elsif obj[k].is_a?(Hash)
              deep_remove_secret(obj[k])
            end
          end
        end
      end
    end
  end
end
