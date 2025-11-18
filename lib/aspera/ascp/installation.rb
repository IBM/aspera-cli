# frozen_string_literal: true

# cspell:ignore protobuf ckpt
require 'aspera/environment'
require 'aspera/data_repository'
require 'aspera/log'
require 'aspera/rest'
require 'aspera/uri_reader'
require 'aspera/assert'
require 'aspera/web_server_simple'
require 'aspera/cli/info'
require 'aspera/cli/version'
require 'aspera/products/desktop'
require 'aspera/products/connect'
require 'aspera/products/transferd'
require 'aspera/products/other'
require 'English'
require 'singleton'
require 'xmlsimple'
require 'base64'
require 'fileutils'
require 'openssl'
require 'yaml'
module Aspera
  module Ascp
    # Singleton that tells where to find ascp and other local resources (keys..) , using the "path(:name)" method.
    # It is used by object : AgentDirect to find necessary resources
    # By default it takes the first Aspera product found
    # The user can specify ascp location by calling:
    # Installation.instance.use_ascp_from_product(product_name)
    # or
    # Installation.instance.ascp_path=""
    class Installation
      include Singleton

      # options for SSH client private key
      CLIENT_SSH_KEY_OPTIONS = %i{dsa_rsa rsa per_client}.freeze
      # prefix
      USE_PRODUCT_PREFIX = 'product:'
      # policy for product selection
      FIRST_FOUND = 'FIRST'

      # Loads YAML from cloud with locations of SDK archives for all platforms
      # @return location structure
      def sdk_locations
        location_url = @transferd_urls
        transferd_locations = UriReader.read(location_url)
        Log.log.debug{"Retrieving SDK locations from #{location_url}"}
        begin
          return YAML.load(transferd_locations)
        rescue Psych::SyntaxError
          raise "Error when parsing yaml data from: #{location_url}"
        end
      end

      # set ascp executable "location"
      def ascp_path=(v)
        Aspera.assert_type(v, String)
        Aspera.assert(!v.empty?){'ascp location cannot be empty: check your config file'}
        @ascp_location = v
        @ascp_path = nil
        return
      end

      def ascp_path
        path(:ascp)
      end

      # Compatibility
      def sdk_folder=(v)
        Products::Transferd.sdk_directory = v
      end

      # find ascp in named product (use value : FIRST_FOUND='FIRST' to just use first one)
      # or select one from installed_products()
      def use_ascp_from_product(product_name)
        if product_name.eql?(FIRST_FOUND)
          pl = installed_products.first
          raise "No Aspera transfer module or SDK found.\nRefer to the manual or install SDK with command:\nascli conf transferd install" if pl.nil?
        else
          pl = installed_products.find{ |i| i[:name].eql?(product_name)}
          raise "No such product installed: #{product_name}" if pl.nil?
        end
        @ascp_path = pl[:ascp_path]
      end

      # @return [Hash] with key = file name (String), and value = path to file
      def file_paths
        return SDK_FILES.each_with_object({}) do |v, m|
          m[v.to_s] =
            begin
              path(v)
            rescue Errno::ENOENT => e
              e.message.gsub(/.*assertion failed: /, '').gsub(/\): .*/, ')')
            rescue => e
              e.message
            end
        end
      end

      # TODO: if using another product than SDK, should use files from there
      def check_or_create_sdk_file(filename, force: false, &block)
        FileUtils.mkdir_p(Products::Transferd.sdk_directory)
        return Environment.write_file_restricted(File.join(Products::Transferd.sdk_directory, filename), force: force, mode: 0o644, &block)
      end

      # Get path of one resource file of currently activated product
      # keys and certs are generated locally... (they are well known values, arch. independent)
      # @param k [Symbol] key of the resource file
      # @return [String, nil] Full path to the resource file or nil if not found
      def path(k)
        file_is_required = true
        case k
        when *EXE_FILES
          file_is_required = k.eql?(:ascp)
          file = if k.eql?(:transferd)
            Products::Transferd.transferd_path
          else
            # find ascp when needed
            if @ascp_path.nil?
              if @ascp_location.start_with?(USE_PRODUCT_PREFIX)
                use_ascp_from_product(@ascp_location[USE_PRODUCT_PREFIX.length..-1])
              else
                @ascp_path = @ascp_location
              end
              Aspera.assert(File.exist?(@ascp_path)){"No such file: [#{@ascp_path}]"}
              Log.log.debug{"ascp_path=#{@ascp_path}"}
            end
            # NOTE: that there might be a .exe at the end
            @ascp_path.gsub('ascp', k.to_s)
          end
        when :ssh_private_dsa, :ssh_private_rsa
          # assume last 3 letters are type
          type = k.to_s[-3..-1].to_sym
          file = check_or_create_sdk_file("aspera_bypass_#{type}.pem"){DataRepository.instance.item(type)}
        when :aspera_license
          file = check_or_create_sdk_file('aspera-license'){DataRepository.instance.item(:license)}
        when :aspera_conf
          file = check_or_create_sdk_file('aspera.conf'){DEFAULT_ASPERA_CONF}
        when :fallback_certificate, :fallback_private_key
          file_key = File.join(Products::Transferd.sdk_directory, 'aspera_fallback_cert_private_key.pem')
          file_cert = File.join(Products::Transferd.sdk_directory, 'aspera_fallback_cert.pem')
          if !File.exist?(file_key) || !File.exist?(file_cert)
            require 'openssl'
            # create new self signed certificate for http fallback
            private_key = OpenSSL::PKey::RSA.new(4096)
            cert = WebServerSimple.self_signed_cert(private_key)
            check_or_create_sdk_file('aspera_fallback_cert_private_key.pem', force: true){private_key.to_pem}
            check_or_create_sdk_file('aspera_fallback_cert.pem', force: true){cert.to_pem}
          end
          file = k.eql?(:fallback_certificate) ? file_cert : file_key
        else Aspera.error_unexpected_value(k)
        end
        return unless file_is_required || File.exist?(file)
        Aspera.assert(File.exist?(file), type: Errno::ENOENT){"#{k} not found (#{file})"}
        return file
      end

      # default bypass key phrase
      def ssh_cert_uuid
        return DataRepository.instance.item(:uuid)
      end

      # get paths of SSH keys to use for ascp client
      # @param types [Symbol] types to use
      def aspera_token_ssh_key_paths(types)
        Aspera.assert_values(types, CLIENT_SSH_KEY_OPTIONS)
        return case types
               when :dsa_rsa, :rsa
                 types.to_s.split('_').map{ |i| Installation.instance.path("ssh_private_#{i}".to_sym)}
               when :per_client
                 Aspera.error_not_implemented
               end
      end

      # use in plugin `config`
      def get_ascp_version(exe_path)
        return get_exe_version(exe_path, '-A')
      end

      # Check that specified path is ascp and get version
      def get_exe_version(exe_path, vers_arg)
        Aspera.assert_type(exe_path, String)
        Aspera.assert_type(vers_arg, String)
        return unless File.exist?(exe_path)
        exe_version = nil
        cmd_out = %x("#{exe_path}" #{vers_arg})
        raise "An error occurred when testing #{exe_path}: #{cmd_out}" unless $CHILD_STATUS == 0
        # get version from ascp, only after full extract, as windows requires DLLs (SSL/TLS/etc...)
        m = cmd_out.match(/ version ([0-9.]+)/)
        exe_version = m[1].gsub(/\.$/, '') unless m.nil?
        return exe_version
      end

      # Extract some stings from ascp logs
      # Folder, PVCL, version, license information
      def ascp_info_from_log
        data = {}
        # read PATHs from ascp directly, and pvcl modules as well
        Open3.popen3(ascp_path, '-DDL-') do |_stdin, _stdout, stderr, thread|
          last_line = ''
          while (line = stderr.gets)
            line.chomp!
            # skip lines that may have accents
            next unless line.valid_encoding?
            last_line = line
            case line
            when /^DBG Path ([^ ]+) (dir|file) +: (.*)$/
              data[Regexp.last_match(1)] = Regexp.last_match(3)
            when /^DBG Added module group:"(?<module>[^"]+)" name:"(?<scheme>[^"]+)", version:"(?<version>[^"]+)" interface:"(?<interface>[^"]+)"$/
              c = Regexp.last_match.named_captures.symbolize_keys
              data[c[:interface]] ||= {}
              data[c[:interface]][c[:module]] ||= []
              data[c[:interface]][c[:module]].push("#{c[:scheme]} v#{c[:version]}")
            when %r{^DBG License result \(/license/(\S+)\): (.+)$}
              data[Regexp.last_match(1)] = Regexp.last_match(2)
            when /^LOG (.+) version ([0-9.]+)$/
              data['product_name'] = Regexp.last_match(1)
              data['product_version'] = Regexp.last_match(2)
            when /^LOG Initializing FASP version ([^,]+),/
              data['ascp_version'] = Regexp.last_match(1)
            end
          end
          raise last_line if !thread.value.exitstatus.eql?(1) && !data.key?('root')
        end
        return data
      end

      # Extract some stings from ascp binary
      # Openssl information
      def ascp_info_from_file
        data = {}
        File.binread(ascp_path).scan(/[\x20-\x7E]{10,}/) do |bin_string|
          if (m = bin_string.match(/OPENSSLDIR.*"(.*)"/))
            data['ascp_openssl_dir'] = m[1]
          elsif (m = bin_string.match(/OpenSSL (\d[^ -]+)/))
            data['ascp_openssl_version'] = m[1]
          end
        end if File.file?(ascp_path)
        return data
      end

      # information for `ascp info`
      def ascp_info
        ascp_data = file_paths
        ascp_data.merge!(ascp_info_from_log)
        ascp_data.merge!(ascp_info_from_file)
        return ascp_data
      end

      # @return the url for download of SDK archive for the given platform and version
      def sdk_url_for_platform(platform: nil, version: nil)
        all_locations = sdk_locations
        platform = Environment.instance.architecture if platform.nil?
        locations = all_locations.select{ |l| l['platform'].eql?(platform)}
        raise "No SDK for platform: #{platform}, available: #{all_locations.map{ |i| i['platform']}.uniq}" if locations.empty?
        version = locations.max_by{ |entry| Gem::Version.new(entry['version'])}['version'] if version.nil?
        info = locations.select{ |entry| entry['version'].eql?(version)}
        raise "No such version: #{version} for #{platform}" if info.empty?
        return info.first['url']
      end

      # @param &block called with entry information
      def extract_archive_files(sdk_archive_path)
        Aspera.assert(block_given?){'missing block'}
        case sdk_archive_path
        # Windows and Mac use zip
        when /\.zip$/
          require 'zip'
          # extract files from archive
          Zip::File.open(sdk_archive_path) do |zip_file|
            zip_file.each do |entry|
              next if entry.name.end_with?('/')
              entry.get_input_stream do |io|
                yield(entry.name, io, nil)
              end
            end
          end
        # Other Unixes use tar.gz
        when /\.tar\.gz/
          require 'zlib'
          require 'rubygems/package'
          Zlib::GzipReader.open(sdk_archive_path) do |gzip|
            Gem::Package::TarReader.new(gzip) do |tar|
              tar.each do |entry|
                next if entry.directory?
                yield(entry.full_name, entry, entry.symlink? ? entry.header.linkname : nil)
              end
            end
          end
        else
          raise "unknown archive extension: #{sdk_archive_path}"
        end
      end

      # Retrieves ascp binary for current system architecture from URL or file
      # @param url      [String] URL to SDK archive, or SpecialValues::DEF
      # @param folder   [String] Destination folder path
      # @param backup   [Bool]   If destination folder exists, then rename
      # @param with_exe [Bool]   If false, only retrieves files, but do not generate or restrict access
      # @param &block   [Proc]   A lambda that receives a file path from archive and tells destination sub folder(end with /) or file, or nil to not extract
      # @return ascp version (from execution)
      def install_sdk(url: nil, version: nil, folder: nil, backup: true, with_exe: true, &block)
        url = sdk_url_for_platform(version: version) if url.nil? || url.eql?('DEF')
        folder = Products::Transferd.sdk_directory if folder.nil?
        subfolder_lambda = block
        if subfolder_lambda.nil?
          # default files to extract directly to main folder if in selected source folders
          subfolder_lambda = ->(name) do
            Products::Transferd::RUNTIME_FOLDERS.any?{ |i| name.match?(%r{^[^/]*/#{i}/})} ? '/' : nil
          end
        end
        FileUtils.mkdir_p(folder)
        # rename old install
        if backup && !Dir.empty?(folder)
          Log.log.warn('Previous install exists, renaming folder.')
          File.rename(folder, "#{folder}.#{Time.now.strftime('%Y%m%d%H%M%S')}")
          # TODO: delete old archives ?
        end
        sdk_archive_path = UriReader.read_as_file(url)
        extract_archive_files(sdk_archive_path) do |entry_name, entry_stream, link_target|
          dest_folder = subfolder_lambda.call(entry_name)
          next if dest_folder.nil?
          dest_folder = File.join(folder, dest_folder)
          if dest_folder.end_with?('/')
            dest_file = File.join(dest_folder, File.basename(entry_name))
          else
            dest_file = dest_folder
            dest_folder = File.dirname(dest_file)
          end
          FileUtils.mkdir_p(dest_folder)
          if link_target.nil?
            File.open(dest_file, 'wb'){ |output_stream| IO.copy_stream(entry_stream, output_stream)}
          else
            File.symlink(link_target, dest_file)
          end
        end
        return unless with_exe
        # Ensure necessary files are there, or generate them
        SDK_FILES.each do |file_id_sym|
          file_path = path(file_id_sym)
          if file_path && EXE_FILES.include?(file_id_sym)
            Environment.restrict_file_access(file_path, mode: 0o755) if File.exist?(file_path)
          end
        end
        sdk_ascp_version = get_ascp_version(path(:ascp))
        transferd_version = get_exe_version(path(:transferd), 'version')
        sdk_name = 'IBM Aspera Transfer SDK'
        sdk_version = transferd_version || sdk_ascp_version
        File.write(File.join(folder, Products::Other::INFO_META_FILE), "<product><name>#{sdk_name}</name><version>#{sdk_version}</version></product>")
        return sdk_name, sdk_version
      end

      attr_accessor :transferd_urls

      private

      DEFAULT_ASPERA_CONF = <<~END_OF_CONFIG_FILE
        <?xml version='1.0' encoding='UTF-8'?>
        <CONF version="2">
        <default>
            <file_system>
                <resume_suffix>.aspera-ckpt</resume_suffix>
                <partial_file_suffix>.partial</partial_file_suffix>
            </file_system>
        </default>
        </CONF>
      END_OF_CONFIG_FILE
      # all executable files from SDK
      EXE_FILES = %i[ascp ascp4 async transferd].freeze
      SDK_FILES = %i[ssh_private_dsa ssh_private_rsa aspera_license aspera_conf fallback_certificate fallback_private_key].unshift(*EXE_FILES).freeze
      TRANSFERD_ARCHIVE_LOCATION_URL = 'https://ibm.biz/sdk_location'
      # filename for ascp with optional extension (Windows)
      private_constant :DEFAULT_ASPERA_CONF, :EXE_FILES, :SDK_FILES, :TRANSFERD_ARCHIVE_LOCATION_URL

      def initialize
        @ascp_path = nil
        @ascp_location = nil
        @sdk_dir = nil
        @found_products = nil
        @transferd_urls = TRANSFERD_ARCHIVE_LOCATION_URL
      end

      public

      # @return the list of installed products in format of product_locations_on_current_os
      def installed_products
        return @found_products unless @found_products.nil?
        # :expected  M app name is taken from the manifest if present, else defaults to this value
        # :app_root  M main folder for the application
        # :log_root  O location of log files (Linux uses syslog)
        # :run_root  O only for Connect Client, location of http port file
        # :sub_bin   O subfolder with executables, default : bin
        scan_locations = Products::Transferd.locations +
          Products::Desktop.locations +
          Products::Connect.locations +
          Products::Other::LOCATION_ON_THIS_OS
        # search installed products: with ascp
        @found_products = Products::Other.find(scan_locations)
      end
    end
  end
end
