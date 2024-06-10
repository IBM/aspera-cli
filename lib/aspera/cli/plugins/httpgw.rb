# frozen_string_literal: true

require 'aspera/rest'
require 'aspera/api/httpgw'

module Aspera
  module Cli
    module Plugins
      class Httpgw < Plugin
        class << self
          def application_name
            'HTTP Gateway'
          end

          def detect(address_or_url)
            error = nil
            [address_or_url].each do |base_url|
              # only HTTPS
              next unless base_url.start_with?('https://')
              api = Rest.new(base_url: base_url, redirect_max: 1)
              path_api_detect = "#{API_V1}/#{Api::Httpgw::INFO_ENDPOINT}"
              result = api.read(path_api_detect)[:data]
              next unless result.is_a?(Hash) && result.key?('download_endpoint')
              # take redirect if any
              return {
                version: result['version'],
                url:     base_url
              }
            rescue StandardError => e
              error = e
              Log.log.debug{"detect error: #{e}"}
            end
            raise error if error
            return nil
          end
        end
        ACTIONS = %i[info].freeze

        def initialize(**env)
          super
          options.declare(:url, 'URL of application, e.g. https://app.example.com/aspera/app')
          options.parse_options!
        end

        def execute_action
          base_url = options.get_option(:url, mandatory: true)
          api_v1 = Api::Httpgw.new(url: base_url, api_version: Api::Httpgw::API_V1)
          command = options.get_next_command(ACTIONS)
          case command
          when :info
            return {type: :single_object, data: api_v1.read(Api::Httpgw::INFO_ENDPOINT)}
          end
        end
      end
    end
  end
end
