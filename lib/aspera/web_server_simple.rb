# frozen_string_literal: true

require 'delegate'
require 'ipaddr'
require 'webrick'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/hash_ext'

module Aspera
  # Simple WEBrick server with HTTPS support
  class WebServerSimple < WEBrick::HTTPServer
    PARAMS = %i[cert key chain].freeze
    DEFAULT_URL = 'http://localhost:8080'
    GENERIC_ISSUER = '/C=FR/O=Test/OU=Test/CN=Test'
    ONE_YEAR_SECONDS = 365 * 24 * 60 * 60
    PKCS12_EXT = %w[p12 pfx].map { |i| ".#{i}" }.freeze
    CLOCK_SKEW_OFFSET_SEC = 5

    private_constant :PARAMS, :DEFAULT_URL, :GENERIC_ISSUER, :ONE_YEAR_SECONDS, :PKCS12_EXT, :CLOCK_SKEW_OFFSET_SEC

    # Logger of WEBrick: its information messages (version, start, shutdown) at debug level, the server logs its URL
    class WebrickLogger < SimpleDelegator
      def info(message = nil, &block) = debug(message, &block)
      def info? = debug?
    end
    private_constant :WebrickLogger

    # @return [URI] URL of the server, with the port it listens on: any free port if `0` was given
    attr_reader :uri

    class << self
      # @param host [String] Host name or IP address the server listens on
      # @return [Boolean] `true` if the server is reachable from the local host only
      def loopback?(host)
        return true if host.eql?('localhost')
        IPAddr.new(host).loopback?
      rescue IPAddr::Error
        false
      end

      # @param parameters [Hash] Parameters of a command that starts a server (symbol keys): `url`, `cert`, `key`, `chain`, others are for the servlet
      # @return [URI] URL of the server: `url`, or `DEFAULT_URL`
      def url(parameters) = URI.parse(parameters.fetch(:url, DEFAULT_URL))

      # @param parameters [Hash] Parameters of a command that starts a server, see `url`
      # @return [Hash] Parameters of the servlet: other than `url`, `cert`, `key`, `chain`
      def servlet_parameters(parameters) = parameters.except(:url, *PARAMS)

      # Start a server with one servlet on the path of `url`, until signal INT or TERM.
      # A server without protection reachable from the network is refused, see `assert_protected`.
      # @param parameters [Hash]      Parameters of the command, see `url`
      # @param servlet    [Class]     Servlet
      # @param protected  [Boolean]   `true` if requests are authenticated or restricted
      # @param what       [String]    Parameters that protect the server, for the error message
      # @param type       [Exception] Exception to raise
      # @yieldreturn [Array] Arguments of the servlet, evaluated once parameters are checked
      def serve(parameters, servlet, protected:, what:, type: ParameterError)
        uri = url(parameters)
        assert_protected(uri.hostname, protected: protected, what: what, type: type)
        server = new(uri, **parameters.slice(*PARAMS))
        server.mount(uri.path, servlet, *yield)
        server.start
      end

      # Refuse a server without protection reachable from the network: anyone could call it
      # @param host      [String]    Host name or IP address the server listens on
      # @param protected [Boolean]   `true` if requests are authenticated or restricted
      # @param what      [String]    Parameters that protect the server, for the error message
      # @param type      [Exception] Exception to raise
      # @raise [Exception] if not protected and `host` is not a loopback address
      def assert_protected(host, protected:, what:, type: ParameterError)
        Aspera.assert(protected || loopback?(host), type: type) do
          "#{what} is required when the server listens on an address that is not loopback (localhost, 127.0.0.0/8, ::1): #{host}"
        end
      end

      # Generate or fill and self sign certificate
      def self_signed_cert(private_key, digest: 'SHA256')
        cert = OpenSSL::X509::Certificate.new
        cert.subject = cert.issuer = OpenSSL::X509::Name.parse(GENERIC_ISSUER)
        cert.not_before = Time.now - CLOCK_SKEW_OFFSET_SEC
        cert.not_after  = cert.not_before + ONE_YEAR_SECONDS
        cert.public_key = private_key.public_key
        cert.serial = 0x0
        cert.version = 2
        ef = OpenSSL::X509::ExtensionFactory.new
        ef.issuer_certificate = cert
        ef.subject_certificate = cert
        cert.extensions = [
          ef.create_extension('basicConstraints', 'CA:TRUE', true),
          ef.create_extension('subjectKeyIdentifier', 'hash')
          # ef.create_extension('keyUsage', 'cRLSign,keyCertSign', true),
        ]
        cert.add_extension(ef.create_extension('authorityKeyIdentifier', 'keyid:always,issuer:always'))
        cert.sign(private_key, OpenSSL::Digest.new(digest))
        cert
      end

      # @return [Array<OpenSSL::X509::Certificate>] list of Certificates from chain file
      def read_chain_file(chain)
        File.read(chain).scan(/-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m).map { |i| OpenSSL::X509::Certificate.new(i) }
      end
    end

    # @param uri   [URI]    Local address where server will listen (use scheme, host and port only), port `0` for any free port
    # @param cert  [String] Path to certificate file, either with extension .p12 or .pfx, else assumed PEM
    # @param key   [String] Path to key file (PEM) or passphrase (pkcs12)
    # @param chain [String] Path to certificate chain file (PEM only)
    def initialize(uri, cert: nil, key: nil, chain: nil)
      Aspera.assert_type(uri, URI)
      @uri = uri.dup
      # see https://www.rubydoc.info/stdlib/webrick/WEBrick/Config
      webrick_options = {
        # without brackets of IPv6 address
        BindAddress: @uri.hostname,
        Port:        @uri.port,
        Logger:      WebrickLogger.new(Log.log),
        AccessLog:   [[self, WEBrick::AccessLog::COMMON_LOG_FORMAT]] # replace default access log to call local method "<<" below
      }
      case @uri.scheme
      when 'http'
        Log.log.debug('HTTP mode')
      when 'https'
        # Required lazily: webrick/ssl.rb reads OpenSSL::OPENSSL_VERSION at load time,
        # a constant CosmoRuby's OpenSSL shim does not define, so requiring it
        # unconditionally at file load would break any command in a Cosmo build
        # even when no HTTPS server is ever started.
        require 'webrick/https'
        webrick_options[:SSLEnable] = true
        if cert.nil? && key.nil?
          webrick_options[:SSLCertName] = [['CN', WEBrick::Utils.getservername]]
        elsif cert && PKCS12_EXT.include?(File.extname(cert).downcase)
          # PKCS12
          Log.log.debug('Using PKCS12 certificate')
          Aspera.assert(!key.nil?, type: Error) { 'PKCS12 requires a key (password)' }
          pkcs12 = OpenSSL::PKCS12.new(File.read(cert), key)
          webrick_options[:SSLCertificate] = pkcs12.certificate
          webrick_options[:SSLPrivateKey] = pkcs12.key
          webrick_options[:SSLExtraChainCert] = pkcs12.ca_certs
        else
          Log.log.debug('Using PEM certificate')
          webrick_options[:SSLPrivateKey] = if key.nil?
            OpenSSL::PKey::RSA.new(4096)
          else
            OpenSSL::PKey::RSA.new(File.read(key))
          end
          webrick_options[:SSLCertificate] = if cert.nil?
            self.class.self_signed_cert(webrick_options[:SSLPrivateKey])
          else
            OpenSSL::X509::Certificate.new(File.read(cert))
          end
          webrick_options[:SSLExtraChainCert] = self.class.read_chain_file(chain) unless chain.nil?
          Aspera.assert(webrick_options[:SSLCertificate].public_key.to_der == webrick_options[:SSLPrivateKey].public_key.to_der, type: Error) { 'key and cert do not match' }
        end
      end
      # call constructor of parent class, but capture STDERR
      # self signed certificate generates characters on STDERR
      # see create_self_signed_cert in webrick/ssl.rb
      Log.capture_stderr { super(webrick_options) }
      @uri.port = config[:Port]
    end

    # Serve requests until #shutdown.
    # In the main thread, signals INT and TERM call #shutdown.
    # In another thread, signals are left to the application, which calls #shutdown, e.g. INT interrupts the main thread.
    def start
      Log.log.info { "Listening on #{@uri}" }
      if Thread.current.equal?(Thread.main)
        # kill (-TERM) for graceful shutdown
        handler = proc { shutdown }
        %i{INT TERM}.each { |sig| trap(sig, &handler) }
      end
      super
    end

    # log web server access ( option AccessLog )
    def <<(access_log)
      Log.log.debug { "webrick log #{access_log.chomp}" }
    end
  end
end
