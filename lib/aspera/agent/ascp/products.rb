# frozen_string_literal: true

# cspell:ignore LOCALAPPDATA
require 'aspera/environment'

module Aspera
  module Agent
    module Ascp
      # find Aspera standard products installation in standard paths
      class Products
        # known product names
        CONNECT = 'IBM Aspera Connect'
        ASPERA = 'IBM Aspera (Client)'
        CLI_V1 = 'Aspera CLI (deprecated)'
        DRIVE = 'Aspera Drive (deprecated)'
        HSTS = 'IBM Aspera High-Speed Transfer Server'
        # product information manifest: XML (part of aspera product)
        INFO_META_FILE = 'product-info.mf'
        BIN_SUBFOLDER = 'bin'
        ETC_SUBFOLDER = 'etc'
        VAR_RUN_SUBFOLDER = File.join('var', 'run')

        @@found_products = nil # rubocop:disable Style/ClassVars
        class << self
          # @return product folders depending on OS fields
          # :expected  M app name is taken from the manifest if present, else defaults to this value
          # :app_root  M main folder for the application
          # :log_root  O location of log files (Linux uses syslog)
          # :run_root  O only for Connect Client, location of http port file
          # :sub_bin   O subfolder with executables, default : bin
          def product_locations_on_current_os
            result =
              case Aspera::Environment.os
              when Aspera::Environment::OS_WINDOWS then [{
                expected: CONNECT,
                app_root: File.join(ENV.fetch('LOCALAPPDATA', nil), 'Programs', 'Aspera', 'Aspera Connect'),
                log_root: File.join(ENV.fetch('LOCALAPPDATA', nil), 'Aspera', 'Aspera Connect', 'var', 'log'),
                run_root: File.join(ENV.fetch('LOCALAPPDATA', nil), 'Aspera', 'Aspera Connect')
              }, {
                expected: CLI_V1,
                app_root: File.join('C:', 'Program Files', 'Aspera', 'cli'),
                log_root: File.join('C:', 'Program Files', 'Aspera', 'cli', 'var', 'log')
              }, {
                expected: HSTS,
                app_root: File.join('C:', 'Program Files', 'Aspera', 'Enterprise Server'),
                log_root: File.join('C:', 'Program Files', 'Aspera', 'Enterprise Server', 'var', 'log')
              }]
              when Aspera::Environment::OS_X then [{
                expected: CONNECT,
                app_root: File.join(Dir.home, 'Applications', 'Aspera Connect.app'),
                log_root: File.join(Dir.home, 'Library', 'Logs', 'Aspera_Connect'),
                run_root: File.join(Dir.home, 'Library', 'Application Support', 'Aspera', 'Aspera Connect'),
                sub_bin:  File.join('Contents', 'Resources')
              }, {
                expected: CONNECT,
                app_root: File.join('', 'Applications', 'Aspera Connect.app'),
                log_root: File.join(Dir.home, 'Library', 'Logs', 'Aspera_Connect'),
                run_root: File.join(Dir.home, 'Library', 'Application Support', 'Aspera', 'Aspera Connect'),
                sub_bin:  File.join('Contents', 'Resources')
              }, {
                expected: CLI_V1,
                app_root: File.join(Dir.home, 'Applications', 'Aspera CLI'),
                log_root: File.join(Dir.home, 'Library', 'Logs', 'Aspera')
              }, {
                expected: HSTS,
                app_root: File.join('', 'Library', 'Aspera'),
                log_root: File.join(Dir.home, 'Library', 'Logs', 'Aspera')
              }, {
                expected: DRIVE,
                app_root: File.join('', 'Applications', 'Aspera Drive.app'),
                log_root: File.join(Dir.home, 'Library', 'Logs', 'Aspera_Drive'),
                sub_bin:  File.join('Contents', 'Resources')
              }, {
                expected: ASPERA,
                app_root: File.join('', 'Applications', 'IBM Aspera.app'),
                log_root: File.join(Dir.home, 'Library', 'Logs', 'IBM Aspera'),
                sub_bin:  File.join('Contents', 'Resources', 'sdk', 'aspera', 'bin')
              }]
              else [{ # other: Linux and Unix family
                expected: CONNECT,
                app_root: File.join(Dir.home, '.aspera', 'connect'),
                run_root: File.join(Dir.home, '.aspera', 'connect')
              }, {
                expected: CLI_V1,
                app_root: File.join(Dir.home, '.aspera', 'cli')
              }, {
                expected: HSTS,
                app_root: File.join('', 'opt', 'aspera')
              }]
              end
            result # .each {|item| item.deep_do {|h, _k, _v, _m|h.freeze}}.freeze
          end

          # @return the list of installed products in format of product_locations_on_current_os
          def installed_products
            if @@found_products.nil?
              scan_locations = product_locations_on_current_os.clone
              # add SDK as first search path
              scan_locations.unshift({
                expected: 'SDK',
                app_root: Installation.instance.sdk_folder,
                sub_bin:  ''
              })
              # search installed products: with ascp
              @@found_products = scan_locations.select! do |item| # rubocop:disable Style/ClassVars
                # skip if not main folder
                next false unless Dir.exist?(item[:app_root])
                Log.log.debug{"Found #{item[:app_root]}"}
                sub_bin = item[:sub_bin] || BIN_SUBFOLDER
                item[:ascp_path] = File.join(item[:app_root], sub_bin, ascp_filename)
                # skip if no ascp
                next false unless File.exist?(item[:ascp_path])
                # read info from product info file if present
                product_info_file = "#{item[:app_root]}/#{INFO_META_FILE}"
                if File.exist?(product_info_file)
                  res_s = XmlSimple.xml_in(File.read(product_info_file), {'ForceArray' => false})
                  item[:name] = res_s['name']
                  item[:version] = res_s['version']
                else
                  item[:name] = item[:expected]
                end
                true # select this version
              end
            end
            return @@found_products
          end

          # filename for ascp with optional extension (Windows)
          def ascp_filename
            return 'ascp' + Environment.exe_extension
          end

          # @return folder paths for specified applications
          # @param name Connect or CLI
          def folders(name)
            found = Products.installed_products.select{|i|i[:expected].eql?(name) || i[:name].eql?(name)}
            raise "Product: #{name} not found, please install." if found.empty?
            return found.first
          end

          # @return the file path of local connect where API's URI can be read
          def connect_uri
            connect = folders(CONNECT)
            folder = File.join(connect[:run_root], VAR_RUN_SUBFOLDER)
            ['', 's'].each do |ext|
              uri_file = File.join(folder, "http#{ext}.uri")
              Log.log.debug{"checking connect port file: #{uri_file}"}
              if File.exist?(uri_file)
                return File.open(uri_file, &:gets).strip
              end
            end
            raise "no connect uri file found in #{folder}"
          end

          # @ return path to configuration file of aspera CLI
          # def cli_conf_file
          #  connect = folders(PRODUCT_CLI_V1)
          #  return File.join(connect[:app_root], BIN_SUBFOLDER, '.aspera_cli_conf')
          # end
        end
      end
    end
  end
end
