module Asperalm
  class FilesApi
    # get API base URL based on instance domain
    # instance domain is asperafiles.com or qa.asperafiles.com
    def self.baseurl(instance_domain)
      return 'https://api.'+instance_domain+'/api/v1'
    end

    # node API scopes
    def self.node_scope(access_key,scope)
      return 'node.'+access_key+':'+scope
    end

    # various API scopes supported
    SCOPE_FILES_SELF='self'
    SCOPE_FILES_USER='user:all'
    SCOPE_FILES_ADMIN='admin:all'
    SCOPE_NODE_USER='user:all'
    SCOPE_NODE_ADMIN='admin:all'

  end # FilesApi
end # Asperalm
