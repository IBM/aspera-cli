# frozen_string_literal: true

# cspell:ignore LOCALAPPDATA
require 'aspera/environment'

module Aspera
  # Location of Aspera products, for which an Agent is not proposed
  module Products
    # other Aspera products with ascp
    class Other
      CLI_V3 = 'Aspera CLI (deprecated)'
      DRIVE = 'Aspera Drive (deprecated)'
      HSTS = 'IBM Aspera High-Speed Transfer Server'

      private_constant :CLI_V3, :DRIVE, :HSTS
      # product information manifest: XML (part of aspera product)
      INFO_META_FILE = 'product-info.mf'

      # :expected  M app name is taken from the manifest if present, else defaults to this value
      # :app_root  M main folder for the application
      # :log_root  O location of log files (Linux uses syslog)
      # :run_root  O only for Connect Client, location of http port file
      # :sub_bin   O subfolder with executables, default : bin
      LOCATION_ON_THIS_OS = case Aspera::Environment.os
      when Aspera::Environment::OS_WINDOWS then [{
        expected: CLI_V3,
        app_root: File.join('C:', 'Program Files', 'Aspera', 'cli'),
        log_root: File.join('C:', 'Program Files', 'Aspera', 'cli', 'var', 'log')
      }, {
        expected: HSTS,
        app_root: File.join('C:', 'Program Files', 'Aspera', 'Enterprise Server'),
        log_root: File.join('C:', 'Program Files', 'Aspera', 'Enterprise Server', 'var', 'log')
      }]
      when Aspera::Environment::OS_MACOS then [{
        expected: CLI_V3,
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
      }]
      else [{ # other: Linux and Unix family
        expected: CLI_V3,
        app_root: File.join(Dir.home, '.aspera', 'cli')
      }, {
        expected: HSTS,
        app_root: File.join('', 'opt', 'aspera')
      }]
      end
      class << self
        def find(scan_locations)
          scan_locations.select do |item|
            # skip if not main folder
            Log.log.trace1{"Checking #{item[:app_root]}"}
            next false unless Dir.exist?(item[:app_root])
            Log.log.debug{"Found #{item[:expected]}"}
            sub_bin = item[:sub_bin] || 'bin'
            item[:ascp_path] = File.join(item[:app_root], sub_bin, Environment.exe_file('ascp'))
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
      end
    end
  end
end
