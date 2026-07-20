# frozen_string_literal: true

require 'aspera/cli/version'
require 'aspera/cli/info'
require 'aspera/environment'
require 'aspera/persistency_action_once'
require 'aspera/rest'
require 'aspera/log'
require 'date'

module Aspera
  module Cli
    # Mixin providing gem version-check functionality to Plugin::Config.
    # Depends on `options` and `persistency` being available in the including class.
    module GemChecker
      GEM_CHECK_DATE_FMT = '%Y/%m/%d'

      # @return [Hash] current vs latest gem version info
      def check_gem_version
        latest_version =
          begin
            Rest.new(base_url: 'https://rubygems.org/api/v1').read("versions/#{Info::GEM_NAME}/latest.json")['version']
          rescue StandardError
            Log.log.warn('Could not retrieve latest gem version on rubygems.')
            '0'
          end
        if Gem::Version.new(Environment.ruby_version) < Gem::Version.new(Info::RUBY_FUTURE_MINIMUM_VERSION)
          Log.log.warn do
            "Note that a future version will require Ruby version #{Info::RUBY_FUTURE_MINIMUM_VERSION} at minimum, " \
              "you are using #{Environment.ruby_version}"
          end
        end
        return {
          name:        Info::GEM_NAME,
          current:     Cli::VERSION,
          latest:      latest_version,
          need_update: Gem::Version.new(Cli::VERSION) < Gem::Version.new(latest_version)
        }
      end

      # Check periodically if a newer gem version is available; log a warning if so.
      # Called once per run by Runner, before command execution.
      def periodic_check_newer_gem_version
        delay_days = options.get_option(:version_check_days, mandatory: true).to_i
        return if delay_days.eql?(0)
        last_check_array = []
        check_date_persist = PersistencyActionOnce.new(
          manager: persistency,
          data:    last_check_array,
          id:      'version_last_check'
        )
        current_date = Date.today
        last_check_days = (current_date - Date.strptime(last_check_array.first, GEM_CHECK_DATE_FMT)) rescue nil
        Log.log.debug{"gem check new version: #{delay_days}, #{last_check_days}, #{current_date}, #{last_check_array}"}
        return if !last_check_days.nil? && last_check_days < delay_days
        last_check_array[0] = current_date.strftime(GEM_CHECK_DATE_FMT)
        check_date_persist.save
        check_data = check_gem_version
        Log.log.warn do
          "A new version is available: #{check_data[:latest]}. You have #{check_data[:current]}. Upgrade with: gem update #{check_data[:name]}"
        end if check_data[:need_update]
      end
    end
  end
end
