require 'sinatra/base'
require 'webrick'
require 'webrick/https'
require 'openssl'
require 'logger'
require 'json'

CERT_PATH = 'data'

class FaspexGW < Sinatra::Base
  def self.set_vars(logger,api_files_user,oauthapi)
    @@api_files_user=api_files_user
    @@logger=logger
    @@oauthapi=oauthapi
  end

  def self.go
    Rack::Server.start({
      :Port               => 9443,
      :Logger             => WEBrick::Log::new($stderr, WEBrick::Log::ERROR),
      :DocumentRoot       => "/ruby/htdocs",
      :SSLEnable          => true,
      :SSLVerifyClient    => OpenSSL::SSL::VERIFY_NONE,
      :SSLCertificate     => OpenSSL::X509::Certificate.new(  File.open(File.join(CERT_PATH, "localhost.crt")).read),
      :SSLPrivateKey      => OpenSSL::PKey::RSA.new(          File.open(File.join(CERT_PATH, "localhost.key")).read),
      :SSLCertName        => [ [ "CN",WEBrick::Utils::getservername ] ],
      :app                => FaspexGW
    })
  end

  post '/aspera/faspex/send' do
    calldata=JSON.parse(request.body.read)
    #@logger.info "body=#{request.body.read}"
    #@logger.info "params1=#{request.params}"
    #@logger.info "params=#{params}"

    filelist = calldata['delivery']['sources'][0]['paths']

    @@logger.info "files=#{filelist}"

    recipient='laurent@asperasoft.com'

    self_data=@@api_files_user.read("self")
    the_workspaceid=self_data['default_workspace_id']
    user_lookup=@@api_files_user.list("contacts",{'current_workspace_id'=>the_workspaceid,'q'=>recipient})
    raise "no such unique user: #{recipient}" unless !user_lookup.nil? and user_lookup.length == 1
    recipient_user_id=user_lookup.first

    # NOTE: important: transfer id must be unique: generate random id (using a non unique id results in discard of tags)
    xfer_id=SecureRandom.uuid

    #  create a new package with one file
    the_package=@@api_files_user.create("packages",{"file_names"=>filelist,"name"=>"sent from script","note"=>"trid=#{xfer_id}","recipients"=>[{"id"=>recipient_user_id['source_id'],"type"=>recipient_user_id['source_type']}],"workspace_id"=>the_workspaceid})

    #  get node information for the node on which package must be created
    node_info=@@api_files_user.read("nodes",the_package['node_id'])

    #  get transfer token (for node)
    node_auth_bearer_token=@@oauthapi.get_authorization('node.'+node_info['access_key']+':user:all')

    # tell Files what to expect in package: 1 transfer (can also be done after transfer)
    resp=@@api_files_user.update("packages",the_package['id'],{"sent"=>true,"transfers_expected"=>1})

    if false
      status 400
      return "ERROR HERE"
    end
    status 200
    result={
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
    @@logger.info "result=#{result}"
    return JSON.generate(result)
  end
end
