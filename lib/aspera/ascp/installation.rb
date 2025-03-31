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
require 'aspera/products/alpha'
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
      # all ascp files (in SDK)
      EXE_FILES = %i[ascp ascp4 async].freeze
      FILES = %i[transferd ssh_private_dsa ssh_private_rsa aspera_license aspera_conf fallback_certificate fallback_private_key].unshift(*EXE_FILES).freeze
      TRANSFER_SDK_LOCATION_URL = 'https://ibm.biz/sdk_location'
      FILE_SCHEME_PREFIX = 'file:///'
      # filename for ascp with optional extension (Windows)
      private_constant :DEFAULT_ASPERA_CONF, :FILES, :TRANSFER_SDK_LOCATION_URL, :FILE_SCHEME_PREFIX
      # options for SSH client private key
      CLIENT_SSH_KEY_OPTIONS = %i{dsa_rsa rsa per_client}.freeze

      class << self
        def transfer_sdk_location_url
          ENV.fetch('ASCLI_TRANSFER_SDK_LOCATION_URL', TRANSFER_SDK_LOCATION_URL)
        end

        # Loads YAML from cloud with locations of SDK archives for all platforms
        # @return location structure
        def sdk_locations
          location_url = transfer_sdk_location_url
          transferd_locations = UriReader.read(location_url)
          Log.log.debug{"Retrieving SDK locations from #{location_url}"}
          begin
            return YAML.load(transferd_locations)
          rescue Psych::SyntaxError
            raise "Error when parsing yaml data from: #{location_url}"
          end
        end
      end

      # set ascp executable path
      def ascp_path=(v)
        Aspera.assert_type(v, String)
        Aspera.assert(!v.empty?) {'ascp path cannot be empty: check your config file'}
        Aspera.assert(File.exist?(v)) {"No such file: [#{v}]"}
        @path_to_ascp = v
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
          raise "no Aspera transfer module or SDK found.\nRefer to the manual or install SDK with command:\nascli conf ascp install" if pl.nil?
        else
          pl = installed_products.find{|i|i[:name].eql?(product_name)}
          raise "no such product installed: #{product_name}" if pl.nil?
        end
        self.ascp_path = pl[:ascp_path]
        Log.log.debug{"ascp_path=#{@path_to_ascp}"}
      end

      # @return [Hash] with key = file name (String), and value = path to file
      def file_paths
        return FILES.each_with_object({}) do |v, m|
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

      def check_or_create_sdk_file(filename, force: false, &block)
        return Environment.write_file_restricted(File.join(Products::Transferd.sdk_directory, filename), force: force, mode: 0o644, &block)
      end

      # get path of one resource file of currently activated product
      # keys and certs are generated locally... (they are well known values, arch. independent)
      def path(k)
        file_is_optional = false
        case k
        when *EXE_FILES
          file_is_optional = k.eql?(:async)
          use_ascp_from_product(FIRST_FOUND) if @path_to_ascp.nil?
          # NOTE: that there might be a .exe at the end
          file = @path_to_ascp.gsub('ascp', k.to_s)
        when :transferd
          file_is_optional = true
          file = Products::Transferd.transferd_path
        when :ssh_private_dsa, :ssh_private_rsa
          # assume last 3 letters are type
          type = k.to_s[-3..-1].to_sym
          file = check_or_create_sdk_file("aspera_bypass_#{type}.pem") {DataRepository.instance.item(type)}
        when :aspera_license
          file = check_or_create_sdk_file('aspera-license') {DataRepository.instance.item(:license)}
        when :aspera_conf
          file = check_or_create_sdk_file('aspera.conf') {DEFAULT_ASPERA_CONF}
        when :fallback_certificate, :fallback_private_key
          file_key = File.join(Products::Transferd.sdk_directory, 'aspera_fallback_cert_private_key.pem')
          file_cert = File.join(Products::Transferd.sdk_directory, 'aspera_fallback_cert.pem')
          if !File.exist?(file_key) || !File.exist?(file_cert)
            require 'openssl'
            # create new self signed certificate for http fallback
            cert = OpenSSL::X509::Certificate.new
            private_key = OpenSSL::PKey::RSA.new(4096)
            WebServerSimple.fill_self_signed_cert(cert, private_key)
            check_or_create_sdk_file('aspera_fallback_cert_private_key.pem', force: true) {private_key.to_pem}
            check_or_create_sdk_file('aspera_fallback_cert.pem', force: true) {cert.to_pem}
          end
          file = k.eql?(:fallback_certificate) ? file_cert : file_key
        else Aspera.error_unexpected_value(k)
        end
        return nil if file_is_optional && !File.exist?(file)
        Aspera.assert(File.exist?(file), exception_class: Errno::ENOENT){"#{k} not found (#{file})"}
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
                 types.to_s.split('_').map{|i|Installation.instance.path("ssh_private_#{i}".to_sym)}
               when :per_client
                 raise 'Not yet implemented'
               end
      end

      # use in plugin `config`
      def get_ascp_version(exe_path)
        return get_exe_version(exe_path, '-A')
      end

      # Check that specified path is ascp and get version
      def get_exe_version(exe_path, vers_arg)
        raise 'ERROR: nil arg' if exe_path.nil?
        return nil unless File.exist?(exe_path)
        exe_version = nil
        cmd_out = %x("#{exe_path}" #{vers_arg})
        raise "An error occurred when testing #{exe_path}: #{cmd_out}" unless $CHILD_STATUS == 0
        # get version from ascp, only after full extract, as windows requires DLLs (SSL/TLS/etc...)
        m = cmd_out.match(/ version ([0-9.]+)/)
        exe_version = m[1].gsub(/\.$/, '') unless m.nil?
        return exe_version
      end

      def ascp_pvcl_info
        data = {}
        # read PATHs from ascp directly, and pvcl modules as well
        Open3.popen3(ascp_path, '-DDL-') do |_stdin, _stdout, stderr, thread|
          last_line = ''
          while (line = stderr.gets)
            line.chomp!
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
              data['sdk_ascp_version'] = Regexp.last_match(1)
            end
          end
          if !thread.value.exitstatus.eql?(1) && !data.key?('root')
            raise last_line
          end
        end
        return data
      end

      # extract some stings from ascp binary
      def ascp_ssl_info
        data = {}
        File.binread(ascp_path).scan(/[\x20-\x7E]{10,}/) do |bin_string|
          if (m = bin_string.match(/OPENSSLDIR.*"(.*)"/))
            data['openssldir'] = m[1]
          elsif (m = bin_string.match(/OpenSSL (\d[^ -]+)/))
            data['openssl_version'] = m[1]
          end
        end if File.file?(ascp_path)
        return data
      end

      # information for `ascp info`
      def ascp_info
        ascp_data = file_paths
        ascp_data.merge!(ascp_pvcl_info)
        ascp_data['sdk_locations'] = self.class.transfer_sdk_location_url
        ascp_data.merge!(ascp_ssl_info)
        return ascp_data
      end

      # @return the url for download of SDK archive for the given platform and version
      def sdk_url_for_platform(platform: nil, version: nil)
        locations = self.class.sdk_locations
        platform = Environment.architecture if platform.nil?
        locations = locations.select{|l|l['platform'].eql?(platform)}
        raise "No SDK for platform: #{platform}" if locations.empty?
        version = locations.max_by { |entry| Gem::Version.new(entry['version']) }['version'] if version.nil?
        info = locations.select{|entry| entry['version'].eql?(version)}
        raise "No such version: #{version} for #{platform}" if info.empty?
        return info.first['url']
      end

      # @param &block called with entry information
      def extract_archive_files(sdk_archive_path)
        raise 'missing block' unless block_given?
        case sdk_archive_path
        # Windows and Mac use zip
        when /\.zip$/
          require 'zip'
          # extract files from archive
          Zip::File.open(sdk_archive_path) do |zip_file|
            zip_file.each do |entry|
              next if entry.name.end_with?('/')
              yield(entry.name, entry.get_input_stream, nil)
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
      # @param &block   [Proc]   A lambda that receives a file path from archive and tells detination sub folder(end with /) or file, or nil to not extract
      # @return ascp version (from execution)
      def install_sdk(url: nil, version: nil, folder: nil, backup: true, with_exe: true, &block)
        url = sdk_url_for_platform(version: version) if url.nil? || url.eql?('DEF')
        folder = Products::Transferd.sdk_directory if folder.nil?
        subfolder_lambda = block
        if subfolder_lambda.nil?
          # default files to extract directly to main folder if in selected source folders
          subfolder_lambda = ->(name) do
            Products::Transferd::RUNTIME_FOLDERS.any?{|i|name.match?(%r{^[^/]*/#{i}/})} ? '/' : nil
          end
        end
        if url.start_with?('file:')
          # require specific file scheme: the path part is "relative", or absolute if there are 4 slash
          raise 'use format: file:///<path>' unless url.start_with?(FILE_SCHEME_PREFIX)
          sdk_archive_path = url[FILE_SCHEME_PREFIX.length..-1]
          delete_archive = false
        else
          sdk_archive_path = File.join(Dir.tmpdir, File.basename(url))
          Aspera::Rest.new(base_url: url, redirect_max: 3).call(operation: 'GET', save_to_file: sdk_archive_path)
          delete_archive = true
        end
        # rename old install
        if backup && !Dir.empty?(folder)
          Log.log.warn('Previous install exists, renaming folder.')
          File.rename(folder, "#{folder}.#{Time.now.strftime('%Y%m%d%H%M%S')}")
          # TODO: delete old archives ?
        end
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
            File.open(dest_file, 'wb') { |output_stream|IO.copy_stream(entry_stream, output_stream)}
          else
            File.symlink(link_target, dest_file)
          end
        end
        File.unlink(sdk_archive_path) rescue nil if delete_archive # Windows may give error
        return unless with_exe
        # ensure license file are generated so that ascp invocation for version works
        path(:aspera_license)
        path(:aspera_conf)
        sdk_ascp_file = Environment.exe_file('ascp')
        sdk_ascp_path = File.join(folder, sdk_ascp_file)
        raise "No #{sdk_ascp_file} found in SDK archive" unless File.exist?(sdk_ascp_path)
        EXE_FILES.each do |exe_sym|
          exe_path = sdk_ascp_path.gsub('ascp', exe_sym.to_s)
          Environment.restrict_file_access(exe_path, mode: 0o755) if File.exist?(exe_path)
        end
        sdk_ascp_version = get_ascp_version(sdk_ascp_path)
        transferd_exe_path = Products::Transferd.transferd_path
        Log.log.warn{"No #{transferd_exe_path} in SDK archive"} unless File.exist?(transferd_exe_path)
        Environment.restrict_file_access(transferd_exe_path, mode: 0o755) if File.exist?(transferd_exe_path)
        transferd_version = get_exe_version(transferd_exe_path, 'version')
        sdk_name = 'IBM Aspera Transfer SDK'
        sdk_version = transferd_version || sdk_ascp_version
        File.write(File.join(folder, Products::Other::INFO_META_FILE), "<product><name>#{sdk_name}</name><version>#{sdk_version}</version></product>")
        return sdk_name, sdk_version
      end

      private

      # policy for product selection
      FIRST_FOUND = 'FIRST'

      def initialize
        @path_to_ascp = nil
        @sdk_dir = nil
        @found_products = nil
      end

      public

      # @return the list of installed products in format of product_locations_on_current_os
      def installed_products
        if @found_products.nil?
          # :expected  M app name is taken from the manifest if present, else defaults to this value
          # :app_root  M main folder for the application
          # :log_root  O location of log files (Linux uses syslog)
          # :run_root  O only for Connect Client, location of http port file
          # :sub_bin   O subfolder with executables, default : bin
          scan_locations = Products::Transferd.locations.concat(
            Products::Alpha.locations,
            Products::Connect.locations,
            Products::Other::LOCATION_ON_THIS_OS
          )
          # .each {|item| item.deep_do {|h, _k, _v, _m|h.freeze}}.freeze
          # search installed products: with ascp
          @found_products = Products::Other.find(scan_locations)
        end
        return @found_products
      end
    end
  end
end
