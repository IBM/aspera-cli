require 'singleton'
require 'asperalm/log'
require 'asperalm/open_application' # current_os_type

require 'xmlsimple'

module Asperalm
  module Fasp
    # locate Aspera transfer products based on OS
    # then identifies resources (binary, keys..)
    class Installation
      include Singleton
      VARRUN_SUBFOLDER='var/run'
      FIRST_FOUND='FIRST'
      PRODUCT_INFO='product-info.mf'

      # name of Aspera application to be used or :first
      attr_reader :activated
      def activated=(value)
        @activated=value
        # reset installed paths
        @i_p=nil
      end

      # installation paths
      # get fasp resource files paths
      def paths
        if @i_p.nil?
          # this contains var/run, files generated on runtime
          if @activated.eql?(FIRST_FOUND)
            p = installed_products.first
            raise "no FASP installation found\nPlease check manual on how to install FASP." if p.nil?
          else
            p=installed_products.select{|p|p[:name].eql?(@activated)}.first
            raise "no such product installed: #{@activated}" if p.nil?
          end
          @i_p=self.class.get_product_paths(p)
        end
        return @i_p
      end

      # user can set all path directly
      def paths=(path_set)
        raise "must be a hash" unless path_set.is_a?(Hash)
        @i_p=path_set
      end

      # get path of one resource file
      def path(k)
        file=paths[k][:path]
        raise "no such file: #{file}" if !File.exist?(file)
        return file
      end

      # @return the list of installed products
      def installed_products
        if @found_products.nil?
          @found_products=product_locations.select do |l|
            next false unless Dir.exist?(l[:app_root])
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

      def get_product(name)
        found=installed_products.select{|i|i[:name].eql?(name)}
        raise "Product: #{name} not found, please install." if found.empty?
        return found.first
      end

      private

      def initialize
        @i_p=nil
        @found_products=nil
        @activated=FIRST_FOUND
      end

      # set ressources path from application information
      # @param p application information
      # a user can set an alternate location, example:
      #      { :expected=>'Enterprise Server',
      #        :exe_ext=>'',
      #        :app_root=>'/Library/Aspera',
      #        :run_root=>File.join(Dir.home,'Library','Application Support','Aspera','Enterprise Server'),
      #        :log_root=>File.join(Dir.home,'Library','Logs','Aspera'),
      #        :sub_bin=>'bin',
      #        :sub_keys=>'var',
      #        :dsa=>'aspera_tokenauth_id_dsa'}
      def self.get_product_paths(p)
        result={
          :bin_folder             => { :type =>:folder,:required => true, :path =>File.join(p[:app_root],p[:sub_bin])},
          :ascp                   => { :type => :file, :required => true, :path =>File.join(p[:app_root],p[:sub_bin],'ascp')+p[:exe_ext].to_s},
          :ascp4                  => { :type => :file, :required => false,:path =>File.join(p[:app_root],p[:sub_bin],'ascp4')+p[:exe_ext].to_s},
          :ssh_bypass_key_dsa     => { :type => :file, :required => true, :path =>File.join(p[:app_root],p[:sub_keys],p[:dsa])},
          :ssh_bypass_key_rsa     => { :type => :file, :required => true, :path =>File.join(p[:app_root],p[:sub_keys],'aspera_tokenauth_id_rsa')},
          :fallback_cert          => { :type => :file, :required => false,:path =>File.join(p[:app_root],p[:sub_keys],'aspera_web_cert.pem')},
          :fallback_key           => { :type => :file, :required => false,:path =>File.join(p[:app_root],p[:sub_keys],'aspera_web_key.pem')},
          :plugin_https_port_file => { :type => :file, :required => false,:path =>File.join(p[:run_root],VARRUN_SUBFOLDER,'https.uri')},
          :log_folder             => { :type =>:folder,:required => false,:path =>p[:log_root]}
        }
        Log.log.debug "resources=#{result}"
        notfound=[]
        result.each_pair do |k,v|
          notfound.push(k) if v[:type].eql?(:file) and v[:required] and ! File.exist?(v[:path])
        end
        if !notfound.empty?
          reslist=notfound.map { |k| "#{k.to_s}: #{result[k][:path]}"}.join("\n")
          raise StandardError.new("Please check your connect client installation, Cannot locate resource(s):\n#{reslist}")
        end
        return result
      end

      # returns product folders depending on OS
      # field :exe_ext is nil if no ext, else it's the exe string (incl. dot).
      def product_locations
        common_places=[]
        case OpenApplication.current_os_type
        when :windows
          common_places.push({
            :expected=>'Aspera Connect',
            :exe_ext=>'.exe',
            :app_root=>File.join(ENV['LOCALAPPDATA'],'Programs','Aspera','Aspera Connect'),
            :run_root=>File.join(ENV['LOCALAPPDATA'],'Aspera','Aspera Connect'),
            :sub_bin=>'bin',
            :sub_keys=>'etc',
            :dsa=>'asperaweb_id_dsa.openssh'})
        when :mac
          common_places.push({
            :expected=>'Aspera Connect',
            :exe_ext=>'',
            :app_root=>File.join(Dir.home,'Applications','Aspera Connect.app'),
            :run_root=>File.join(Dir.home,'Library','Application Support','Aspera','Aspera Connect'),
            :log_root=>File.join(Dir.home,'Library','Logs','Aspera_Connect'),
            :sub_bin=>File.join('Contents','Resources'),
            :sub_keys=>File.join('Contents','Resources'),
            :dsa=>'asperaweb_id_dsa.openssh'})
          common_places.push({
            :expected=>'Enterprise Server',
            :exe_ext=>'',
            :app_root=>'/Library/Aspera',
            :run_root=>File.join(Dir.home,'Library','Application Support','Aspera','Enterprise Server'),
            :log_root=>File.join(Dir.home,'Library','Logs','Aspera'),
            :sub_bin=>'bin',
            :sub_keys=>'var',
            :dsa=>'aspera_tokenauth_id_dsa'})
          common_places.push({
            :expected=>'Aspera CLI',
            :exe_ext=>'',
            :app_root=>File.join(Dir.home,'Applications','Aspera CLI'),
            :run_root=>File.join(Dir.home,'Library','Application Support','Aspera','Aspera Connect'),
            :log_root=>File.join(Dir.home,'Library','Logs','Aspera'),
            :sub_bin=>File.join('bin'),
            :sub_keys=>File.join('etc'),
            :dsa=>'asperaweb_id_dsa.openssh'})
        else  # other: unix family
          common_places.push({
            :expected=>'Aspera Connect',
            :exe_ext=>'',
            :app_root=>File.join(Dir.home,'.aspera','connect'),
            :run_root=>File.join(Dir.home,'.aspera','connect'),
            :sub_bin=>'bin',
            :sub_keys=>'etc',
            :dsa=>'asperaweb_id_dsa.openssh'})
          common_places.push({
            :expected=>'Enterprise Server',
            :exe_ext=>'',
            :app_root=>'/opt/aspera',
            :run_root=>'/opt/aspera',
            :sub_bin=>'bin',
            :sub_keys=>'var',
            :dsa=>'aspera_tokenauth_id_dsa'})
        end
        return common_places
      end
    end # Installation
  end
end

