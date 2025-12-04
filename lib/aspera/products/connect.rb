# frozen_string_literal: true

require 'aspera/environment'
require 'singleton'

module Aspera
  module Products
    class Connect
      include Singleton

      APP_NAME = 'IBM Aspera Connect'

      class << self
        # standard folder locations
        def locations
          case Aspera::Environment.instance.os
          when Aspera::Environment::OS_WINDOWS then [{
            app_root: File.join(ENV.fetch('LOCALAPPDATA', nil), 'Programs', 'Aspera', 'Aspera Connect'),
            log_root: File.join(ENV.fetch('LOCALAPPDATA', nil), 'Aspera', 'Aspera Connect', 'var', 'log'),
            run_root: File.join(ENV.fetch('LOCALAPPDATA', nil), 'Aspera', 'Aspera Connect')
          }]
          when Aspera::Environment::OS_MACOS then [{
            app_root: File.join(Dir.home, 'Applications', 'Aspera Connect.app'),
            log_root: File.join(Dir.home, 'Library', 'Logs', 'Aspera_Connect'),
            run_root: File.join(Dir.home, 'Library', 'Application Support', 'Aspera', 'Aspera Connect'),
            sub_bin:  File.join('Contents', 'Resources')
          }, {
            app_root: File.join('', 'Applications', 'Aspera Connect.app'),
            log_root: File.join(Dir.home, 'Library', 'Logs', 'Aspera_Connect'),
            run_root: File.join(Dir.home, 'Library', 'Application Support', 'Aspera', 'Aspera Connect'),
            sub_bin:  File.join('Contents', 'Resources')
          }, {
            app_root: File.join(Dir.home, 'Applications', 'IBM Aspera Connect.app'),
            log_root: File.join(Dir.home, 'Library', 'Logs', 'Aspera_Connect'),
            run_root: File.join(Dir.home, 'Library', 'Application Support', 'Aspera', 'Aspera Connect'),
            sub_bin:  File.join('Contents', 'Resources')
          }, {
            app_root: File.join('', 'Applications', 'IBM Aspera Connect.app'),
            log_root: File.join(Dir.home, 'Library', 'Logs', 'Aspera_Connect'),
            run_root: File.join(Dir.home, 'Library', 'Application Support', 'Aspera', 'Aspera Connect'),
            sub_bin:  File.join('Contents', 'Resources')
          }]
          else [{ # other: Linux and Unix family
            app_root: File.join(Dir.home, '.aspera', 'connect'),
            run_root: File.join(Dir.home, '.aspera', 'connect')
          }]
          end.map{ |i| i.merge({expected: APP_NAME})}
        end
      end

      # Base URL for CDN of Connect
      def cdn_api
        Rest.new(base_url: CDN_BASE_URL)
      end

      # Retrieve structure from cloud (CDN) with all versions available
      def versions
        if @connect_versions.nil?
          http = cdn_api.read(VERSION_INFO_FILE, ret: :resp)
          # get result on one line
          connect_versions_javascript = http.body.gsub(/\r?\n\s*/, '')
          Log.dump(:javascript, connect_versions_javascript)
          # get javascript object only
          found = connect_versions_javascript.match(/^.*? = (.*);/)
          raise Cli::Error, 'Problem when getting connect versions from internet' if found.nil?
          all_data = JSON.parse(found[1])
          @connect_versions = all_data['entries']
        end
        return @connect_versions
      end

      private

      def initialize
        @connect_versions = nil
      end

      CDN_BASE_URL = 'https://d3gcli72yxqn2z.cloudfront.net/connect'
      VERSION_INFO_FILE = 'connectversions.js' # cspell: disable-line

      private_constant :CDN_BASE_URL, :VERSION_INFO_FILE
    end
  end
end
