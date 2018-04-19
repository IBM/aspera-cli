require 'asperalm/log'
require 'asperalm/fasp/installation'
require 'sinatra/base'
require 'webrick'
require 'webrick/https'
require 'webrick/log'
require 'openssl'
require 'json'
require 'securerandom'

module Asperalm
  # this class answers the Faspex /send API and creates a package on Files
  class FaspexGW < Sinatra::Base
    def self.start_server(api_files_user,workspace_id)
      @@api_files_user=api_files_user
      @@api_files_oauth=@@api_files_user.param_default[:auth][:obj]
      @@the_workspaceid=workspace_id
      $CERTIFICATE=File.read(Fasp::Installation.instance.path(:localhost_cert))
      $PRIVATE_KEY=File.read(Fasp::Installation.instance.path(:localhost_key))
      webrick_options = {
        :app                => FaspexGW,
        :Port               => 9443,
        :Logger             => Log.log,
        :DocumentRoot       => '/ruby/htdocs',
        :SSLEnable          => true,
        :SSLVerifyClient    => OpenSSL::SSL::VERIFY_NONE,
        :SSLCertificate     => OpenSSL::X509::Certificate.new($CERTIFICATE),
        :SSLPrivateKey      => OpenSSL::PKey::RSA.new($PRIVATE_KEY),
        :SSLCertName        => [ [ 'CN',WEBrick::Utils::getservername ] ]
      }
      puts "Server started on port #{webrick_options[:Port]}"
      Rack::Server.start(webrick_options)
    end
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
    post '/aspera/faspex/send' do
      faspex_pkg_parameters=JSON.parse(request.body.read)
      faspex_pkg_delivery=faspex_pkg_parameters['delivery']
      Log.log.debug "faspex pkg create parameters=#{faspex_pkg_parameters}"

      # get recipient ids
      files_pkg_recipients=[]
      faspex_pkg_delivery['recipients'].each do |recipient_email|
        user_lookup=@@api_files_user.read("contacts",{'current_workspace_id'=>@@the_workspaceid,'q'=>recipient_email})[:data]
        raise StandardError,"no such unique user: #{recipient_email} / #{user_lookup}" unless !user_lookup.nil? and user_lookup.length == 1
        recipient_user_info=user_lookup.first
        files_pkg_recipients.push({"id"=>recipient_user_info['source_id'],"type"=>recipient_user_info['source_type']})
      end

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
      node_auth_bearer_token=@@api_files_oauth.get_authorization(FilesApi.node_scope(node_info['access_key'],FilesApi::SCOPE_NODE_USER))

      # tell Files what to expect in package: 1 transfer (can also be done after transfer)
      @@api_files_user.update("packages/#{the_package['id']}",{"sent"=>true,"transfers_expected"=>1})

      if false
        status 400
        return "ERROR HERE"
      end
      status 200
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
      return JSON.generate(faspex_package_create_result)
    end
  end # FaspexGW
end # AsperaLm
