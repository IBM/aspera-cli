# frozen_string_literal: true

require 'webrick'
require 'webrick/https'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/hash_ext'
require 'openssl'

module Aspera
  # Simple WEBrick server with HTTPS support
  class WebServerSimple < WEBrick::HTTPServer
    PARAMS = %i[cert key chain].freeze
    DEFAULT_URL = 'http://localhost:8080'
    GENERIC_ISSUER = '/C=FR/O=Test/OU=Test/CN=Test'
    ONE_YEAR_SECONDS = 365 * 24 * 60 * 60
    PKCS12_EXT = %w[p12 pfx].map{ |i| ".#{i}"}.freeze
    CLOCK_SKEW_OFFSET_SEC = 5

    private_constant :GENERIC_ISSUER, :ONE_YEAR_SECONDS, :PKCS12_EXT, :CLOCK_SKEW_OFFSET_SEC

    class << self
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

      # @return a list of Certificates from chain file
      def read_chain_file(chain)
        File.read(chain).scan(/-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m).map{ |i| OpenSSL::X509::Certificate.new(i)}
      end
    end

    # @param url   [URI]    Local address where server will listen (use scheme, host and port only)
    # @param cert  [String] Path to certificate file, either with extension .p12 or .pfx, else assumed PEM
    # @param key   [String] Path to key file (PEM) or passphrase (pkcs12)
    # @param chain [String] Path to certificate chain file (PEM only)
    def initialize(uri, cert: nil, key: nil, chain: nil)
      Aspera.assert_type(uri, URI)
      @uri = uri
      # see https://www.rubydoc.info/stdlib/webrick/WEBrick/Config
      webrick_options = {
        BindAddress: @uri.host,
        Port:        @uri.port,
        Logger:      Log.log,
        AccessLog:   [[self, WEBrick::AccessLog::COMMON_LOG_FORMAT]] # replace default access log to call local method "<<" below
      }
      case @uri.scheme
      when 'http'
        Log.log.debug('HTTP mode')
      when 'https'
        webrick_options[:SSLEnable] = true
        if cert.nil? && key.nil?
          webrick_options[:SSLCertName] = [['CN', WEBrick::Utils.getservername]]
        elsif cert && PKCS12_EXT.include?(File.extname(cert).downcase)
          # PKCS12
          Log.log.debug('Using PKCS12 certificate')
          raise Error, 'PKCS12 requires a key (password)' if key.nil?
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
          webrick_options[:SSLExtraChainCert] = read_chain_file(chain) unless chain.nil?
          raise Error, 'key and cert do not match' unless webrick_options[:SSLCertificate].public_key.to_der == webrick_options[:SSLPrivateKey].public_key.to_der
        end
      end
      # call constructor of parent class, but capture STDERR
      # self signed certificate generates characters on STDERR
      # see create_self_signed_cert in webrick/ssl.rb
      Log.capture_stderr{super(webrick_options)}
    end

    # blocking
    def start
      Log.log.info{"Listening on #{@uri}"}
      # kill (-TERM) for graceful shutdown
      handler = proc{shutdown}
      %i{INT TERM}.each{ |sig| trap(sig, &handler)}
      super
    end

    # log web server access ( option AccessLog )
    def <<(access_log)
      Log.log.debug{"webrick log #{access_log.chomp}"}
    end
  end
end
