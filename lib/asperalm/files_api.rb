require 'asperalm/log'
require 'base64'

module Asperalm
  class FilesApi
    PRODUCT_NAME='Aspera on Cloud'
    PRODUCT_DOMAIN='ibmaspera.com'
    # various API scopes supported
    SCOPE_FILES_SELF='self'
    SCOPE_FILES_USER='user:all'
    SCOPE_FILES_ADMIN='admin:all'
    SCOPE_FILES_ADMIN_USER='admin-user:all'
    SCOPE_FILES_ADMIN_USER_USER=SCOPE_FILES_ADMIN_USER+'+'+SCOPE_FILES_USER
    SCOPE_NODE_USER='user:all'
    SCOPE_NODE_ADMIN='admin:all'
    
    PATH_PUBLIC_PACKAGE='/packages/public/receive'

    # some cool random string
    # strings /Applications/Aspera\ Drive.app/Contents/MacOS/AsperaDrive|grep -E '.{100}==$'|rev
    RANDOM_SEED='==QMGdXZsdkYMlDezZ3MNhDStYFWQNXNrZTOPRmYh10ZmJkN2EnZCFHbFxkRQtmNylTQOpHdtdUTPNFTxFGWFdFWFB1dr1iNK5WTadTLSFGWBlFTkVDdoxkYjx0MRp3ZlVlOlZXayRmLhJXZwNXY';
    def self.random
      Base64.strict_decode64(RANDOM_SEED.reverse).split(':')
    end
    
    def self.parse_url(aoc_org_url)
      uri=URI.parse(aoc_org_url.gsub(/\/+$/,''))
      instance_fqdn=uri.host
      Log.log.debug("instance_fqdn=#{instance_fqdn}")
      raise "No host found in URL.Please check URL format: https://myorg.#{PRODUCT_DOMAIN}" if instance_fqdn.nil?
      organization,instance_domain=instance_fqdn.split('.',2)
      Log.log.debug("instance_domain=#{instance_domain}")
      Log.log.debug("organization=#{organization}")
      raise "expecting a public FQDN for #{PRODUCT_NAME}" if instance_domain.nil?
      return organization,instance_domain
    end

    # get necessary fixed information to create JWT or call API
    # instance domain is: ibmaspera.com, asperafiles.com or qa.asperafiles.com, etc...
    def self.base_rest_params(aoc_org_url)
      organization,instance_domain=parse_url(aoc_org_url)
      base_url='https://api.'+instance_domain+'/api/v1'
      return {
        :base_url           => base_url,
        :auth_type          => :oauth2,
        :oauth_base_url     => "#{base_url}/oauth2/#{organization}",
        :oauth_path_login   => 'authorize',
        :oauth_path_token   => 'token',
        :oauth_jwt_audience => 'https://api.asperafiles.com/api/v1/oauth2/token'
      }
    end

    # node API scopes
    def self.node_scope(access_key,scope)
      return 'node.'+access_key+':'+scope
    end

  end # FilesApi
end # Asperalm
