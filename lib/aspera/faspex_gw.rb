require 'aspera/log'
require 'aspera/aoc'
require 'aspera/node'
require 'aspera/cli/main'
require 'webrick'
require 'webrick/https'
require 'securerandom'
require 'openssl'
require 'json'

module Aspera
  # this class answers the Faspex /send API and creates a package on Aspera on Cloud
  class FaspexGW
    class FxGwServlet < WEBrick::HTTPServlet::AbstractServlet
      def initialize(server,a_aoc_api_user,a_workspace_id)
        @aoc_api_user=a_aoc_api_user
        @aoc_workspace_id=a_workspace_id
      end

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
      def process_faspex_send(request, response)
        raise "no payload" if request.body.nil?
        faspex_pkg_parameters=JSON.parse(request.body)
        faspex_pkg_delivery=faspex_pkg_parameters['delivery']
        Log.log.debug "faspex pkg create parameters=#{faspex_pkg_parameters}"

        # get recipient ids
        files_pkg_recipients=[]
        faspex_pkg_delivery['recipients'].each do |recipient_email|
          user_lookup=@aoc_api_user.read("contacts",{'current_workspace_id'=>@aoc_workspace_id,'q'=>recipient_email})[:data]
          raise StandardError,"no such unique user: #{recipient_email} / #{user_lookup}" unless !user_lookup.nil? and user_lookup.length == 1
          recipient_user_info=user_lookup.first
          files_pkg_recipients.push({"id"=>recipient_user_info['source_id'],"type"=>recipient_user_info['source_type']})
        end

        #  create a new package with one file
        the_package=@aoc_api_user.create("packages",{
          "file_names"=>faspex_pkg_delivery['sources'][0]['paths'],
          "name"=>faspex_pkg_delivery['title'],
          "note"=>faspex_pkg_delivery['note'],
          "recipients"=>files_pkg_recipients,
          "workspace_id"=>@aoc_workspace_id})[:data]

        #  get node information for the node on which package must be created
        node_info=@aoc_api_user.read("nodes/#{the_package['node_id']}")[:data]

        #  get transfer token (for node)
        node_auth_bearer_token=@aoc_api_user.oauth_token(scope: AoC.node_scope(node_info['access_key'],AoC::SCOPE_NODE_USER))

        # tell Files what to expect in package: 1 transfer (can also be done after transfer)
        @aoc_api_user.update("packages/#{the_package['id']}",{"sent"=>true,"transfers_expected"=>1})

        if false
          response.status=400
          return "ERROR HERE"
        end
        # TODO: check about xfer_*
        ts_tags={
          "aspera" => {
          "files"      => { "package_id" => the_package['id'], "package_operation" => "upload" },
          "node"       => { "access_key" => node_info['access_key'], "file_id" => the_package['contents_file_id'] },
          "xfer_id"    => SecureRandom.uuid,
          "xfer_retry" => 3600 } }
        # this transfer spec is for transfer to AoC
        faspex_transfer_spec={
          'direction'   => 'send',
          'remote_host' => node_info['host'],
          'remote_user' => Node::ACCESS_KEY_TRANSFER_USER,
          'ssh_port'    => Node::SSH_PORT_DEFAULT,
          'fasp_port'   => Node::UDP_PORT_DEFAULT
          'tags'        => ts_tags,
          'token'       => node_auth_bearer_token,
          'paths'       => [{'destination' => '/'}],
          'cookie'      => 'unused',
          'create_dir'  => true,
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
        Log.log.info("faspex_package_create_result=#{faspex_package_create_result}")
        response.status=200
        response.content_type = "application/json"
        response.body=JSON.generate(faspex_package_create_result)
      end

      def do_GET (request, response)
        case request.path
        when '/aspera/faspex/send'
          process_faspex_send(request, response)
        else
          response.status=400
          return "ERROR HERE"
          raise "unsupported path: #{request.path}"
        end
      end
    end # FxGwServlet

    class NewUserServlet < WEBrick::HTTPServlet::AbstractServlet
      def do_GET (request, response)
        case request.path
        when '/newuser'
          response.status=200
          response.content_type = "text/html"
          response.body='<html><body>hello world</body></html>'
        else
          raise "unsupported path: [#{request.path}]"
        end
      end
    end

    def fill_self_signed_cert(options)
      key = OpenSSL::PKey::RSA.new(4096)
      cert = OpenSSL::X509::Certificate.new
      cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/C=FR/O=Test/OU=Test/CN=Test")
      cert.not_before = Time.now
      cert.not_after = Time.now + 365 * 24 * 60 * 60
      cert.public_key = key.public_key
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
      cert.sign(key, OpenSSL::Digest::SHA256.new)
      options[:SSLPrivateKey]  = key
      options[:SSLCertificate] = cert
    end

    def initialize(a_aoc_api_user,a_workspace_id)
      webrick_options = {
        :app                => FaspexGW,
        :Port               => 9443,
        :Logger             => Log.log,
        #:DocumentRoot       => Cli::Main.gem_root,
        :SSLEnable          => true,
        :SSLVerifyClient    => OpenSSL::SSL::VERIFY_NONE,
      }
      case 2
      when 0
        # generate self signed cert
        webrick_options[:SSLCertName]    = [ [ 'CN',WEBrick::Utils::getservername ] ]
        Log.log.error(">>>#{webrick_options[:SSLCertName]}")
      when 1
        fill_self_signed_cert(webrick_options)
      when 2
        webrick_options[:SSLPrivateKey] =OpenSSL::PKey::RSA.new(File.read('/Users/laurent/workspace/Tools/certificate/myserver.key'))
        webrick_options[:SSLCertificate] = OpenSSL::X509::Certificate.new(File.read('/Users/laurent/workspace/Tools/certificate/myserver.crt'))
      end
      Log.log.info("Server started on port #{webrick_options[:Port]}")
      @server = WEBrick::HTTPServer.new(webrick_options)
      @server.mount('/aspera/faspex', FxGwServlet,a_aoc_api_user,a_workspace_id)
      @server.mount('/newuser', NewUserServlet)
      trap('INT') {@server.shutdown}
    end

    def start_server
      @server.start
    end
  end # FaspexGW
end # AsperaLm
