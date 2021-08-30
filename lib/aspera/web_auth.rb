require 'webrick'
require 'webrick/https'
require 'thread'

module Aspera
  class WebAuth
    # server for auth page
    class FxGwServlet < WEBrick::HTTPServlet::AbstractServlet
      def initialize(server,info) # additional args get here
        @shared=info
      end

      def do_GET (request, response)
        if ! request.path.eql?(@shared[:expected_path])
          response.status=400
          return
        end
        @shared[:mutex].synchronize do
          @shared[:query]=request.query
          @shared[:cond].signal
        end
        response.status=200
        response.content_type = 'text/html'
        response.body='<html><head><title>Ok</title></head><body><h1>Thank you !</h1><p>You can close this window.</p></body></html>'
      end
    end # FxGwServlet

    # generates and adds self signed cert to provided webrick options
    def fill_self_signed_cert(options)
      key = OpenSSL::PKey::RSA.new(4096)
      cert = OpenSSL::X509::Certificate.new
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
        ef.create_extension('basicConstraints','CA:TRUE', true),
        ef.create_extension('subjectKeyIdentifier', 'hash'),
        # ef.create_extension('keyUsage', 'cRLSign,keyCertSign', true),
      ]
      cert.add_extension(ef.create_extension('authorityKeyIdentifier','keyid:always,issuer:always'))
      cert.sign(key, OpenSSL::Digest::SHA256.new)
      options[:SSLPrivateKey]  = key
      options[:SSLCertificate] = cert
    end

    def initialize(endpoint_url)
      uri=URI.parse(endpoint_url)
      webrick_options = {
        :app                => WebAuth,
        :Port               => uri.port,
        :Logger             => Log.log
      }
      uri_path=uri.path.empty? ? '/' : uri.path
      case uri.scheme
      when 'http'
        Log.log.debug('HTTP mode')
      when 'https'
        webrick_options[:SSLEnable]=true
        webrick_options[:SSLVerifyClient]=OpenSSL::SSL::VERIFY_NONE
        case 0
        when 0
          # generate self signed cert
          fill_self_signed_cert(webrick_options)
        when 1
          # short
          webrick_options[:SSLCertName]    = [ [ 'CN',WEBrick::Utils::getservername ] ]
          Log.log.error(">>>#{webrick_options[:SSLCertName]}")
        when 2
          # good cert
          webrick_options[:SSLPrivateKey] =OpenSSL::PKey::RSA.new(File.read('/Users/laurent/workspace/Tools/certificate/myserver.key'))
          webrick_options[:SSLCertificate] = OpenSSL::X509::Certificate.new(File.read('/Users/laurent/workspace/Tools/certificate/myserver.crt'))
        end
      end
      # parameters for servlet
      @shared_info={
        expected_path: uri_path,
        mutex: Mutex.new,
        cond: ConditionVariable.new
      }
      @server = WEBrick::HTTPServer.new(webrick_options)
      @server.mount(uri_path, FxGwServlet, @shared_info) # additional args provided to constructor
      Thread.new { @server.start }
    end

    # wait for request on web server
    # @return Hash the query
    def get_request
      Log.log.debug('get_request')
      # called only once
      raise "error" if @server.nil?
      @shared_info[:mutex].synchronize do
        @shared_info[:cond].wait(@shared_info[:mutex])
      end
      @server.shutdown
      @server=nil
      return @shared_info[:query]
    end
  end
end
