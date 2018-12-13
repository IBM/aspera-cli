require 'asperalm/log'
require 'asperalm/rest'

module Asperalm
  class AtsApi < Rest
    # currently supported clouds
    # Note to Aspera: shall be an API call
    @@CLOUD_NAME={
      :aws =>'Amazon Web Services',
      :azure =>'Microsoft Azure',
      :google =>'Google Cloud',
      :limelight =>'Limelight',
      :rackspace =>'Rackspace',
      :softlayer =>'IBM Cloud'
    }
    
    def self.base_url;'https://ats.aspera.io';end

    def initialize
      super({:base_url=>AtsApi.base_url+'/pub/v1'})
      # cache of server data
      @all_servers_cache=nil
    end
    
    def cloud_names;@@CLOUD_NAME;end

    # all available ATS servers
    # NOTE to Aspera: an API shall be created to retrieve all servers at once
    def all_servers
      if @all_servers_cache.nil?
        @all_servers_cache=[]
        @@CLOUD_NAME.keys.each do |name|
          read("servers/#{name.to_s.upcase}")[:data].each do |i|
            @all_servers_cache.push(i)
          end
        end
      end
      return @all_servers_cache
    end
  end # AtsApi
end # Asperalm
