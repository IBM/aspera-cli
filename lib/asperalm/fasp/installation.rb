require 'singleton'
require 'asperalm/log'
require 'asperalm/open_application' # current_os_type

require 'xmlsimple'

module Asperalm
  module Fasp
    # Singleton that tells where to find ascp and other local resources (binary, keys..)
    # it is used by object : Fasp::Local to find necessary resouces
    # by default it takes the first Aspera product found specified in product_locations
    # but the user can for a product by name by calling: activated=(name)
    # or call paths= and provide a hash with all resources , as specified in get_product_paths
    class Installation
      include Singleton

      # name of Aspera application to be used or :first
      attr_reader :activated
      # set paths by product name
      def activated=(value)
        @activated=value
        # reset installed paths
        @selected_product_paths=nil
      end

      # user can set all path directly, see get_product_paths for format
      def paths=(res_paths)
        raise "must be a hash" unless res_paths.is_a?(Hash)
        # check required files
        missing_mandatory=res_paths.keys.select do |res_sym|
          raise "hash values must be a String (path to resource)" unless res_paths[res_sym].is_a?(String)
          Log.log.debug("#{res_sym}: #{res_paths[res_sym]}")
          @@FASP_SDK[res_sym][:type].eql?(:file) and @@FASP_SDK[res_sym][:required] and ! File.exist?(res_paths[res_sym])
        end
        if !missing_mandatory.empty?
          reslist=missing_mandatory.map{|res_sym|"#{res_sym.to_s}: #{res_paths[res_sym]}"}.join("\n")
          raise StandardError.new("Please check your FASP installation.\nCannot locate:\n#{reslist}")
        end
        @selected_product_paths=res_paths
      end

      # get all fasp resource files paths of currently activated product
      def paths
        if @selected_product_paths.nil?
          # this contains var/run, files generated on runtime
          if @activated.eql?(@@FIRST_FOUND)
            p = installed_products.first
            raise "no FASP installation found\nPlease check manual on how to install FASP." if p.nil?
          else
            p=installed_products.select{|p|p[:name].eql?(@activated)}.first
            raise "no such product installed: #{@activated}" if p.nil?
          end
          self.paths=get_product_paths(p)
        end
        return @selected_product_paths
      end

      # get path of one resource file of currently activated product
      def path(k)
        file=paths[k]
        raise "no such file: #{file}" if !File.exist?(file)
        return file
      end

      # @return the list of installed products in format of product_locations
      def installed_products
        if @found_products.nil?
          @found_products=product_locations.select do |l|
            next false unless Dir.exist?(l[:app_root])
            Log.log.debug("found #{l[:app_root]}")
            product_info_file="#{l[:app_root]}/#{@@PRODUCT_INFO}"
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

      # @returns the file path of local connect where API's URI can be read
      def connect_uri_file
        connect=get_product('Aspera Connect')
        return File.join(connect[:run_root],@@VARRUN_SUBFOLDER,'https.uri')
      end

      # @ return path to configuration file of aspera CLI
      def cli_conf_file
        connect=get_product('Aspera CLI')
        return File.join(connect[:app_root],@@BIN_SUBFOLDER,'.aspera_cli_conf')
      end
      private

      @@VARRUN_SUBFOLDER=File.join('var','run')
      @@BIN_SUBFOLDER='bin'
      @@ETC_SUBFOLDER='etc'
      # policy for product selection
      @@FIRST_FOUND='FIRST'
      # product information manifest: XML
      @@PRODUCT_INFO='product-info.mf'
      @@RSA_FILE_NAME='aspera_tokenauth_id_rsa'
      @@WEBCERT_FILE_NAME='aspera_web_cert.pem'
      @@WEBKEY_FILE_NAME='aspera_web_key.pem'
      @@CLIENT_DSA='asperaweb_id_dsa.openssh'
      @@SERVER_DSA='aspera_tokenauth_id_dsa'

      def get_product(name)
        found=installed_products.select{|i|i[:expected].eql?(name) or i[:name].eql?(name)}
        raise "Product: #{name} not found, please install." if found.empty?
        return found.first
      end

      def initialize
        @selected_product_paths=nil
        @found_products=nil
        @activated=@@FIRST_FOUND
      end

      # necessary FASP SDK resource files
      @@FASP_SDK={
        #:bin_folder             => { :type =>:folder,:required => true},
        #:log_folder             => { :type =>:folder,:required => false},
        :ascp                   => { :type => :file, :required => true},
        :ascp4                  => { :type => :file, :required => false},
        :ssh_bypass_key_dsa     => { :type => :file, :required => true},
        :ssh_bypass_key_rsa     => { :type => :file, :required => true},
        :fallback_cert          => { :type => :file, :required => false},
        :fallback_key           => { :type => :file, :required => false}
      }

      # set ressources path from application information
      # @param p application information
      # a user can set an alternate location, example:
      #      { :expected=>'Enterprise Server',
      #        :app_root=>'/Library/Aspera',
      #        :run_root=>File.join(Dir.home,'Library','Application Support','Aspera','Enterprise Server'),
      #        :log_root=>File.join(Dir.home,'Library','Logs','Aspera'),
      #        :sub_bin=>'bin',
      #        :sub_keys=>'var',
      #        :dsa=>'aspera_tokenauth_id_dsa'}
      def get_product_paths(p)
        exec_ext = OpenApplication.current_os_type.eql?(:windows) ? '.exe' : ''
        # set default values if specific ones not specified
        sub_bin = p[:sub_bin] || @@BIN_SUBFOLDER
        sub_keys = p[:sub_keys] || @@ETC_SUBFOLDER
        res_paths={
          #:bin_folder             => File.join(p[:app_root],sub_bin),
          #:log_folder             => p[:log_root]},
          :ascp                   => File.join(p[:app_root],sub_bin,'ascp')+exec_ext,
          :ascp4                  => File.join(p[:app_root],sub_bin,'ascp4')+exec_ext,
          :ssh_bypass_key_dsa     => File.join(p[:app_root],sub_keys,@@CLIENT_DSA),
          :ssh_bypass_key_rsa     => File.join(p[:app_root],sub_keys,@@RSA_FILE_NAME),
          :fallback_cert          => File.join(p[:app_root],sub_keys,@@WEBCERT_FILE_NAME),
          :fallback_key           => File.join(p[:app_root],sub_keys,@@WEBKEY_FILE_NAME)
        }
        # server software (having asperanoded) has a different DSA filename
        server_dsa=File.join(p[:app_root],sub_keys,@@SERVER_DSA)
        res_paths[:ssh_bypass_key_dsa]=server_dsa if File.exist?(server_dsa)
        Log.log.debug("resources=#{res_paths}")
        return res_paths
      end

      # returns product folders depending on OS
      # fields
      # :expected  M app name is taken from the manifest if present, else defaults to this value
      # :app_root  M main forlder for the application
      # :log_root  O location of log files (Linux uses syslog)
      # :run_root  O only for Connect Client, location of http port file
      # :sub_bin   O subfolder with executables, default : bin
      # :sub_keys  O subfolder with keys, default : etc
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
            :sub_keys =>'var'
            },{
            :expected =>'Enterprise Server',
            :app_root =>File.join('C:','Program Files','Aspera','Enterprise Server'),
            :log_root =>File.join('C:','Program Files','Aspera','Enterprise Server','var','log'),
            :sub_keys =>'var'
            }]
        when :mac; return [{
            :expected =>'Aspera Connect',
            :app_root =>File.join(Dir.home,'Applications','Aspera Connect.app'),
            :log_root =>File.join(Dir.home,'Library','Logs','Aspera_Connect'),
            :run_root =>File.join(Dir.home,'Library','Application Support','Aspera','Aspera Connect'),
            :sub_bin  =>File.join('Contents','Resources'),
            :sub_keys =>File.join('Contents','Resources')
            },{
            :expected =>'Aspera CLI',
            :app_root =>File.join(Dir.home,'Applications','Aspera CLI'),
            :log_root =>File.join(Dir.home,'Library','Logs','Aspera')
            },{
            :expected =>'Enterprise Server',
            :app_root =>File.join('','Library','Aspera'),
            :log_root =>File.join(Dir.home,'Library','Logs','Aspera'),
            :sub_keys =>'var'
            },{
            :expected =>'Aspera Drive',
            :app_root =>File.join('','Applications','Aspera Drive.app'),
            :log_root =>File.join(Dir.home,'Library','Logs','Aspera_Drive'),
            :sub_bin  =>File.join('Contents','Resources'),
            :sub_keys =>File.join('Contents','Resources')
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
            :sub_keys =>'var'
            }]
        end
      end
    end # Installation
  end
end

