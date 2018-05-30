require 'asperalm/log'
require 'base64'

module Asperalm
  class FilesApi
    # various API scopes supported
    SCOPE_FILES_SELF='self'
    SCOPE_FILES_USER='user:all'
    SCOPE_FILES_ADMIN='admin:all'
    SCOPE_FILES_ADMIN_USER='admin-user:all'
    SCOPE_FILES_ADMIN_USER_USER=SCOPE_FILES_ADMIN_USER+'+'+SCOPE_FILES_USER
    SCOPE_NODE_USER='user:all'
    SCOPE_NODE_ADMIN='admin:all'
    
    RANDOM='==QMGdXZsdkYMlDezZ3MNhDStYFWQNXNrZTOPRmYh10ZmJkN2EnZCFHbFxkRQtmNylTQOpHdtdUTPNFTxFGWFdFWFB1dr1iNK5WTadTLSFGWBlFTkVDdoxkYjx0MRp3ZlVlOlZXayRmLhJXZwNXY';

    # get necessary fixed information to create JWT or call API
    # instance domain is asperafiles.com or qa.asperafiles.com
    def self.info(web_url)
      uri=URI.parse(web_url.gsub(/\/+$/,''))
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
    
    def self.get_random
      Base64.strict_decode64(RANDOM.reverse).split(':')
    end

  end # FilesApi
end # Asperalm
