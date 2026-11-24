# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative 'environment'
require_relative 'log'
require 'xmlsimple'

module Aspera
  # Location of Aspera products with `ascp`: one class per product (`Products::Connect`, `Products::Hsts`...), each with `APP_NAME` and `.locations`
  module Products
    # product information manifest: XML (part of aspera product)
    INFO_META_FILE = 'product-info.mf'

    class << self
      # Find installed products and provide paths for it.
      # @param scan_locations [Array] Array of Hash with keys: expected, app_root, sub_bin, ascp_path, name, version
      #   (:expected  M app name is taken from the manifest if present, else defaults to this value;
      #   :app_root  M main folder for the application;
      #   :log_root  O location of log files (Linux uses syslog);
      #   :run_root  O only for Connect Client, location of http port file;
      #   :sub_bin   O subfolder with executables, default : bin)
      # @return [Array] of products found, with filled missing fields
      # @raise [RuntimeError] if no installed product found
      def find(scan_locations)
        product_names = []
        found = scan_locations.select do |item|
          product_names.push(item[:expected]) unless product_names.include?(item[:expected])
          # skip if not main folder
          Log.log.trace1 { "Checking #{item[:app_root]}" }
          next false unless Dir.exist?(item[:app_root])
          Log.log.debug { "Found #{item[:expected]}" }
          sub_bin = item[:sub_bin] || 'bin'
          item[:ascp_path] = File.join(item[:app_root], sub_bin, Environment.instance.exe_file('ascp'))
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
        raise "Product: #{product_names.join(', ')} not found, please install." if found.empty?
        found
      end
    end
  end
end
