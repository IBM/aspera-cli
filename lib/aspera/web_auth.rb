# frozen_string_literal: true
require 'webrick'
require 'webrick/https'

module Aspera
  # servlet called on callback: it records the callback request
  class WebAuthServlet < WEBrick::HTTPServlet::AbstractServlet
    def initialize(_server,application) # additional args get here
      super
      Log.log.debug('WebAuthServlet.new')
      @app=application
    end

    def service(request, response)
      if !request.path.eql?(@app.expected_path)
        Log.log.error("unexpected path: #{request.path}")
        response.status=400
        return
      end
      # acquire lock and signal change
      @app.mutex.synchronize do
        @app.query=request.query
        @app.cond.signal
      end
      response.status=200
      response.content_type = 'text/html'
      response.body='<html><head><title>Ok</title></head><body><h1>Thank you !</h1><p>You can close this window.</p></body></html>'
    end
  end # WebAuthServlet

  # start a local web server, then start a browser that will callback the local server upon authentication
  class WebAuth
    #      # generates and adds self signed cert to provided webrick options
    #      def fill_self_signed_cert(cert,key)
    #        cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/C=FR/O=Test/OU=Test/CN=Test')
    #        cert.not_before = Time.now
    #        cert.not_after = Time.now + 365 * 24 * 60 * 60
    #        cert.public_key = key.public_key
    #        cert.serial = 0x0
    #        cert.version = 2
    #        ef = OpenSSL::X509::ExtensionFactory.new
    #        ef.issuer_certificate = cert
    #        ef.subject_certificate = cert
    #        cert.extensions = [
    #          ef.create_extension('basicConstraints','CA:TRUE', true),
    #          ef.create_extension('subjectKeyIdentifier', 'hash'),
    #          # ef.create_extension('keyUsage', 'cRLSign,keyCertSign', true),
    #        ]
    #        cert.add_extension(ef.create_extension('authorityKeyIdentifier','keyid:always,issuer:always'))
    #        cert.sign(key, OpenSSL::Digest::SHA256.new)
    #      end
    attr_reader :expected_path,:mutex,:cond
    attr_writer :query
    # @param endpoint_url [String] e.g. 'https://127.0.0.1:12345'
    def initialize(endpoint_url)
      uri=URI.parse(endpoint_url)
      # parameters for servlet
      @query=nil
      @mutex=Mutex.new
      @cond=ConditionVariable.new
      @expected_path=uri.path.empty? ? '/' : uri.path
      # see https://www.rubydoc.info/stdlib/webrick/WEBrick/Config
      webrick_options = {
        BindAddress: uri.host,
        Port:        uri.port,
        Logger:      Log.log
      }
      case uri.scheme
      when 'http'
        Log.log.debug('HTTP mode')
      when 'https'
        webrick_options[:SSLEnable]=true
        webrick_options[:SSLVerifyClient] = OpenSSL::SSL::VERIFY_NONE
        # a- automatic certificate generation
        webrick_options[:SSLCertName] = [['CN',WEBrick::Utils.getservername]]
        # b- generate self signed cert
        #webrick_options[:SSLPrivateKey]   = OpenSSL::PKey::RSA.new(4096)
        #webrick_options[:SSLCertificate]  = OpenSSL::X509::Certificate.new
        #self.class.fill_self_signed_cert(webrick_options[:SSLCertificate],webrick_options[:SSLPrivateKey])
        ## c- good cert
        #webrick_options[:SSLPrivateKey]  = OpenSSL::PKey::RSA.new(File.read('.../myserver.key'))
        #webrick_options[:SSLCertificate] = OpenSSL::X509::Certificate.new(File.read('.../myserver.crt'))
      end
      @server = WEBrick::HTTPServer.new(webrick_options)
      @server.mount(@expected_path, WebAuthServlet, self) # additional args provided to constructor
      Thread.new { @server.start }
    end

    # wait for request on web server
    # @return Hash the query
    def received_request
      Log.log.debug('received_request')
      # shall be called only once
      raise 'error, received_request called twice ?' if @server.nil?
      # wait for signal from thread
      @mutex.synchronize{@cond.wait(@mutex)}
      # tell server thread to stop
      @server.shutdown
      @server=nil
      return @query
    end
  end
end
