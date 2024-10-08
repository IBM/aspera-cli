# frozen_string_literal: true

# cspell:ignore protobuf ckpt
require 'aspera/environment'
require 'aspera/data_repository'
require 'aspera/ascp/products'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/web_server_simple'
require 'English'
require 'singleton'
require 'xmlsimple'
require 'zlib'
require 'base64'
require 'fileutils'
require 'openssl'

module Aspera
  module Ascp
    # Singleton that tells where to find ascp and other local resources (keys..) , using the "path(:name)" method.
    # It is used by object : AgentDirect to find necessary resources
    # By default it takes the first Aspera product found
    # but the user can specify ascp location by calling:
    # Installation.instance.use_ascp_from_product(product_name)
    # or
    # Installation.instance.ascp_path=""
    class Installation
      include Singleton
      # protobuf generated files from sdk
      EXT_RUBY_PROTOBUF = '_pb.rb'
      RB_SDK_FOLDER = 'lib'
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
      private_constant :EXT_RUBY_PROTOBUF, :RB_SDK_FOLDER, :DEFAULT_ASPERA_CONF, :FILES
      # options for SSH client private key
      CLIENT_SSH_KEY_OPTIONS = %i{dsa_rsa rsa per_client}.freeze
      # set ascp executable path
      def ascp_path=(v)
        @path_to_ascp = v
      end

      def ascp_path
        path(:ascp)
      end

      def sdk_ruby_folder
        ruby_pb_folder = File.join(sdk_folder, RB_SDK_FOLDER)
        FileUtils.mkdir_p(ruby_pb_folder)
        return ruby_pb_folder
      end

      # location of SDK files
      def sdk_folder=(v)
        Log.log.debug{"sdk_folder=#{v}"}
        @sdk_dir = v
        sdk_folder
      end

      # backward compatibility in sample program
      alias_method :folder=, :sdk_folder=

      # @return the path to folder where SDK is installed
      def sdk_folder
        raise 'SDK path was ot initialized' if @sdk_dir.nil?
        FileUtils.mkdir_p(@sdk_dir)
        @sdk_dir
      end

      # find ascp in named product (use value : FIRST_FOUND='FIRST' to just use first one)
      # or select one from Products.installed_products()
      def use_ascp_from_product(product_name)
        if product_name.eql?(FIRST_FOUND)
          pl = Products.installed_products.first
          raise "no FASP installation found\nPlease check manual on how to install FASP." if pl.nil?
        else
          pl = Products.installed_products.find{|i|i[:name].eql?(product_name)}
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
            rescue => e
              e.message
            end
        end
      end

      def check_or_create_sdk_file(filename, force: false, &block)
        return Environment.write_file_restricted(File.join(sdk_folder, filename), force: force, mode: 0o644, &block)
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
          file = transferd_filepath
        when :ssh_private_dsa, :ssh_private_rsa
          # assume last 3 letters are type
          type = k.to_s[-3..-1].to_sym
          file = check_or_create_sdk_file("aspera_bypass_#{type}.pem") {DataRepository.instance.item(type)}
        when :aspera_license
          file = check_or_create_sdk_file('aspera-license') {DataRepository.instance.item(:license)}
        when :aspera_conf
          file = check_or_create_sdk_file('aspera.conf') {DEFAULT_ASPERA_CONF}
        when :fallback_certificate, :fallback_private_key
          file_key = File.join(sdk_folder, 'aspera_fallback_cert_private_key.pem')
          file_cert = File.join(sdk_folder, 'aspera_fallback_cert.pem')
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
        Aspera.assert(File.exist?(file)){"no such file: #{file}"}
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
        raise "An error occurred when testing #{ascp_filename}: #{cmd_out}" unless $CHILD_STATUS == 0
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

      def ascp_info
        files = file_paths
        return files.merge(ascp_pvcl_info).merge(ascp_ssl_info)
      end

      # download aspera SDK or use local file
      # extracts ascp binary for current system architecture
      # @return ascp version (from execution)
      def install_sdk(sdk_url)
        # SDK is organized by architecture, check this first, in case architecture is not supported
        arch_filter = "#{Environment.architecture}/"
        require 'zip'
        sdk_zip_path = File.join(Dir.tmpdir, 'sdk.zip')
        if sdk_url.start_with?('file:')
          # require specific file scheme: the path part is "relative", or absolute if there are 4 slash
          raise 'use format: file:///<path>' unless sdk_url.start_with?('file:///')
          sdk_zip_path = sdk_url.gsub(%r{^file:///}, '')
        else
          Aspera::Rest.new(base_url: sdk_url, redirect_max: 3).call(operation: 'GET', save_to_file: sdk_zip_path)
        end
        # rename old install
        if !Dir.empty?(sdk_folder)
          Log.log.warn('Previous install exists, renaming folder.')
          File.rename(sdk_folder, "#{sdk_folder}.#{Time.now.strftime('%Y%m%d%H%M%S')}")
          # TODO: delete old archives ?
        end
        # extract files from archive
        Zip::File.open(sdk_zip_path) do |zip_file|
          zip_file.each do |entry|
            # skip folder entries
            next if entry.name.end_with?('/')
            dest_folder = nil
            # binaries
            dest_folder = sdk_folder if entry.name.include?(arch_filter)
            # ruby adapters
            dest_folder = sdk_ruby_folder if entry.name.end_with?(EXT_RUBY_PROTOBUF)
            next if dest_folder.nil?
            File.open(File.join(dest_folder, File.basename(entry.name)), 'wb') do |output_stream|
              IO.copy_stream(entry.get_input_stream, output_stream)
            end
          end
        end
        File.unlink(sdk_zip_path) rescue nil # Windows may give error
        # ensure license file are generated so that ascp invocation for version works
        path(:aspera_license)
        path(:aspera_conf)
        sdk_ascp_file = Products.ascp_filename
        sdk_ascp_path = File.join(sdk_folder, sdk_ascp_file)
        raise "No #{sdk_ascp_file} found in SDK archive" unless File.exist?(sdk_ascp_path)
        EXE_FILES.each do |exe_sym|
          exe_path = sdk_ascp_path.gsub('ascp', exe_sym.to_s)
          Environment.restrict_file_access(exe_path, mode: 0o755) if File.exist?(exe_path)
        end
        sdk_ascp_version = get_ascp_version(sdk_ascp_path)
        sdk_daemon_path = transferd_filepath
        Log.log.warn{"No #{sdk_daemon_path} in SDK archive"} unless File.exist?(sdk_daemon_path)
        Environment.restrict_file_access(sdk_daemon_path, mode: 0o755) if File.exist?(sdk_daemon_path)
        transferd_version = get_exe_version(sdk_daemon_path, 'version')
        sdk_name = 'IBM Aspera Transfer SDK'
        sdk_version = transferd_version || sdk_ascp_version
        File.write(File.join(sdk_folder, Products::INFO_META_FILE), "<product><name>#{sdk_name}</name><version>#{sdk_version}</version></product>")
        return sdk_name, sdk_version
      end

      private

      # policy for product selection
      FIRST_FOUND = 'FIRST'

      def initialize
        @path_to_ascp = nil
        @sdk_dir = nil
      end

      def transferd_filepath
        return File.join(sdk_folder, 'asperatransferd' + Environment.exe_extension) # cspell:disable-line
      end
    end
  end
end
