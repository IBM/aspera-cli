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

    def self.path(k)
      return res[k][:path]
    end

    # locate connect plugin resources
    def self.locate_resources
      res={}
      folder_bin='bin'
      folder_etc='etc'
      # this contains var/run, files generated on runtime
      folder_varrun=File.join('var','run')
      ascp_bin_file='ascp'
      # detect Connect Client on all platforms
      case RbConfig::CONFIG['host_os']
      when /darwin|mac os/
        connect_install_dir = File.join(Dir.home,'Applications','Aspera Connect.app')
        connect_run_dir=File.join(Dir.home,'Library','Application Support','Aspera','Aspera Connect')
        folder_bin=File.join('Contents','Resources')
        folder_etc=folder_bin
      when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
        # also: ENV{TEMP}/.. , or %USERPROFILE%\AppData\Local\
        connect_install_dir = File.join(ENV['LOCALAPPDATA'],'Programs','Aspera','Aspera Connect')
        connect_run_dir = File.join(ENV['LOCALAPPDATA'],'Aspera','Aspera Connect')
        ascp_bin_file='ascp.exe'
      else  # unix family
        connect_install_dir = File.join(Dir.home,'.aspera','connect')
        connect_run_dir = connect_install_dir # TODO: check
      end
      res[:ascp] = { :path =>File.join(connect_install_dir,folder_bin,ascp_bin_file), :type => :file, :required => true}
      res[:ssh_bypass_key_dsa] = { :path =>File.join(connect_install_dir,folder_etc,'asperaweb_id_dsa.openssh'), :type => :file, :required => true}
      res[:ssh_bypass_key_rsa] = { :path =>File.join(connect_install_dir,folder_etc,'aspera_tokenauth_id_rsa'), :type => :file, :required => true}
      res[:fallback_cert] = { :path =>File.join(connect_install_dir,folder_etc,'aspera_web_cert.pem'), :type => :file, :required => true}
      res[:fallback_key] = { :path =>File.join(connect_install_dir,folder_etc,'aspera_web_key.pem'), :type => :file, :required => true}
      res[:localhost_cert] = { :path =>File.join(connect_install_dir,folder_etc,'localhost.crt'), :type => :file, :required => true}
      res[:localhost_key] = { :path =>File.join(connect_install_dir,folder_etc,'localhost.key'), :type => :file, :required => true}
      res[:plugin_https_port_file] = { :path =>File.join(connect_run_dir,folder_varrun,'https.uri'), :type => :file, :required => false}
      Log.log.debug "resources=#{res}"
      notfound=[]
      res.each_pair do |k,v|
        notfound.push(k) if v[:type].eql?(:file) and v[:required] and ! File.exist?(v[:path])
      end
      if !notfound.empty?
        reslist=notfound.map { |k| "#{k.to_s}: #{res[k][:path]}"}.join("\n")
        raise StandardError.new("Please check your connect client installation, Cannot locate resource(s):\n#{reslist}")
      end
      return res
    end
  end
end
