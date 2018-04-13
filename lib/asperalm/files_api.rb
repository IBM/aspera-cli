require 'asperalm/log'

module Asperalm
  class FilesApi
    # get API base URL based on instance domain
    # instance domain is asperafiles.com or qa.asperafiles.com
    def self.info(web_url)
      uri=URI.parse(web_url)
      instance_fqdn=uri.host
      raise "No host found in URL.Please check URL format: https://myorg.ibmaspera.com" if instance_fqdn.nil?
      organization,instance_domain=instance_fqdn.split('.',2)
      raise "expecting a public FQDN for Files" if instance_domain.nil?
      Log.log.debug("instance_fqdn=#{instance_fqdn}")
      Log.log.debug("instance_domain=#{instance_domain}")
      Log.log.debug("organization=#{organization}")
      return {
        :web_url         => web_url,
        :organization    => organization,
        :domain          => instance_domain,
        :api_url         => 'https://api.'+instance_domain+'/api/v1',
        :jwt_audience    => 'https://api.asperafiles.com/api/v1/oauth2/token',
        :oauth_authorize => "oauth2/#{organization}/authorize",
        :oauth_token     => "oauth2/#{organization}/token"
      }
    end

    # node API scopes
    def self.node_scope(access_key,scope)
      return 'node.'+access_key+':'+scope
    end

    # various API scopes supported
    SCOPE_FILES_SELF='self'
    SCOPE_FILES_USER='user:all'
    SCOPE_FILES_ADMIN='admin:all'
    SCOPE_FILES_ADMIN_USER='admin-user:all+user:all'
    SCOPE_NODE_USER='user:all'
    SCOPE_NODE_ADMIN='admin:all'

  end # FilesApi
end # Asperalm
