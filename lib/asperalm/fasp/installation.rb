require 'singleton'
require 'asperalm/log'
require 'asperalm/open_application' # current_os_type

require 'xmlsimple'
require 'zlib'
require 'base64'

module Asperalm
  module Fasp
    # Singleton that tells where to find ascp and other local resources (keys..) , using the "path(symb)" method.
    # It is used by object : Fasp::Local to find necessary resources
    # By default it takes the first Aspera product found specified in product_locations
    # but the user can specify ascp location by calling:
    # Installation.instance.use_ascp_from_product(product_name)
    # or
    # Installation.instance.ascp_path=ascp_path
    class Installation
      include Singleton
      # currently used ascp executable
      attr_accessor :ascp_path
      # where key files are generated and used
      attr_accessor :config_folder
      # find ascp in named product (use value : FIRST_FOUND='FIRST' to just use first one)
      # or select one from installed_products()
      def use_ascp_from_product(product_name)
        if product_name.eql?(FIRST_FOUND)
          p=installed_products.first
          raise "no FASP installation found\nPlease check manual on how to install FASP." if p.nil?
        else
          p=installed_products.select{|i|i[:name].eql?(product_name)}.first
          raise "no such product installed: #{product_name}" if p.nil?
        end
        sub_bin = p[:sub_bin] || BIN_SUBFOLDER
        exec_ext = OpenApplication.current_os_type.eql?(:windows) ? '.exe' : ''
        @ascp_path=File.join(p[:app_root],sub_bin,'ascp')+exec_ext
        Log.log.debug("ascp_path=#{@ascp_path}")
      end

      # @return the list of installed products in format of product_locations
      def installed_products
        if @found_products.nil?
          @found_products=product_locations.select do |l|
            next false unless Dir.exist?(l[:app_root])
            Log.log.debug("found #{l[:app_root]}")
            product_info_file="#{l[:app_root]}/#{PRODUCT_INFO}"
            if File.exist?(product_info_file)
              res_s=XmlSimple.xml_in(File.read(product_info_file),{"ForceArray"=>false})
              l[:name]=res_s['name']
              l[:version]=res_s['version']
            else
              l[:name]=l[:expected]
            end
            true # select this version
          end
        end
        return @found_products
      end

      # get path of one resource file of currently activated product
      # keys and certs are generated locally... (they are well known values, arch. independant)
      def path(k)
        case k
        when :ascp,:ascp4
          use_ascp_from_product(FIRST_FOUND) if @ascp_path.nil?
          file=@ascp_path
          # note that there might be a .exe at the end
          file=file.gsub('ascp','ascp4') if k.eql?(:ascp4)
        when :ssh_bypass_key_dsa
          file=File.join(@config_folder,'aspera_bypass_dsa.pem')
          File.write(file,Zlib::Inflate.inflate(Base64.decode64(SSH_BYPASS_DSA))) unless File.exist?(file)
          File.chmod(0400,file)
        when :ssh_bypass_key_rsa
          file=File.join(@config_folder,'aspera_bypass_rsa.pem')
          File.write(file,Zlib::Inflate.inflate(Base64.decode64(SSH_BYPASS_RSA))) unless File.exist?(file)
          File.chmod(0400,file)
        when :fallback_cert,:fallback_key
          file_key=File.join(@config_folder,'aspera_fallback_key.pem')
          file_cert=File.join(@config_folder,'aspera_fallback_cert.pem')
          if !File.exist?(file_key) or !File.exist?(file_cert)
            require 'openssl'
            # create new self signed certificate forhttp fallback
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
      def connect_uri_file
        connect=get_product_folders('Aspera Connect')
        return File.join(connect[:run_root],VARRUN_SUBFOLDER,'https.uri')
      end

      # @ return path to configuration file of aspera CLI
      def cli_conf_file
        connect=get_product_folders('Aspera CLI')
        return File.join(connect[:app_root],BIN_SUBFOLDER,'.aspera_cli_conf')
      end

      # add Aspera private keys for web access, token based authorization
      def add_bypass_keys(transfer_spec)
        transfer_spec['EX_ssh_key_paths'] = [ Installation.instance.path(:ssh_bypass_key_dsa), Installation.instance.path(:ssh_bypass_key_rsa) ]
        transfer_spec['drowssap_etomer'.reverse] = "%08x-%04x-%04x-%04x-%04x%08x" % "t1(\xBF;\xF3E\xB5\xAB\x14F\x02\xC6\x7F)P".unpack("NnnnnN")
      end

      # DEPRECATED ZONE

      def activated;Log.log.warn("deprecated, use ascp_path accessor");nil;end

      def activated=(product_name);Log.log.warn("deprecated, use method use_ascp_from_product");use_ascp_from_product(product_name);end

      def paths;Log.log.warn("deprecated, no replacement");raise "deprecated";end

      def paths=(res_paths)
        raise "must be a hash" unless res_paths.is_a?(Hash)
        raise "must have :ascp key" unless res_paths.has_key?(:ascp)
        Log.log.warn("deprecated, use method: ascp_path=")
        @ascp_path=res_paths[:ascp]
      end

      private

      BIN_SUBFOLDER='bin'
      ETC_SUBFOLDER='etc'
      VARRUN_SUBFOLDER=File.join('var','run')
      # policy for product selection
      FIRST_FOUND='FIRST'
      # product information manifest: XML (part of aspera product)
      PRODUCT_INFO='product-info.mf'

      private_constant :BIN_SUBFOLDER,:ETC_SUBFOLDER,:VARRUN_SUBFOLDER,:PRODUCT_INFO

      # get some specific folder from specific applications: Connect or CLI
      def get_product_folders(name)
        found=installed_products.select{|i|i[:expected].eql?(name) or i[:name].eql?(name)}
        raise "Product: #{name} not found, please install." if found.empty?
        return found.first
      end

      def initialize
        @ascp_path=nil
        @config_folder='.'
        @found_products=nil
      end

      # returns product folders depending on OS
      # fields
      # :expected  M app name is taken from the manifest if present, else defaults to this value
      # :app_root  M main forlder for the application
      # :log_root  O location of log files (Linux uses syslog)
      # :run_root  O only for Connect Client, location of http port file
      # :sub_bin   O subfolder with executables, default : bin
      def product_locations
        case OpenApplication.current_os_type
        when :windows; return [{
            :expected =>'Aspera Connect',
            :app_root =>File.join(ENV['LOCALAPPDATA'],'Programs','Aspera','Aspera Connect'),
            :log_root =>File.join(ENV['LOCALAPPDATA'],'Aspera','Aspera Connect','var','log'),
            :run_root =>File.join(ENV['LOCALAPPDATA'],'Aspera','Aspera Connect')
            },{
            :expected =>'Aspera CLI',
            :app_root =>File.join('C:','Program Files','Aspera','cli'),
            :log_root =>File.join('C:','Program Files','Aspera','cli','var','log'),
            },{
            :expected =>'Enterprise Server',
            :app_root =>File.join('C:','Program Files','Aspera','Enterprise Server'),
            :log_root =>File.join('C:','Program Files','Aspera','Enterprise Server','var','log'),
            }]
        when :mac; return [{
            :expected =>'Aspera Connect',
            :app_root =>File.join(Dir.home,'Applications','Aspera Connect.app'),
            :log_root =>File.join(Dir.home,'Library','Logs','Aspera_Connect'),
            :run_root =>File.join(Dir.home,'Library','Application Support','Aspera','Aspera Connect'),
            :sub_bin  =>File.join('Contents','Resources'),
            },{
            :expected =>'Aspera CLI',
            :app_root =>File.join(Dir.home,'Applications','Aspera CLI'),
            :log_root =>File.join(Dir.home,'Library','Logs','Aspera')
            },{
            :expected =>'Enterprise Server',
            :app_root =>File.join('','Library','Aspera'),
            :log_root =>File.join(Dir.home,'Library','Logs','Aspera'),
            },{
            :expected =>'Aspera Drive',
            :app_root =>File.join('','Applications','Aspera Drive.app'),
            :log_root =>File.join(Dir.home,'Library','Logs','Aspera_Drive'),
            :sub_bin  =>File.join('Contents','Resources'),
            }]
        else; return [{  # other: Linux and unix family
            :expected =>'Aspera Connect',
            :app_root =>File.join(Dir.home,'.aspera','connect'),
            :run_root =>File.join(Dir.home,'.aspera','connect')
            },{
            :expected =>'Aspera CLI',
            :app_root =>File.join(Dir.home,'.aspera','cli'),
            },{
            :expected =>'Enterprise Server',
            :app_root =>File.join('','opt','aspera'),
            }]
        end
      end

      # not pass protected
      SSH_BYPASS_DSA='eJxtksuSojAAAO98xdypKYFggGOA8HQ0ICBywwiooARRIH79zu55+9qnrurv719M7PrbL3uPvkjsZyjBXyE+/hXfwo/vm+/ZNxEKzSay2zDybHhXub80t7HikDy4Ckta5DgeA4+vVbYyh9znxzbboRYzIWymBAxJsr3z9nCY1X7aEVm0rzJdKQ470q6jCbu0B7rXO6TdJFm5p7iieTnlN0JcSbiC13p6mfqy4QC0EaiMyVht5ou00Lh+l9J5ndbO3DPTR/kUoCcw4bNkoy5GvymbeRR4NYwLwH1nlVaWB7UIZVoFjKHeRaQnL0xU/vFcJX/Rxarz8qS+jQ+GM/moFQlekpAmD1Cn0yO6B4l2lcLMip+gUTxlV/wcHFnh0i0d9Mh8F8rYA8urKu0gZ3d0Pm01Z6GiQHlmPDD8pPGASsJfygmLz+ZHZgRuovS4NDZYwvMkF67Y2r6Na5iC/nGj4emOIG0XIYFuOfXIao4Y9aeS2dOaKXXvidRdh5I2+o5tPKXY1t5h8OiG2xHlH4fqqQbnPGzeUDjkb6aUVLJ6MX4UTPPG0nBFLF4DyHrfYLtY0vPkTDqucjvdbPeJSuaufp72TmI42UX4tIea7SaUUr1uI3QphmlFMMwuTqTPEih0lw35op3AdjJjEdf+AqAe9paDed1JkyckpdbAuzv7P/nznESRXhej8O8xvLX//94fHTzUbwo='
      # pass protected (but not fips compliant)
      SSH_BYPASS_RSA='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'
    end # Installation
  end
end
