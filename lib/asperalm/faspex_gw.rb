require 'sinatra/base'
require 'webrick'
require 'webrick/https'
require 'openssl'
require 'logger'
require 'json'

# from connect client
$PRIVATE_KEY="-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC9roQ8WMLSprIM
Ljo9t9mP1xrH6+xkEVO+tF6KYGBIlnmrpo9J0gRJnf7Bpd0abjE3N75/wQQErG34
TVQ4PVWX3DC16S5fjsxoCFnhuXiK7ZKZpwfYH7rRCFQIjy4wHErMS/21FrHGF4o3
7yRVwGb5nPRHXodYzN3inIberzbbeTTHkUJ6N7KMyNW4lF1CToxE7Eunrqm+HZa0
0AlwrqbyVVdbqr6qvZ7FjGTjKEF49O/xhQhnqiJlw8I3J1El3CoR1KqI4DImdVca
rM+oVe3OLAcZuYFORzMdxgxht4iz8Xbov8BS3BE/Oh1e2VSWPDp9cadvowjvyfQq
peUggD8TAgMBAAECggEABlLwM7bd3/oQy5kq9e3QQhxw1yOFgRyWxy/qSwDFlQX3
ToLCGjr3S6EJ4ljuUzhDSc0A++9qe+Fn1TR2z100IlkEAryggC0ZoYpNvNnbK/6Z
uae4+jqsltWJP7POXWpEECWkcsor6SfVwuGlO3qrtDzIZCzBpHNIHosLcBc1ZAHK
yQWoX82wnWH7Xvkfetix4nYFR/CkIG/7dCguc8Zccd3QoBu6XExaOauKbDdytXiN
rLHlNVC4TZHywY2eaApEa8TqBcBLt1yubdrYPmt1O9NSDQ9alHRZu27wdduHtMeq
oFc2E5Ys8J1uy7XsDY2In9AnHqVo+bJFB3IR9JnyoQKBgQDqRlL3z1BvlViAc7Gs
4x/Q+fLB2BAOkVczOz2xE8XoVZhxyP1saJ6dsuPdQo+EDOAWuD0dzu7UlGkWAdn6
x616zkKW2ij3T8ilAuFAjL9m3qrorutaRxiu7VtXbNZDfT7L3iN0bz9eLHu+CCSs
1dHOW8XjcWrXw1WBTbj3//5R0QKBgQDPRY5EZ2kHUoVzgJSbDUP4Mvexpp8vJFOV
BK+ue4KrmvMz2LLj417L4ORFk31VKDaxAgfXAXu6vrIno4IQsjng0cQ/MGCXjd6/
nvfzuCbpb518kj3ZuSje5fCi0fd3Fqs9QmYeVirfgJkvDQsmHUG/Cru1IxBItfmT
0aqQuWp3owKBgD7h5206yVVaGepIo51LTYPzQzTCwPSYEHbg5Ns9+nY1W3jXQSaz
IjgkB0OhlRIVvqR6iXUR0UtgFqDgmFjW9fqrmHYTUsGnOa0JC9serFV5WRihsuyF
ftudPFJIFW8CFDP2iT+8iJ7Hg+NrHiUCM5GXUpONIueNN8tASHDQ1ruxAoGBAKD6
AWMo+U5BjfnFrCS76cUTOIJVyR3g1bVPvW4C6NqEbkwfCdip1w766+8JfHat08Qn
spUOxtyjjFPyzmpPMVplMEhvNyWdfplOSn6T0EzObf64yaaWAqMS7JBYCB0KkxXx
wsPe4k9RXidHtxfz8wL/wAcPY29FPb/LP/BEwOaHAoGAXGDsZ/YlB5yjfn4JkIUq
V5mQHJRtcl8AZWhZGgadorjnxNiOTeCsX05Mb4WNgWi20WJmtUVhDUPoG3KbrCgO
Z7tF835k+lgKuE8FVHfilIOiftbBeXjPpGH+/37tcdf20pfVX4t0aJXKVK/6Dr7K
l9NvUUMWt1DSybWrDTwUanw=
-----END PRIVATE KEY-----"
$CERTIFICATE="-----BEGIN CERTIFICATE-----
MIIENjCCAx6gAwIBAgIBATANBgkqhkiG9w0BAQUFADBvMQswCQYDVQQGEwJTRTEU
MBIGA1UEChMLQWRkVHJ1c3QgQUIxJjAkBgNVBAsTHUFkZFRydXN0IEV4dGVybmFs
IFRUUCBOZXR3b3JrMSIwIAYDVQQDExlBZGRUcnVzdCBFeHRlcm5hbCBDQSBSb290
MB4XDTAwMDUzMDEwNDgzOFoXDTIwMDUzMDEwNDgzOFowbzELMAkGA1UEBhMCU0Ux
FDASBgNVBAoTC0FkZFRydXN0IEFCMSYwJAYDVQQLEx1BZGRUcnVzdCBFeHRlcm5h
bCBUVFAgTmV0d29yazEiMCAGA1UEAxMZQWRkVHJ1c3QgRXh0ZXJuYWwgQ0EgUm9v
dDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALf3GjPm8gAELTngTlvt
H7xsD821+iO2zt6bETOXpClMfZOfvUq8k+0DGuOPz+VtUFrWlymUWoCwSXrbLpX9
uMq/NzgtHj6RQa1wVsfwTz/oMp50ysiQVOnGXw94nZpAPA6sYapeFI+eh6FqUNzX
mk6vBbOmcZSccbNQYArHE504B4YCqOmoaSYYkKtMsE8jqzpPhNjfzp/haW+710LX
a0Tkx63ubUFfclpxCDezeWWkWaCUN/cALw3CknLa0Dhy2xSoRcRdKn23tNbE7qzN
E0S3ySvdQwAl+mG5aWpYIxG3pzOPVnVZ9c0p10a3CitlttNCbxWyuHv77+ldU9U0
WicCAwEAAaOB3DCB2TAdBgNVHQ4EFgQUrb2YejS0Jvf6xCZU7wO94CTLVBowCwYD
VR0PBAQDAgEGMA8GA1UdEwEB/wQFMAMBAf8wgZkGA1UdIwSBkTCBjoAUrb2YejS0
Jvf6xCZU7wO94CTLVBqhc6RxMG8xCzAJBgNVBAYTAlNFMRQwEgYDVQQKEwtBZGRU
cnVzdCBBQjEmMCQGA1UECxMdQWRkVHJ1c3QgRXh0ZXJuYWwgVFRQIE5ldHdvcmsx
IjAgBgNVBAMTGUFkZFRydXN0IEV4dGVybmFsIENBIFJvb3SCAQEwDQYJKoZIhvcN
AQEFBQADggEBALCb4IUlwtYj4g+WBpKdQZic2YR5gdkeWxQHIzZlj7DYd7usQWxH
YINRsPkyPef89iYTx4AWpb9a/IfPeHmJIZriTAcKhjW88t5RxNKWt9x+Tu5w/Rw5
6wwCURQtjr0W4MHfRnXnJK3s9EK0hZNwEGe6nQY1ShjTK3rMUUKhemPR5ruhxSvC
Nr4TDea9Y355e6cJDUCrat2PisP29owaQgVR1EX1n6diIWgVIEM8med8vSTYqZEX
c4g/VhsxOBi0cQ+azcgOno4uG+GMmIPLHzHxREzGBHNJdmAPx/i9F4BrLunMTA5a
mnkPIAou1Z5jJh5VkpTYghdae9C8x49OhgQ=
-----END CERTIFICATE-----"
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
      :SSLCertificate     => OpenSSL::X509::Certificate.new($CERTIFICATE),
      :SSLPrivateKey      => OpenSSL::PKey::RSA.new($PRIVATE_KEY),
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
