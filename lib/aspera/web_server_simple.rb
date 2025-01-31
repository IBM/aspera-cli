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
    CERT_PARAMETERS = %i[key cert chain pkcs12].freeze
    GENERIC_ISSUER = '/C=FR/O=Test/OU=Test/CN=Test'
    ONE_YEAR_SECONDS = 365 * 24 * 60 * 60

    private_constant :CERT_PARAMETERS, :GENERIC_ISSUER, :ONE_YEAR_SECONDS

    class << self
      # Fill and self sign provided certificate
      def fill_self_signed_cert(cert, key, digest = 'SHA256')
        cert.subject = cert.issuer = OpenSSL::X509::Name.parse(GENERIC_ISSUER)
        cert.not_before = cert.not_after = Time.now
        cert.not_after += ONE_YEAR_SECONDS
        cert.public_key = key.public_key
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
        cert.sign(key, OpenSSL::Digest.new(digest))
      end
    end

    # @param uri [URI]
    def initialize(uri, certificate: nil)
      @url = uri
      # see https://www.rubydoc.info/stdlib/webrick/WEBrick/Config
      webrick_options = {
        BindAddress: uri.host,
        Port:        uri.port,
        Logger:      Log.log,
        AccessLog:   [[self, WEBrick::AccessLog::COMMON_LOG_FORMAT]] # replace default access log to call local method "<<" below
      }
      case uri.scheme
      when 'http'
        Log.log.debug('HTTP mode')
      when 'https'
        webrick_options[:SSLEnable] = true
        if certificate.nil?
          webrick_options[:SSLCertName] = [['CN', WEBrick::Utils.getservername]]
        else
          Aspera.assert_type(certificate, Hash)
          certificate = certificate.symbolize_keys
          raise "unexpected key in certificate config: only: #{CERT_PARAMETERS.join(', ')}" if certificate.keys.any?{|key|!CERT_PARAMETERS.include?(key)}
          if certificate.key?(:pkcs12)
            Log.log.debug('Using PKCS12 certificate')
            raise 'pkcs12 requires a key (password)' unless certificate.key?(:key)
            pkcs12 = OpenSSL::PKCS12.new(File.read(certificate[:pkcs12]), certificate[:key])
            webrick_options[:SSLCertificate] = pkcs12.certificate
            webrick_options[:SSLPrivateKey] = pkcs12.key
            webrick_options[:SSLExtraChainCert] = pkcs12.ca_certs
          else
            Log.log.debug('Using PEM certificate')
            webrick_options[:SSLPrivateKey] = if certificate.key?(:key)
              OpenSSL::PKey::RSA.new(File.read(certificate[:key]))
            else
              OpenSSL::PKey::RSA.new(4096)
            end
            if certificate.key?(:cert)
              webrick_options[:SSLCertificate] = OpenSSL::X509::Certificate.new(File.read(certificate[:cert]))
            else
              webrick_options[:SSLCertificate] = OpenSSL::X509::Certificate.new
              self.class.fill_self_signed_cert(webrick_options[:SSLCertificate], webrick_options[:SSLPrivateKey])
            end
            if certificate.key?(:chain)
              webrick_options[:SSLExtraChainCert] = [OpenSSL::X509::Certificate.new(File.read(certificate[:chain]))]
            end
          end
        end
      end
      # call constructor of parent class, but capture STDERR
      # self signed certificate generates characters on STDERR
      # see create_self_signed_cert in webrick/ssl.rb
      Log.capture_stderr { super(webrick_options) }
    end

    # blocking
    def start
      Log.log.info{"Listening on #{@url}"}
      # kill -HUP for graceful shutdown
      Kernel.trap('HUP') { shutdown }
      super
    end

    # log web server access ( option AccessLog )
    def <<(access_log)
      Log.log.debug{"webrick log #{access_log.chomp}"}
    end
  end
end
