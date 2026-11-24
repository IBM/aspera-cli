# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../environment'
require_relative '../log'
require_relative '../products/desktop'
require_relative '../products/transferd'
require_relative 'log_analyzer'
require 'json'
require 'set'
require 'xmlsimple'

module Aspera
  module Ascp
    # Location of the `ascp` log files of the local system.
    # `ascp` logs in the folder of option `-L` (set by Connect, transferd, IBM Aspera for Desktop),
    # else in `<logging><directory>` of `aspera.conf`, else in a default location that depends on the OS:
    # syslog on Linux and Unix, `~/Library/Logs/Aspera` on macOS, `var\log` of the product (or folder of `ascp`) on Windows.
    module LogLocations
      # Linux and Unix: `ascp` logs to syslog (facility `local2`), in one of these files depending on the syslog configuration
      SYSLOG_FILES = %w[/var/log/aspera.log /var/log/messages /var/log/syslog].freeze
      # Log location of `ascp` on Linux and Unix without `-L` nor `<logging><directory>`
      SYSLOG = 'syslog'
      # Source of a location that is not specific to a product
      DEFAULT_SOURCE = 'ascp default'
      # Source of a location given by an `ascp` found in `PATH`, but not in the locations of known products
      PATH_SOURCE = 'ascp in PATH'
      # Names of the log files written by `ascp` in a folder (`-L` or `aspera.conf`): current file, rotations, compressed
      ASCP_FILE = /\A(?:aspera-scp-transfer|ascp4?)(?:\.\d+)?\.log(?:\.gz)?\z/
      class << self
        # @param products [Array<Hash>] installed products, see `Installation#installed_products`
        # @param defaults [Array<Array>] default locations: `[path, source]`
        # @return [Array<Hash>] files that contain `ascp` log lines: `path`, `size`, `modified`, `source`, most recent first
        def find(products, defaults: default_locations)
          seen = Set.new
          # Default locations first: they are shared by products (e.g. `~/Library/Logs/Aspera`)
          locations = defaults + (products + path_products(products)).flat_map { |product| product_locations(product) }
          files = locations.flat_map { |location, source| location_files(location).map { |file| [file, source] } }
          files.filter_map do |file, source|
            stat = File.stat(file)
            # Same file in several locations, or `<name>.log` hard link to `<name>.<n>.log`
            next unless seen.add?(stat.ino.zero? ? File.expand_path(file) : [stat.dev, stat.ino])
            next unless LogAnalyzer.ascp_log?(file)
            {'path' => file, 'size' => stat.size, 'modified' => stat.mtime, 'source' => source}
          end.sort_by { |row| -row['modified'].to_f }
        end

        # @return [Array<Array>] locations not specific to an installed product: `[path, source]`
        def default_locations
          locations = case Environment.instance.os
          when Environment::OS_WINDOWS then []
          when Environment::OS_MACOS then [File.join(Dir.home, 'Library', 'Logs', 'Aspera'), File.join('', 'Library', 'Logs', 'Aspera')]
          else SYSLOG_FILES
          end.map { |path| [path, DEFAULT_SOURCE] }
          desktop = Products::Desktop.log_folder
          locations.push([desktop, Products::Desktop::APP_NAME]) unless desktop.nil?
          service = transferd_service_log_folder
          locations.push([service, 'transferd service']) unless service.nil?
          locations
        end

        # Location of the log of `ascp` when it runs without option `-L`
        # @param ascp      [String]      path of `ascp`
        # @param root      [String, nil] root folder of the product, as reported by `ascp` (Windows)
        # @param conf_file [String, nil] `aspera.conf` used by `ascp`
        # @return [String] log folder, or `syslog` (Linux and Unix)
        def ascp_log_location(ascp, root: nil, conf_file: nil)
          folder = conf_directory(conf_file)
          return folder unless folder.nil?
          case Environment.instance.os
          when Environment::OS_MACOS
            File.join(Dir.home.start_with?('/var/root') ? '' : Dir.home, 'Library', 'Logs', 'Aspera')
          when Environment::OS_WINDOWS
            var_log = File.join(root || File.dirname(File.dirname(ascp)), 'var', 'log')
            File.directory?(var_log) ? var_log : File.dirname(ascp)
          else SYSLOG
          end
        end

        private

        # @param products [Array<Hash>] installed products
        # @return [Array<Hash>] products for the `ascp` found in `PATH` that are not one of `products`
        def path_products(products)
          known = products.filter_map { |product| real_path(product[:ascp_path]) }
          ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).filter_map do |folder|
            ascp = real_path(File.join(folder, Environment.instance.exe_file('ascp')))
            next if ascp.nil? || known.include?(ascp)
            known.push(ascp)
            bin = File.dirname(ascp)
            {name: PATH_SOURCE, ascp_path: ascp, app_root: File.basename(bin).eql?('bin') ? File.dirname(bin) : bin}
          end
        end

        # @param product [Hash] installed product
        # @return [Array<Array>] locations of logs of the product: `[path, source]`
        def product_locations(product)
          locations = [product[:log_root], conf_log_folder(product), File.join(product[:app_root], 'var', 'log')]
          # Windows: without `var\log`, `ascp` logs in its own folder
          locations.push(File.dirname(product[:ascp_path])) if Environment.instance.os.eql?(Environment::OS_WINDOWS)
          locations.compact.uniq.map { |path| [path, product[:name]] }
        end

        # @param product [Hash] installed product
        # @return [String, nil] `<default><logging><directory>` of `aspera.conf` of the product: in `etc`, or in the folder of `ascp` (SDK)
        def conf_log_folder(product)
          conf_directory([File.join(product[:app_root], 'etc', 'aspera.conf'), File.join(File.dirname(product[:ascp_path]), 'aspera.conf')].find { |f| File.file?(f) })
        end

        # @param conf_file [String, nil] `aspera.conf`
        # @return [String, nil] `<default><logging><directory>` of the file
        def conf_directory(conf_file)
          return if conf_file.nil? || !File.file?(conf_file)
          folder = XmlSimple.xml_in(File.read(conf_file), {'ForceArray' => false}).dig('default', 'logging', 'directory')
          folder if folder.is_a?(String) && !folder.empty?
        rescue StandardError => e
          Log.log.debug { "Cannot read #{conf_file}: #{e.message}" }
          nil
        end

        # @return [String, nil] `fasp_runtime.log.dir` (folder given to `ascp -L`) of the transferd service installed by `transferd service install`
        def transferd_service_log_folder
          file = Products::Transferd::SERVICE_CONFIG_FILE
          return unless File.file?(file) && File.readable?(file)
          folder = JSON.parse(File.read(file)).dig('fasp_runtime', 'log', 'dir')
          folder if folder.is_a?(String) && File.absolute_path?(folder)
        rescue StandardError => e
          Log.log.debug { "Cannot read transferd configuration: #{e.message}" }
          nil
        end

        # @return [Boolean] true if readable, else warn
        def readable?(location)
          return true if File.readable?(location)
          Log.log.warn { "Cannot read #{location}: permission denied" }
          false
        end

        # @return [String, nil] real path of the file, nil if it does not exist
        def real_path(file)
          File.realpath(file) if file && File.file?(file)
        end

        # @param location [String] log folder, or syslog file (with its rotations: `<file>-<date>`, `<file>.<n>`, compressed or not)
        # @return [Array<String>] readable files of the location: `ascp` log files of a folder, or syslog files
        def location_files(location)
          files = if File.directory?(location)
            return [] unless readable?(location)
            LogAnalyzer.log_paths(location).select { |file| File.basename(file).match?(ASCP_FILE) }
          else
            Dir.glob("#{location}*").select { |file| File.file?(file) }.sort
          end
          files.select { |file| readable?(file) }
        rescue SystemCallError => e
          Log.log.warn { "Cannot read #{location}: #{e.message}" }
          []
        end
      end
    end
  end
end
