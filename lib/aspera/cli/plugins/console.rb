# frozen_string_literal: true

require 'aspera/cli/basic_auth_plugin'
require 'aspera/nagios'

module Aspera
  module Cli
    module Plugins
      class Console < BasicAuthPlugin
        DEFAULT_FILTER_AGE_SECONDS = 3 * 3600
        private_constant :DEFAULT_FILTER_AGE_SECONDS
        def initialize(env)
          super(env)
          options.add_opt_date(:filter_from,'only after date')
          options.add_opt_date(:filter_to,'only before date')
          time_now = Time.now
          options.set_option(:filter_from,Manager.time_to_string(time_now - DEFAULT_FILTER_AGE_SECONDS))
          options.set_option(:filter_to,Manager.time_to_string(time_now))
          options.parse_options!
        end

        ACTIONS = %i[transfer health].freeze

        def execute_action
          api_console = basic_auth_api('api')
          command = options.get_next_command(ACTIONS)
          case command
          when :health
            nagios = Nagios.new
            begin
              api_console.read('ssh_keys')
              nagios.add_ok('console api','accessible')
            rescue StandardError => e
              nagios.add_critical('console api',e.to_s)
            end
            return nagios.result
          when :transfer
            command = options.get_next_command(%i[current smart])
            case command
            when :smart
              command = options.get_next_command(%i[list submit])
              case command
              when :list
                return {type: :object_list,data: api_console.read('smart_transfers')[:data]}
              when :submit
                smart_id = options.get_next_argument('smart_id')
                params = options.get_next_argument('transfer parameters')
                return {type: :object_list,data: api_console.create('smart_transfers/' + smart_id,params)[:data]}
              end
            when :current
              command = options.get_next_command([:list])
              case command
              when :list
                return {
                  type:   :object_list,
                  data:   api_console.read('transfers',{
                    'from' => options.get_option(:filter_from,is_type: :mandatory),
                    'to'   => options.get_option(:filter_to,is_type: :mandatory)
                  })[:data],
                  fields: %w[id contact name status]}
              end
            end
          end
        end
      end # Console
    end # Plugins
  end # Cli
end # Aspera
