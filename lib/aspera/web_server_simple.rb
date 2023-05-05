# frozen_string_literal: true

require 'webrick'
require 'webrick/https'
require 'aspera/log'
require 'openssl'

module Aspera
  class WebServerSimple < WEBrick::HTTPServer
    CERT_PARAMETERS = %i[key cert chain].freeze
    class << self
      # generates and adds self signed cert to provided webrick options
      def fill_self_signed_cert(cert, key)
        cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/C=FR/O=Test/OU=Test/CN=Test')
        cert.not_before = Time.now
        cert.not_after = Time.now + 365 * 24 * 60 * 60
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
        cert.sign(key, OpenSSL::Digest.new('SHA256'))
      end
    end

    # @param uri [URI]
    def initialize(uri, certificate: nil)
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
          raise 'certificate must be Hash' unless certificate.is_a?(Hash)
          certificate = certificate.symbolize_keys
          raise "unexpected key in certificate config: only: #{CERT_PARAMETERS.join(', ')}" if certificate.keys.any?{|k|!CERT_PARAMETERS.include?(k)}
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
      # self signed certificate generates characters on STDERR, see create_self_signed_cert in webrick/ssl.rb
      Log.capture_stderr { super(webrick_options) }
      # kill -USR1 for graceful shutdown
      Kernel.trap('USR1') { shutdown }
    end

    # log web server access ( option AccessLog )
    def <<(access_log)
      Log.log.debug{"webrick log #{access_log.chomp}"}
    end
  end
end
