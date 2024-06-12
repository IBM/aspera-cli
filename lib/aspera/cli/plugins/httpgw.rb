# frozen_string_literal: true

require 'aspera/rest'
require 'aspera/api/httpgw'
require 'aspera/nagios'

module Aspera
  module Cli
    module Plugins
      class Httpgw < Plugin
        class << self
          def application_name
            'HTTP Gateway'
          end

          def detect(base_url)
            api = Api::Httpgw.new(url: base_url)
            api_info = api.info
            return {
              url:     base_url,
              version: api_info['version']
            } if api_info.is_a?(Hash) && api_info.key?('download_endpoint')
            return nil
          end
        end
        ACTIONS = %i[health info].freeze

        def initialize(**env)
          super
          options.declare(:url, 'URL of application, e.g. https://app.example.com/aspera/app')
          options.parse_options!
        end

        def execute_action
          base_url = options.get_option(:url, mandatory: true)
          command = options.get_next_command(ACTIONS)
          case command
          when :health
            nagios = Nagios.new
            begin
              Api::Httpgw.new(url: base_url)
              nagios.add_ok('api', 'answered ok')
            rescue StandardError => e
              nagios.add_critical('api', e.to_s)
            end
            return nagios.result
          when :info
            api_v1 = Api::Httpgw.new(url: base_url)
            return {type: :single_object, data: api_v1.info}
          end
        end
      end
    end
  end
end
