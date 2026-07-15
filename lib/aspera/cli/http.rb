# frozen_string_literal: true

require 'aspera/cli/special_values'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/line_logger'
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

      attr_accessor :insecure, :warn_insecure, :http_options
      attr_reader   :ignore_cert_host_port

      # Declare all HTTP/S CLI options, with handlers pointing to self.
      # Called once from Config#initialize after this object is instantiated.
      # @param options [Aspera::Cli::Manager]
      def declare_options(options)
        options.declare(:insecure, 'HTTP/S: Do not validate any certificate', allowed: Allowed::TYPES_BOOLEAN, handler: {o: self, m: :insecure}, default: false)
        options.declare(:ignore_certificate, 'HTTP/S: Do not validate certificate for these URLs', allowed: [Array, NilClass], handler: {o: self, m: :ignore_cert_host_port})
        options.declare(:warn_insecure, 'HTTP/S: Issue a warning if certificate is ignored', allowed: Allowed::TYPES_BOOLEAN, handler: {o: self, m: :warn_insecure}, default: true)
        options.declare(:cert_stores, 'HTTP/S: List of folder with trusted certificates', allowed: Allowed::TYPES_STRING_ARRAY, handler: {o: self, m: :trusted_cert_locations})
        options.declare(:http_options, 'HTTP/S: Options for HTTP/S socket', allowed: Hash, handler: {o: self, m: :http_options}, default: {})
        options.declare(:http_proxy, 'HTTP/S: URL for proxy with optional credentials', handler: {o: self, m: :http_proxy})
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
          raise "Expecting https scheme: #{url}" unless uri.scheme.eql?('https')
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
      # @param path_list [Array<String>]
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

      # @param http_session [Net::HTTP]
      def update_session(http_session)
        http_session.set_debug_output(LineLogger.new(:trace2)) if Log.instance.logger.trace2?
        if http_session.use_ssl? && ignore_cert?(http_session.address, http_session.port)
          http_session.verify_mode = SELF_SIGNED_CERT
        end
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
      end
    end
  end
end
