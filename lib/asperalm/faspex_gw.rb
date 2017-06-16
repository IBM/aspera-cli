require 'asperalm/log'
require 'asperalm/connect'
require 'sinatra/base'
require 'webrick'
require 'webrick/https'
require 'webrick/log'
require 'openssl'
require 'json'

module Asperalm
  class FaspexGW < Sinatra::Base
    def self.go(api_files_user,workspace_id)
      @@api_files_user=api_files_user
      @@the_workspaceid=workspace_id
      $CERTIFICATE=File.read(Connect.path(:localhost_cert))
      $PRIVATE_KEY=File.read(Connect.path(:localhost_key))
      Rack::Server.start({
        :app                => FaspexGW,
        :Port               => 9443,
#        :Logger             => WEBrick::Log::new($stderr, WEBrick::Log::ERROR),
        :Logger             => Log.log,
        :DocumentRoot       => "/ruby/htdocs",
        :SSLEnable          => true,
        :SSLVerifyClient    => OpenSSL::SSL::VERIFY_NONE,
        :SSLCertificate     => OpenSSL::X509::Certificate.new($CERTIFICATE),
        :SSLPrivateKey      => OpenSSL::PKey::RSA.new($PRIVATE_KEY),
        :SSLCertName        => [ [ "CN",WEBrick::Utils::getservername ] ]
      })
    end

    post '/aspera/faspex/send' do
      # parameters from user to Faspex API call
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

      faspex_pkg_parameters=JSON.parse(request.body.read)
      faspex_pkg_delivery=faspex_pkg_parameters['delivery']
      Log.log.debug "faspex pkg create parameters=#{faspex_pkg_parameters}"

      # TODO: get from parameters
      files_pkg_recipients=[]
      faspex_pkg_delivery['recipients'].each do |recipient_email|
        user_lookup=@@api_files_user.list("contacts",{'current_workspace_id'=>@@the_workspaceid,'q'=>recipient_email})[:data]
        raise StandardError,"no such unique user: #{recipient_email} / #{user_lookup}" unless !user_lookup.nil? and user_lookup.length == 1
        recipient_user_info=user_lookup.first
        files_pkg_recipients.push({"id"=>recipient_user_info['source_id'],"type"=>recipient_user_info['source_type']})
      end

      # NOTE: important: transfer id must be unique: generate random id (using a non unique id results in discard of tags)
      xfer_id=SecureRandom.uuid
      Log.log.debug "xfer id=#{xfer_id}"

      #  create a new package with one file
      the_package=@@api_files_user.create("packages",{
        "file_names"=>faspex_pkg_delivery['sources'][0]['paths'],
        "name"=>faspex_pkg_delivery['title'],
        "note"=>faspex_pkg_delivery['note'],
        "recipients"=>files_pkg_recipients,
        "workspace_id"=>@@the_workspaceid})[:data]

      #  get node information for the node on which package must be created
      node_info=@@api_files_user.read("nodes/#{the_package['node_id']}")[:data]

      #  get transfer token (for node)
      node_auth_bearer_token=@@api_files_user.param_default[:oauth].get_authorization(FilesApi.node_scope(node_info['access_key'],FilesApi::SCOPE_NODE_USER))

      # tell Files what to expect in package: 1 transfer (can also be done after transfer)
      @@api_files_user.update("packages/#{the_package['id']}",{"sent"=>true,"transfers_expected"=>1})

      if false
        status 400
        return "ERROR HERE"
      end
      status 200
      faspex_transfer_spec_result={
        "xfer_sessions" => [
        {
        "https_fallback_port" => nil,
        "cookie" => "unused",
        "tags" => { "aspera" => { "files" => { "package_id" => the_package['id'], "package_operation" => "upload" }, "node" => { "access_key" => node_info['access_key'], "file_id" => the_package['contents_file_id'] }, "xfer_id" => xfer_id, "xfer_retry" => 3600 } },
        "rate_policy" => "fair",
        "rate_policy_allowed" => "fixed",
        "min_rate_cap_kbps" => nil,
        "min_rate_kbps" => 0,
        "remote_user" => "xfer",
        "remote_host" => node_info['host'],
        "target_rate_percentage" => nil,
        "lock_target_rate" => nil,
        "fasp_url" => "unused",
        "lock_rate_policy" => true,
        "source_root" => "",
        "content_protection" => nil,
        "target_rate_cap_kbps" => 20000,
        "target_rate_kbps" => 10000,
        "cipher" => "aes-128",
        "cipher_allowed" => nil,
        "http_fallback" => false,
        "token" => node_auth_bearer_token,
        "destination_root" => "/",
        "paths" => [
        {
        "destination" => "/"
        }
        ],
        "http_fallback_port" => nil,
        "lock_min_rate" => true,
        "direction" => "send",
        "fasp_port" => 33001,
        "create_dir" => true,
        "ssh_port" => 33001
        }
        ],
        "links" => {
        "status" => "unused"
        }
      }
      Log.log.info "faspex_transfer_spec_result=#{faspex_transfer_spec_result}"
      return JSON.generate(faspex_transfer_spec_result)
    end
  end
end
