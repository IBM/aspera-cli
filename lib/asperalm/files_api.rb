require 'asperalm/log'

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

    # strings AsperaDrive|grep -E '.{100}==$'|base64 --decode|rev
    RANDOM='1FwelGbL9xsv3M8H-VXPs5k69OdbaMgfB66qfBqlELFPk6r9ANztmGMOSLqaXEWXEPwk-6JnMZ7-RaXAYLd5thLbcL3QzgeU:evird.arepsa';
    def self.random
      RANDOM.reverse.split(':')
    end

    # get necessary fixed information to create JWT or call API
    # instance domain is asperafiles.com or qa.asperafiles.com
    def self.set_rest_params(aoc_org_url,rest_params)
      uri=URI.parse(aoc_org_url.gsub(/\/+$/,''))
      instance_fqdn=uri.host
      raise "No host found in URL.Please check URL format: https://myorg.ibmaspera.com" if instance_fqdn.nil?
      organization,instance_domain=instance_fqdn.split('.',2)
      raise "expecting a public FQDN for Files" if instance_domain.nil?
      Log.log.debug("instance_fqdn=#{instance_fqdn}")
      Log.log.debug("instance_domain=#{instance_domain}")
      Log.log.debug("organization=#{organization}")
      rest_params[:base_url] = 'https://api.'+instance_domain+'/api/v1'
      rest_params[:oauth_base_url] = rest_params[:base_url]+"/oauth2/#{organization}"
      rest_params[:oauth_jwt_audience] = 'https://api.asperafiles.com/api/v1/oauth2/token'
      rest_params[:oauth_path_authorize] = "authorize"
      rest_params[:oauth_path_token] = "token"
      return nil
    end

    # node API scopes
    def self.node_scope(access_key,scope)
      return 'node.'+access_key+':'+scope
    end

  end # FilesApi
end # Asperalm
