require 'webrick'
require 'webrick/https'
require 'openssl'
require 'json'
require 'securerandom'
require 'singleton'
require 'asperalm/log'
require 'asperalm/on_cloud'

module Asperalm
  # this class answers the Faspex /send API and creates a package on Files
  class FaspexGW
    include Singleton
    class Servlet < WEBrick::HTTPServlet::AbstractServlet
      def do_GET (request, response)
        raise "unsupported path: #{request.path}" unless request.path.eql?('/aspera/faspex/send')
        # parameters from user to Faspex API call
        #{"delivery":{"use_encryption_at_rest":false,"note":"note","sources":[{"paths":["file1"]}],"title":"my title","recipients":["email1"],"send_upload_result":true}}
        #    {
        #      "delivery"=>{
        #      "use_encryption_at_rest"=>false,
        #      "note"=>"note",
        #      "sources"=>[{"paths"=>["file1"]}],
        #      "title"=>"my title",
        #      "recipients"=>["email1"],
        #      "send_upload_result"=>true
        #      }
        #    }
        raise "no payload" if request.body.nil?
        faspex_pkg_parameters=JSON.parse(request.body)
        faspex_pkg_delivery=faspex_pkg_parameters['delivery']
        Log.log.debug "faspex pkg create parameters=#{faspex_pkg_parameters}"

        # get recipient ids
        files_pkg_recipients=[]
        faspex_pkg_delivery['recipients'].each do |recipient_email|
          user_lookup=FaspexGW.instance.aoc_api_user.read("contacts",{'current_workspace_id'=>FaspexGW.instance.aoc_workspace_id,'q'=>recipient_email})[:data]
          raise StandardError,"no such unique user: #{recipient_email} / #{user_lookup}" unless !user_lookup.nil? and user_lookup.length == 1
          recipient_user_info=user_lookup.first
          files_pkg_recipients.push({"id"=>recipient_user_info['source_id'],"type"=>recipient_user_info['source_type']})
        end

        #  create a new package with one file
        the_package=FaspexGW.instance.aoc_api_user.create("packages",{
          "file_names"=>faspex_pkg_delivery['sources'][0]['paths'],
          "name"=>faspex_pkg_delivery['title'],
          "note"=>faspex_pkg_delivery['note'],
          "recipients"=>files_pkg_recipients,
          "workspace_id"=>FaspexGW.instance.aoc_workspace_id})[:data]

        #  get node information for the node on which package must be created
        node_info=FaspexGW.instance.aoc_api_user.read("nodes/#{the_package['node_id']}")[:data]

        #  get transfer token (for node)
        node_auth_bearer_token=FaspexGW.instance.aoc_api_user.oauth_token(scope: OnCloud.node_scope(node_info['access_key'],OnCloud::SCOPE_NODE_USER))

        # tell Files what to expect in package: 1 transfer (can also be done after transfer)
        FaspexGW.instance.aoc_api_user.update("packages/#{the_package['id']}",{"sent"=>true,"transfers_expected"=>1})

        if false
          response.status=400
          return "ERROR HERE"
        end
        response.status=200
        # TODO: check about xfer_*
        ts_tags={
          "aspera" => {
          "files"      => { "package_id" => the_package['id'], "package_operation" => "upload" },
          "node"       => { "access_key" => node_info['access_key'], "file_id" => the_package['contents_file_id'] },
          "xfer_id"    => SecureRandom.uuid,
          "xfer_retry" => 3600 } }
        # this transfer spec is for transfer to Files
        faspex_transfer_spec={
          'direction' => 'send',
          'remote_user' => 'xfer',
          'remote_host' => node_info['host'],
          'ssh_port' => 33001,
          'fasp_port' => 33001,
          'tags' => ts_tags,
          'token' => node_auth_bearer_token,
          'paths' => [{'destination' => '/'}],
          'cookie' => 'unused',
          'create_dir' => true,
          'rate_policy' => 'fair',
          'rate_policy_allowed' => 'fixed',
          'min_rate_cap_kbps' => nil,
          'min_rate_kbps' => 0,
          'target_rate_percentage' => nil,
          'lock_target_rate' => nil,
          'fasp_url' => 'unused',
          'lock_min_rate' => true,
          'lock_rate_policy' => true,
          'source_root' => '',
          'content_protection' => nil,
          'target_rate_cap_kbps' => 20000, # TODO
          'target_rate_kbps' => 10000, # TODO
          'cipher' => 'aes-128',
          'cipher_allowed' => nil,
          'http_fallback' => false,
          'http_fallback_port' => nil,
          'https_fallback_port' => nil,
          'destination_root' => '/'
        }
        # but we place it in a Faspex package creation response
        faspex_package_create_result={
          'links' => {'status' => 'unused'},
          'xfer_sessions' => [faspex_transfer_spec]
        }
        Log.log.info "faspex_package_create_result=#{faspex_package_create_result}"
        response.content_type = "application/json"
        response.body=JSON.generate(faspex_package_create_result)
      end
    end # Servlet

    TEST_SUBJECT="/C=FR/O=Test/OU=Test/CN=Test"
    
    def initialize
      @webrick_options = {
        :app                => FaspexGW,
        :Port               => 9443,
        :Logger             => Log.log,
        #:DocumentRoot       => '/ruby/htdocs',
        :SSLEnable          => true,
        :SSLVerifyClient    => OpenSSL::SSL::VERIFY_NONE,
        :SSLCertName        => [ [ 'CN',WEBrick::Utils::getservername ] ],
        :SSLPrivateKey      => OpenSSL::PKey::RSA.new(4096),
        :SSLCertificate     => OpenSSL::X509::Certificate.new
      }
      cert = @webrick_options[:SSLCertificate]
      cert.subject = cert.issuer = OpenSSL::X509::Name.parse(TEST_SUBJECT)
      cert.not_before = Time.now
      cert.not_after = Time.now + 365 * 24 * 60 * 60
      cert.public_key = @webrick_options[:SSLPrivateKey].public_key
      cert.serial = 0x0
      cert.version = 2
      ef = OpenSSL::X509::ExtensionFactory.new
      ef.issuer_certificate = cert
      ef.subject_certificate = cert
      cert.extensions = [
        ef.create_extension("basicConstraints","CA:TRUE", true),
        ef.create_extension("subjectKeyIdentifier", "hash"),
        # ef.create_extension("keyUsage", "cRLSign,keyCertSign", true),
      ]
      cert.add_extension(ef.create_extension("authorityKeyIdentifier","keyid:always,issuer:always"))
      cert.sign(@webrick_options[:SSLPrivateKey], OpenSSL::Digest::SHA256.new)
    end

    attr_reader :aoc_api_user
    attr_reader :aoc_workspace_id

    def start_server(a_aoc_api_user,a_workspace_id)
      @aoc_api_user=a_aoc_api_user
      @aoc_workspace_id=a_workspace_id
      Log.log.info("Server started on port #{@webrick_options[:Port]}")
      server = WEBrick::HTTPServer.new(@webrick_options)
      server.mount('/aspera/faspex', Servlet)
      trap("INT") {server.shutdown}
      server.start
    end
  end # FaspexGW
end # AsperaLm
