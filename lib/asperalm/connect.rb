module Asperalm
  # locate Connect client resources based on OS
  class Connect
    @@res=nil
    def self.res
      if @@res.nil?
        @@res=locate_resources
      end
      return @@res
    end

    # locate connect plugin resources
    def self.locate_resources
      connect_resources={}
      folder_bin='bin'
      folder_etc='etc'
      # detect Connect Client on all platforms
      case RbConfig::CONFIG['host_os']
      when /darwin|mac os/
        pluginLocation = File.join(Dir.home,'Applications','Aspera Connect.app')
        folder_bin=File.join('Contents','Resources')
        folder_etc=File.join('Contents','Resources')
        var_run_location = File.join(Dir.home,'Library','Application Support','Aspera','Aspera Connect','var','run')
      when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
        # also: ENV{TEMP}/.. , or %USERPROFILE%\AppData\Local\
        pluginLocation = File.join(ENV['LOCALAPPDATA'],'Programs','Aspera','Aspera Connect')
      else  # unix family
        pluginLocation = File.join(Dir.home,'.aspera','connect')
      end
      connect_resources[:ascp] = File.join(pluginLocation,folder_bin,'ascp')
      connect_resources[:ssh_bypass_key_dsa] = File.join(pluginLocation,folder_etc,'asperaweb_id_dsa.openssh')
      connect_resources[:ssh_bypass_key_rsa] = File.join(pluginLocation,folder_etc,'aspera_tokenauth_id_rsa')
      connect_resources[:fallback_cert] = File.join(pluginLocation,folder_etc,'aspera_web_cert.pem')
      connect_resources[:fallback_key] = File.join(pluginLocation,folder_etc,'aspera_web_key.pem')
      connect_resources[:localhost_cert] = File.join(pluginLocation,folder_etc,'localhost.crt')
      connect_resources[:localhost_key] = File.join(pluginLocation,folder_etc,'localhost.key')
      connect_resources[:plugin_https_port_file] = File.join(var_run_location,'https.uri')
      Log.log.debug "resources=#{connect_resources}"
      connect_resources.keys.each do |res|
        raise StandardError,"Cannot locate resource for #{res.to_s}: [#{connect_resources[res]}]" if ! File.exist?(connect_resources[res] )
      end
      return  connect_resources
    end
  end
end
