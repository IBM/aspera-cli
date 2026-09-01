# frozen_string_literal: true

require 'aspera/cli/special_values'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/line_logger'
require 'aspera/schema/registry'
require 'aspera/rest'
require 'aspera/oauth'
require 'aspera/ssl'
require 'openssl'

module Aspera
  module Cli
    # Encapsulates all HTTP/S and TLS runtime configuration options.
    # Extracted from Plugins::Config so it can be referenced independently
    # via Context#http_config without coupling to the plugin machinery.
    class Http
      # Certificate file extensions recognized when scanning a folder
      CERT_EXT = %w[crt cer pem der].freeze
      # OpenSSL constant that disables peer verification (VERIFY_NONE)
      SELF_SIGNED_CERT = OpenSSL::SSL.const_get(:enon_yfirev.to_s.upcase.reverse) # cspell: disable-line

      private_constant :CERT_EXT, :SELF_SIGNED_CERT

      def initialize
        @insecure              = false
        @warn_insecure         = true
        @ignore_cert_host_port = []
        @http_options          = {}
        @ssl_warned_urls       = []
        @certificate_store     = nil
        @certificate_paths     = nil
      end

      attr_accessor :insecure, :warn_insecure
      attr_reader   :ignore_cert_host_port, :http_options

      class << self
        # Declare all HTTP/S CLI options (metadata only - no handler binding yet).
        # Called once from Config#initialize before this instance is available as a target.
        # Handlers are bound in a second pass via bind_options once the instance exists.
        # @param options [Aspera::Cli::Options] CLI options manager to declare options into
        # @return [nil]
        def declare_options(options)
          options.declare(:insecure,           description: 'HTTP/S: Do not validate any certificate',                   allowed: Allowed::TYPES_BOOLEAN, default: false)
          options.declare(:ignore_certificate, description: 'HTTP/S: Do not validate certificate for these URLs',        allowed: [Array, NilClass])
          options.declare(:warn_insecure,      description: 'HTTP/S: Issue a warning if certificate is ignored',         allowed: Allowed::TYPES_BOOLEAN, default: true)
          options.declare(:cert_stores,        description: 'HTTP/S: List of folder with trusted certificates',          allowed: Allowed::TYPES_STRING_ARRAY)
          options.declare(:http_options,       schema: Schema::Registry::HTTP_OPTIONS)
          options.declare(:http_proxy,         description: 'HTTP/S: URL for proxy with optional credentials')
          nil
        end
      end

      # Bind all HTTP options to this instance using set_handler.
      # Called from Config#initialize immediately after Http.new.
      # @param options [Aspera::Cli::Options]
      # @return [nil]
      def bind_options(options)
        options.set_handler(:insecure,           object: self, method: :insecure)
        options.set_handler(:ignore_certificate, object: self, method: :ignore_cert_host_port)
        options.set_handler(:warn_insecure,      object: self, method: :warn_insecure)
        options.set_handler(:cert_stores,        object: self, method: :trusted_cert_locations)
        options.set_handler(:http_options,       object: self, method: :http_options)
        options.set_handler(:http_proxy,         object: self, method: :http_proxy)
      end

      # Setter for http_options: dispatch each key to its target singleton immediately.
      # Keys matching RestParameters setters go to RestParameters, 'ssl_options' goes to SSL,
      # keys matching OAuth::Factory.instance.parameters go to OAuth, and the rest are kept
      # in @http_options for Net::HTTP session configuration in update_session.
      # This runs on every assignment (JSON hash, dotted notation, preset merge) so timing
      # of option parsing never matters.
      # @param new_options [Hash] merged http_options hash
      # @return [nil]
      def http_options=(new_options)
        Aspera.assert_type(new_options, Hash)
        kept = {}
        new_options.each do |k, v|
          method = "#{k}=".to_sym
          if RestParameters.instance.respond_to?(method)
            RestParameters.instance.send(method, v)
          elsif k.to_s.eql?('ssl_options')
            Aspera::SSL.option_list = v
          elsif OAuth::Factory.instance.parameters.key?(k.to_sym)
            OAuth::Factory.instance.parameters[k.to_sym] = v
          else
            kept[k] = v
          end
        end
        @http_options = kept
        nil
      end

      # ------------------------------------------------------------------
      # Proxy
      # ------------------------------------------------------------------

      def http_proxy
        ENV['http_proxy']
      end

      def http_proxy=(value)
        URI.parse(value)
        ENV['http_proxy'] = value
      end

      # ------------------------------------------------------------------
      # Per-URL certificate ignore list
      # ------------------------------------------------------------------

      def ignore_cert_host_port=(url_list)
        url_list.each do |url|
          uri = URI.parse(url)
          Aspera.assert(uri.scheme.eql?('https')){"Expecting https scheme: #{url}"}
          @ignore_cert_host_port.push([uri.host, uri.port].freeze)
        end
      end

      # Should the certificate be ignored for this host/port?
      # Also logs a warning the first time (if warn_insecure is set).
      def ignore_cert?(address, port)
        endpoint    = [address, port].freeze
        ignore_cert = @insecure || @ignore_cert_host_port.any?(endpoint)
        if ignore_cert && @warn_insecure
          base_url = "https://#{address}:#{port}"
          unless @ssl_warned_urls.include?(base_url)
            Log.log.warn{"Ignoring certificate for: #{base_url}. Do not deactivate certificate verification in production."}
            @ssl_warned_urls.push(base_url)
          end
        end
        Log.log.debug{"ignore cert? #{endpoint} -> #{ignore_cert}"}
        ignore_cert
      end

      # ------------------------------------------------------------------
      # Trusted certificate store / paths
      # ------------------------------------------------------------------

      # Add files, folders or the default OS locations to the cert store.
      # @param path_list [Array<String>] list of file/folder paths to add to the certificate store
      # @return [nil]
      def trusted_cert_locations=(path_list)
        Aspera.assert_type(path_list, Array){'cert locations'}
        if @certificate_store.nil?
          Log.log.debug('Creating SSL Cert store')
          @certificate_store = OpenSSL::X509::Store.new
          @certificate_paths = []
        end
        path_list.each do |path|
          Aspera.assert_type(path, String){'Expecting a String for certificate location'}
          paths_to_add = [path]
          Log.log.debug{"Adding cert location: #{path}"}
          if path.eql?(SpecialValues::DEF)
            @certificate_store.set_default_paths
            paths_to_add = [OpenSSL::X509::DEFAULT_CERT_DIR]
            paths_to_add.push(OpenSSL::X509::DEFAULT_CERT_FILE) unless defined?(JRUBY_VERSION)
            paths_to_add.select!{ |f| File.exist?(f)}
          elsif File.file?(path)
            @certificate_store.add_file(path)
          elsif File.directory?(path)
            @certificate_store.add_path(path)
          else
            raise "No such file or folder: #{path}"
          end
          paths_to_add.each do |p|
            pp = [File.realpath(p)]
            if File.directory?(p)
              pp = Dir.entries(p)
                .map{ |e| File.realpath(File.join(p, e))}
                .select{ |entry| File.file?(entry)}
                .select{ |entry| CERT_EXT.any?{ |ext| entry.end_with?(ext)}}
            end
            @certificate_paths.concat(pp)
          end
        end
        @certificate_paths.uniq!
        nil
      end

      # Return cert file paths (computes OS defaults lazily if never set).
      def trusted_cert_locations
        if @certificate_paths.nil?
          self.trusted_cert_locations = [SpecialValues::DEF]
          locations = @certificate_paths
          # Restore to "lazy" state so next call recomputes if store was reset
          @certificate_paths = @certificate_store = nil
          return locations
        end
        @certificate_paths
      end

      # ------------------------------------------------------------------
      # HTTP session callback
      # Called every time a new Net::HTTP session is opened.
      # ------------------------------------------------------------------

      # @param http_session [Net::HTTP] HTTP session to configure
      # @return [nil]
      def update_session(http_session)
        http_session.set_debug_output(LineLogger.new(:trace2)) if Log.instance.logger.trace2?
        http_session.verify_mode = SELF_SIGNED_CERT if http_session.use_ssl? && ignore_cert?(http_session.address, http_session.port)
        http_session.cert_store = @certificate_store if @certificate_store
        Log.log.debug{"Using cert store #{http_session.cert_store} (#{@certificate_store})"} unless http_session.cert_store.nil?
        @http_options.each do |k, v|
          method = "#{k}=".to_sym
          if http_session.respond_to?(method)
            http_session.send(method, v)
          else
            Log.log.error{"Unknown HTTP session attribute: #{k}"}
          end
        end
        nil
      end
    end
  end
end
