# frozen_string_literal: true

require 'aspera/cli/plugins/base'
require 'aspera/rest'
require 'aspera/api/httpgw'
require 'aspera/nagios'

module Aspera
  module Cli
    module Plugins
      class Httpgw < Base
        application_name 'HTTP Gateway'

        class << self
          # @return [Hash,NilClass]
          def detect(base_url)
            api = Api::Httpgw.new(url: base_url)
            api_info = api.info
            return {
              url:     api.base_url,
              version: api_info['version']
            } if api_info.is_a?(Hash) && api_info.key?('download_endpoint')
            return
          end
        end

        # @param wizard  [Wizard] The wizard object
        # @param app_url [String] Tested URL
        # @return [Hash] :preset_value, :test_args
        def wizard(wizard, app_url)
          return {
            preset_value: {
              url: app_url
            },
            test_args:    'info'
          }
        end

        command(:health, description: 'Check health of HTTP Gateway', handler: lambda do
          nagios = Nagios.new
          begin
            Api::Httpgw.new(url: options.get_option(:url, mandatory: true))
            nagios.add_ok('api', 'answered ok')
          rescue StandardError => e
            nagios.add_critical('api', e.to_s)
          end
          Result::ObjectList.new(nagios.status_list)
        end)

        command(:info, description: 'Show HTTP Gateway information', handler: lambda do
          Result::SingleObject.new(Api::Httpgw.new(url: options.get_option(:url, mandatory: true)).info)
        end)

        option :url, 'URL of application, e.g. https://app.example.com/aspera/app'

        def initialize(**_)
          super
          options.parse_options!
        end
      end
    end
  end
end
