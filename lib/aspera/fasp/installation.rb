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
    # It is used by object : Fasp::Local to find necessary resources
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
      # currently used ascp executable
      def ascp_path=(v)
        @path_to_ascp=v
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
          @found_products=product_locations
          # add sdk as first search path
          @found_products.unshift({# SDK
            :expected =>'SDK',
            :app_root =>folder_path,
            :sub_bin =>''
          })
          @found_products.select! do |pl|
            next false unless Dir.exist?(pl[:app_root])
            Log.log.debug("found #{pl[:app_root]}")
            sub_bin = pl[:sub_bin] || BIN_SUBFOLDER
            pl[:ascp_path]=File.join(pl[:app_root],sub_bin,'ascp'+Environment.exe_extension)
            next false unless File.exist?(pl[:ascp_path])
            product_info_file="#{pl[:app_root]}/#{PRODUCT_INFO}"
            if File.exist?(product_info_file)
              res_s=XmlSimple.xml_in(File.read(product_info_file),{"ForceArray"=>false})
              pl[:name]=res_s['name']
              pl[:version]=res_s['version']
            else
              pl[:name]=pl[:expected]
            end
            true # select this version
          end
        end
        return @found_products
      end

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
        <storage_rc>
            <adaptive>
                true
            </adaptive>
        </storage_rc>
        <resume_suffix>.aspera-ckpt</resume_suffix>
        <partial_file_suffix>.partial</partial_file_suffix>
        <replace_illegal_chars>_</replace_illegal_chars>
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

      # @returns the file path of local connect where API's URI can be read
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

      def install_sdk(sdk_url)
        require 'zip'
        sdk_zip_path=File.join(Dir.tmpdir,'sdk.zip')
        if sdk_url.start_with?('file:')
          # require specific file scheme: the path part is "relative", or absolute if there are 4 slash
          raise 'use format: file:///<path>' unless sdk_url.start_with?('file:///')
          sdk_zip_path=sdk_url.gsub(%r{^file:///},'')
        else
          Aspera::Rest.new(base_url: sdk_url).call(operation: 'GET',save_to_file: sdk_zip_path)
        end
        filter="/#{Environment.architecture}/"
        ascp_path=nil
        # first ensure license file is here so that ascp invokation for version works
        self.path(:aspera_license)
        self.path(:aspera_conf)
        Zip::File.open(sdk_zip_path) do |zip_file|
          zip_file.each do |entry|
            if entry.name.include?(filter) and !entry.name.end_with?('/')
              archive_file=File.join(folder_path,File.basename(entry.name))
              File.open(archive_file, 'wb') do |output_stream|
                IO.copy_stream(entry.get_input_stream, output_stream)
              end
              if entry.name.include?('ascp')
                FileUtils.chmod(0755,archive_file)
                ascp_path=archive_file
              end
            end
          end
        end
        File.unlink(sdk_zip_path) rescue nil # Windows may give error
        ascp_version='n/a'
        raise "error in sdk: no ascp included" if ascp_path.nil?
        cmd_out=%x{#{ascp_path} -A}
        raise "An error occured when testing ascp: #{cmd_out}" unless $? == 0
        # get version from ascp, only after full extract, as windows requires DLLs (SSL/TLS/etc...)
        m=cmd_out.match(/ascp version (.*)/)
        ascp_version=m[1] unless m.nil?
        File.write(File.join(folder_path,PRODUCT_INFO),"<product><name>IBM Aspera SDK</name><version>#{ascp_version}</version></product>")
        return ascp_version
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

      # get some specific folder from specific applications: Connect or CLI
      def get_product_folders(name)
        found=installed_products.select{|i|i[:expected].eql?(name) or i[:name].eql?(name)}
        raise "Product: #{name} not found, please install." if found.empty?
        return found.first
      end

      def initialize
        @path_to_ascp=nil
        @sdk_folder=nil
        @found_products=nil
      end

      def folder_path
        raise "undefined path to SDK" if @sdk_folder.nil?
        FileUtils.mkdir_p(@sdk_folder) unless Dir.exist?(@sdk_folder)
        @sdk_folder
      end

      # returns product folders depending on OS
      # fields
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
        else; return [{  # other: Linux and unix family
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

      def get_key(type,id)
        hf=['begin','end'].map{|t|"-----#{t} #{type} private key-----".upcase}
        bin=Base64.strict_encode64(DataRepository.instance.get_bin(id))
        hf.insert(1,bin).join("\n")
      end

    end # Installation
  end
end
