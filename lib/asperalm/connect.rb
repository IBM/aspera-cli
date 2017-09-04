require 'asperalm/log'
require 'asperalm/operating_system'

module Asperalm
  # locate Connect client resources based on OS
  class Connect
    @@res=nil
    def self.resource
      if @@res.nil?
        @@res=locate_resources
      end
      return @@res
    end

    def self.path(k)
      file=resource[k][:path]
      raise "no such file: #{file}" if !File.exist?(file)
      return file
    end
    @@fasp_install_paths=nil

    def self.fasp_install_paths=(path)
      raise "must be a hash" if !path.is_a?(Hash)
      @@fasp_install_paths=path
    end

    # try to find connect client or other Aspera product installed.
    def self.fasp_install_paths
      if @@fasp_install_paths.nil?
        common_places=[]
        case OperatingSystem.current_os_type
        when :mac
          common_places.push({
            :ascp=>'ascp',
            :app_root=>File.join(Dir.home,'Applications','Aspera Connect.app'),
            :run_root=>File.join(Dir.home,'Library','Application Support','Aspera','Aspera Connect'),
            :log_root=>File.join(Dir.home,'Library','Logs','Aspera'),
            :sub_bin=>File.join('Contents','Resources'),
            :sub_keys=>File.join('Contents','Resources'),
            :dsa=>'asperaweb_id_dsa.openssh'})
        when :windows
          common_places.push({
            :ascp=>'ascp.exe',
            :app_root=>File.join(ENV['LOCALAPPDATA'],'Programs','Aspera','Aspera Connect'),
            :run_root=>File.join(ENV['LOCALAPPDATA'],'Aspera','Aspera Connect'),
            :sub_bin=>'bin',
            :sub_keys=>'etc',
            :dsa=>'asperaweb_id_dsa.openssh'})
        else  # unix family
          common_places.push({
            :ascp=>'ascp',
            :app_root=>File.join(Dir.home,'.aspera','connect'),
            :run_root=>File.join(Dir.home,'.aspera','connect'),
            :sub_bin=>'bin',
            :sub_keys=>'etc',
            :dsa=>'asperaweb_id_dsa.openssh'})
          common_places.push({
            :ascp=>'ascp',
            :app_root=>'/opt/aspera',
            :run_root=>'/opt/aspera',
            :sub_bin=>'bin',
            :sub_keys=>'var',
            :dsa=>'aspera_tokenauth_id_dsa'})
        end
        common_places.each do |one_place|
          if Dir.exist?(one_place[:app_root])
            Log.log.debug("found: #{one_place[:app_root]}")
            @@fasp_install_paths=one_place
            return @@fasp_install_paths
          end
        end
        raise "no FASP installation found"
      end
      return @@fasp_install_paths
    end

    # locate connect plugin resources
    def self.locate_resources
      # this contains var/run, files generated on runtime
      sub_varrun='var/run'
      p = fasp_install_paths
      res={}
      res[:ascp] = { :path =>File.join(p[:app_root],p[:sub_bin],p[:ascp]), :type => :file, :required => true}
      res[:ssh_bypass_key_dsa] = { :path =>File.join(p[:app_root],p[:sub_keys],p[:dsa]), :type => :file, :required => true}
      res[:ssh_bypass_key_rsa] = { :path =>File.join(p[:app_root],p[:sub_keys],'aspera_tokenauth_id_rsa'), :type => :file, :required => true}
      res[:fallback_cert] = { :path =>File.join(p[:app_root],p[:sub_keys],'aspera_web_cert.pem'), :type => :file, :required => false}
      res[:fallback_key] = { :path =>File.join(p[:app_root],p[:sub_keys],'aspera_web_key.pem'), :type => :file, :required => false}
      res[:localhost_cert] = { :path =>File.join(p[:app_root],p[:sub_keys],'localhost.crt'), :type => :file, :required => false}
      res[:localhost_key] = { :path =>File.join(p[:app_root],p[:sub_keys],'localhost.key'), :type => :file, :required => false}
      res[:plugin_https_port_file] = { :path =>File.join(p[:run_root],sub_varrun,'https.uri'), :type => :file, :required => false}
      res[:log_folder] = { :path =>p[:log_root], :type => :folder, :required => false}
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
