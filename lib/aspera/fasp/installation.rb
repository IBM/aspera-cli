require 'singleton'
require 'aspera/log'
require 'aspera/environment'
require 'aspera/data_repository'
require 'xmlsimple'
require 'zlib'
require 'base64'
require 'fileutils'

module Aspera
  module Fasp
    # Singleton that tells where to find ascp and other local resources (keys..) , using the "path(symb)" method.
    # It is used by object : AgentDirect to find necessary resources
    # By default it takes the first Aspera product found specified in product_locations
    # but the user can specify ascp location by calling:
    # Installation.instance.use_ascp_from_product(product_name)
    # or
    # Installation.instance.ascp_path=""
    class Installation
      include Singleton
      PRODUCT_CONNECT='Aspera Connect'
      PRODUCT_CLI_V1='Aspera CLI'
      PRODUCT_DRIVE='Aspera Drive'
      PRODUCT_ENTSRV='Enterprise Server'
      # protobuf generated files from sdk
      EXT_RUBY_PROTOBUF='_pb.rb'
      RB_SDK_FOLDER='lib'
      MAX_REDIRECT_SDK=2
      private_constant :MAX_REDIRECT_SDK
      # set ascp executable path
      def ascp_path=(v)
        @path_to_ascp=v
      end

      def sdk_ruby_folder
        ruby_pb_folder=File.join(folder_path,RB_SDK_FOLDER)
        FileUtils.mkdir_p(ruby_pb_folder) unless Dir.exist?(ruby_pb_folder)
        return ruby_pb_folder
      end

      # location of SDK files
      def folder=(v)
        @sdk_folder=v
        folder_path
      end

      # find ascp in named product (use value : FIRST_FOUND='FIRST' to just use first one)
      # or select one from installed_products()
      def use_ascp_from_product(product_name)
        if product_name.eql?(FIRST_FOUND)
          pl=installed_products.first
          raise "no FASP installation found\nPlease check manual on how to install FASP." if pl.nil?
        else
          pl=installed_products.select{|i|i[:name].eql?(product_name)}.first
          raise "no such product installed: #{product_name}" if pl.nil?
        end
        self.ascp_path=pl[:ascp_path]
        Log.log.debug("ascp_path=#{@path_to_ascp}")
      end

      # @return the list of installed products in format of product_locations
      def installed_products
        if @found_products.nil?
          scan_locations=product_locations.clone
          # add SDK as first search path
          scan_locations.unshift({
            :expected =>'SDK',
            :app_root =>folder_path,
            :sub_bin =>''
          })
          # search installed products: with ascp
          @found_products=scan_locations.select! do |item|
            # skip if not main folder
            next false unless Dir.exist?(item[:app_root])
            Log.log.debug("Found #{item[:app_root]}")
            sub_bin = item[:sub_bin] || BIN_SUBFOLDER
            item[:ascp_path]=File.join(item[:app_root],sub_bin,ascp_filename)
            # skip if no ascp
            next false unless File.exist?(item[:ascp_path])
            # read info from product info file if present
            product_info_file="#{item[:app_root]}/#{PRODUCT_INFO}"
            if File.exist?(product_info_file)
              res_s=XmlSimple.xml_in(File.read(product_info_file),{'ForceArray'=>false})
              item[:name]=res_s['name']
              item[:version]=res_s['version']
            else
              item[:name]=item[:expected]
            end
            true # select this version
          end
        end
        return @found_products
      end

      # all ascp files (in SDK)
      FILES=[:ascp,:ascp4,:ssh_bypass_key_dsa,:ssh_bypass_key_rsa,:aspera_license,:aspera_conf,:fallback_cert,:fallback_key]

      # get path of one resource file of currently activated product
      # keys and certs are generated locally... (they are well known values, arch. independant)
      def path(k)
        case k
        when :ascp,:ascp4
          use_ascp_from_product(FIRST_FOUND) if @path_to_ascp.nil?
          file=@path_to_ascp
          # note that there might be a .exe at the end
          file=file.gsub('ascp','ascp4') if k.eql?(:ascp4)
        when :transferd
          file=transferd_filepath
        when :ssh_bypass_key_dsa
          file=File.join(folder_path,'aspera_bypass_dsa.pem')
          File.write(file,get_key('dsa',1)) unless File.exist?(file)
          File.chmod(0400,file)
        when :ssh_bypass_key_rsa
          file=File.join(folder_path,'aspera_bypass_rsa.pem')
          File.write(file,get_key('rsa',2)) unless File.exist?(file)
          File.chmod(0400,file)
        when :aspera_license
          file=File.join(folder_path,'aspera-license')
          File.write(file,Base64.strict_encode64("#{Zlib::Inflate.inflate(DataRepository.instance.get_bin(6))}==SIGNATURE==\n#{Base64.strict_encode64(DataRepository.instance.get_bin(7))}")) unless File.exist?(file)
          File.chmod(0400,file)
        when :aspera_conf
          file=File.join(folder_path,'aspera.conf')
          File.write(file,%Q{<?xml version='1.0' encoding='UTF-8'?>
<CONF version="2">
<default>
    <file_system>
        <resume_suffix>.aspera-ckpt</resume_suffix>
        <partial_file_suffix>.partial</partial_file_suffix>
    </file_system>
</default>
</CONF>
}) unless File.exist?(file)
          File.chmod(0400,file)
        when :fallback_cert,:fallback_key
          file_key=File.join(folder_path,'aspera_fallback_key.pem')
          file_cert=File.join(folder_path,'aspera_fallback_cert.pem')
          if !File.exist?(file_key) or !File.exist?(file_cert)
            require 'openssl'
            # create new self signed certificate for http fallback
            private_key = OpenSSL::PKey::RSA.new(1024)
            cert = OpenSSL::X509::Certificate.new
            cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/C=US/ST=California/L=Emeryville/O=Aspera Inc./OU=Corporate/CN=Aspera Inc./emailAddress=info@asperasoft.com")
            cert.not_before = Time.now
            cert.not_after = Time.now + 365 * 24 * 60 * 60
            cert.public_key = private_key.public_key
            cert.serial = 0x0
            cert.version = 2
            cert.sign(private_key, OpenSSL::Digest::SHA1.new)
            File.write(file_key,private_key.to_pem)
            File.write(file_cert,cert.to_pem)
            File.chmod(0400,file_key)
            File.chmod(0400,file_cert)
          end
          file = k.eql?(:fallback_cert) ? file_cert : file_key
        else
          raise "INTERNAL ERROR: #{k}"
        end
        raise "no such file: #{file}" unless File.exist?(file)
        return file
      end

      # @return the file path of local connect where API's URI can be read
      def connect_uri
        connect=get_product_folders(PRODUCT_CONNECT)
        folder=File.join(connect[:run_root],VARRUN_SUBFOLDER)
        ['','s'].each do |ext|
          uri_file=File.join(folder,"http#{ext}.uri")
          Log.log.debug("checking connect port file: #{uri_file}")
          if File.exist?(uri_file)
            return File.open(uri_file){|f|f.gets}.strip
          end
        end
        raise "no connect uri file found in #{folder}"
      end

      # @ return path to configuration file of aspera CLI
      def cli_conf_file
        connect=get_product_folders(PRODUCT_CLI_V1)
        return File.join(connect[:app_root],BIN_SUBFOLDER,'.aspera_cli_conf')
      end

      # default bypass key phrase
      def bypass_pass
        return "%08x-%04x-%04x-%04x-%04x%08x" % DataRepository.instance.get_bin(3).unpack("NnnnnN")
      end

      def bypass_keys
        return [:ssh_bypass_key_dsa,:ssh_bypass_key_rsa].map{|i|Installation.instance.path(i)}
      end

      # use in plugin `config`
      def get_ascp_version(exe_path)
        return get_exe_version(exe_path,'-A')
      end

      # Check that specified path is ascp and get version
      def get_exe_version(exe_path,vers_arg)
        raise "ERROR: nil arg" if exe_path.nil?
        return nil unless File.exist?(exe_path)
        exe_version=nil
        cmd_out=%x{"#{exe_path}" #{vers_arg}}
        raise "An error occured when testing #{ascp_filename}: #{cmd_out}" unless $? == 0
        # get version from ascp, only after full extract, as windows requires DLLs (SSL/TLS/etc...)
        m=cmd_out.match(/ version ([0-9\.]+)/)
        exe_version=m[1] unless m.nil?
        return exe_version
      end

      # download aspera SDK or use local file
      # extracts ascp binary for current system architecture
      # @return ascp version (from execution)
      def install_sdk(sdk_url)
        require 'zip'
        sdk_zip_path=File.join(Dir.tmpdir,'sdk.zip')
        if sdk_url.start_with?('file:')
          # require specific file scheme: the path part is "relative", or absolute if there are 4 slash
          raise 'use format: file:///<path>' unless sdk_url.start_with?('file:///')
          sdk_zip_path=sdk_url.gsub(%r{^file:///},'')
        else
          redirect_remain=MAX_REDIRECT_SDK
          begin
            Aspera::Rest.new(base_url: sdk_url).call(operation: 'GET',save_to_file: sdk_zip_path)
          rescue Aspera::RestCallError => e
            if e.response.is_a?(Net::HTTPRedirection)
              if redirect_remain > 0
                redirect_remain-=1
                sdk_url=e.response['location']
                retry
              else
                raise "Too many redirect"
              end
            else
              raise e
            end
          end
        end
        # rename old install
        if ! Dir.empty?(folder_path)
          Log.log.warn("Previous install exists, renaming folder.")
          File.rename(folder_path,"#{folder_path}.#{Time.now.strftime("%Y%m%d%H%M%S")}")
          # TODO: delete old archives ?
        end
        # SDK is organized by architecture
        arch_filter="#{Environment.architecture}/"
        # extract files from archive
        Zip::File.open(sdk_zip_path) do |zip_file|
          zip_file.each do |entry|
            # skip folder entries
            next if entry.name.end_with?('/')
            dest_folder=nil
            # binaries
            dest_folder=folder_path if entry.name.include?(arch_filter)
            # ruby adapters
            dest_folder=sdk_ruby_folder if entry.name.end_with?(EXT_RUBY_PROTOBUF)
            if !dest_folder.nil?
              File.open(File.join(dest_folder,File.basename(entry.name)), 'wb') do |output_stream|
                IO.copy_stream(entry.get_input_stream, output_stream)
              end
            end
          end
        end
        File.unlink(sdk_zip_path) rescue nil # Windows may give error
        # ensure license file are generated so that ascp invokation for version works
        self.path(:aspera_license)
        self.path(:aspera_conf)
        ascp_path=File.join(folder_path,ascp_filename)
        raise "No #{ascp_filename} found in SDK archive" unless File.exist?(ascp_path)
        FileUtils.chmod(0755,ascp_path)
        FileUtils.chmod(0755,ascp_path.gsub('ascp','ascp4'))
        ascp_version=get_ascp_version(File.join(folder_path,ascp_filename))
        trd_path=transferd_filepath
        Log.log.warn("No #{trd_path} in SDK archive") unless File.exist?(trd_path)
        FileUtils.chmod(0755,trd_path) if File.exist?(trd_path)
        transferd_version=get_exe_version(trd_path,'version')
        sdk_version = transferd_version||ascp_version
        File.write(File.join(folder_path,PRODUCT_INFO),"<product><name>IBM Aspera SDK</name><version>#{sdk_version}</version></product>")
        return sdk_version
      end

      private

      BIN_SUBFOLDER='bin'
      ETC_SUBFOLDER='etc'
      VARRUN_SUBFOLDER=File.join('var','run')
      # product information manifest: XML (part of aspera product)
      PRODUCT_INFO='product-info.mf'
      # policy for product selection
      FIRST_FOUND='FIRST'

      private_constant :BIN_SUBFOLDER,:ETC_SUBFOLDER,:VARRUN_SUBFOLDER,:PRODUCT_INFO

      def initialize
        @path_to_ascp=nil
        @sdk_folder=nil
        @found_products=nil
      end

      # @return folder paths for specified applications
      # @param name Connect or CLI
      def get_product_folders(name)
        found=installed_products.select{|i|i[:expected].eql?(name) or i[:name].eql?(name)}
        raise "Product: #{name} not found, please install." if found.empty?
        return found.first
      end

      # @return the path to folder where SDK is installed
      def folder_path
        raise "Undefined path to SDK" if @sdk_folder.nil?
        FileUtils.mkdir_p(@sdk_folder) unless Dir.exist?(@sdk_folder)
        @sdk_folder
      end

      # filename for ascp with optional extension (Windows)
      def ascp_filename
        return 'ascp'+Environment.exe_extension
      end

      def transferd_filepath
        return File.join(folder_path,'asperatransferd'+Environment.exe_extension)
      end

      # @return product folders depending on OS fields
      # :expected  M app name is taken from the manifest if present, else defaults to this value
      # :app_root  M main folder for the application
      # :log_root  O location of log files (Linux uses syslog)
      # :run_root  O only for Connect Client, location of http port file
      # :sub_bin   O subfolder with executables, default : bin
      def product_locations
        case Aspera::Environment.os
        when Aspera::Environment::OS_WINDOWS; return [{
            :expected =>PRODUCT_CONNECT,
            :app_root =>File.join(ENV['LOCALAPPDATA'],'Programs','Aspera','Aspera Connect'),
            :log_root =>File.join(ENV['LOCALAPPDATA'],'Aspera','Aspera Connect','var','log'),
            :run_root =>File.join(ENV['LOCALAPPDATA'],'Aspera','Aspera Connect')
            },{
            :expected =>PRODUCT_CLI_V1,
            :app_root =>File.join('C:','Program Files','Aspera','cli'),
            :log_root =>File.join('C:','Program Files','Aspera','cli','var','log'),
            },{
            :expected =>PRODUCT_ENTSRV,
            :app_root =>File.join('C:','Program Files','Aspera','Enterprise Server'),
            :log_root =>File.join('C:','Program Files','Aspera','Enterprise Server','var','log'),
            }]
        when Aspera::Environment::OS_X; return [{
            :expected =>PRODUCT_CONNECT,
            :app_root =>File.join(Dir.home,'Applications','Aspera Connect.app'),
            :log_root =>File.join(Dir.home,'Library','Logs','Aspera_Connect'),
            :run_root =>File.join(Dir.home,'Library','Application Support','Aspera','Aspera Connect'),
            :sub_bin  =>File.join('Contents','Resources'),
            },{
            :expected =>PRODUCT_CLI_V1,
            :app_root =>File.join(Dir.home,'Applications','Aspera CLI'),
            :log_root =>File.join(Dir.home,'Library','Logs','Aspera')
            },{
            :expected =>PRODUCT_ENTSRV,
            :app_root =>File.join('','Library','Aspera'),
            :log_root =>File.join(Dir.home,'Library','Logs','Aspera'),
            },{
            :expected =>PRODUCT_DRIVE,
            :app_root =>File.join('','Applications','Aspera Drive.app'),
            :log_root =>File.join(Dir.home,'Library','Logs','Aspera_Drive'),
            :sub_bin  =>File.join('Contents','Resources'),
            }]
        else; return [{  # other: Linux and Unix family
            :expected =>PRODUCT_CONNECT,
            :app_root =>File.join(Dir.home,'.aspera','connect'),
            :run_root =>File.join(Dir.home,'.aspera','connect')
            },{
            :expected =>PRODUCT_CLI_V1,
            :app_root =>File.join(Dir.home,'.aspera','cli'),
            },{
            :expected =>PRODUCT_ENTSRV,
            :app_root =>File.join('','opt','aspera'),
            }]
        end
      end

      # @return a standard bypass key
      # @param type rsa or dsa
      # @param id in repository 1 for dsa, 2 for rsa
      def get_key(type,id)
        hf=['begin','end'].map{|t|"-----#{t} #{type} private key-----".upcase}
        bin=Base64.strict_encode64(DataRepository.instance.get_bin(id))
        hf.insert(1,bin).join("\n")
      end

    end # Installation
  end
end
