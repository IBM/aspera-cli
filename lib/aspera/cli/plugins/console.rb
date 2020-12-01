require 'aspera/cli/basic_auth_plugin'
require 'aspera/nagios'

module Aspera
  module Cli
    module Plugins
      class Console < BasicAuthPlugin
        def initialize(env)
          super(env)
          self.options.add_opt_date(:filter_from,"only after date")
          self.options.add_opt_date(:filter_to,"only before date")
          self.options.set_option(:filter_from,Manager.time_to_string(Time.now - 3*3600))
          self.options.set_option(:filter_to,Manager.time_to_string(Time.now))
          self.options.parse_options!
        end

        ACTIONS=[:transfer,:nagios_check]

        def execute_action
          api_console=basic_auth_api('api')
          command=self.options.get_next_command(ACTIONS)
          case command
          when :nagios_check
            nagios=Nagios.new
            begin
              api_console.read('ssh_keys')
              nagios.add_ok('console api','accessible')
            rescue => e
              nagios.add_critical('console api',e.to_s)
            end
            return nagios.result
          when :transfer
            command=self.options.get_next_command([ :current, :smart ])
            case command
            when :smart
              command=self.options.get_next_command([:list,:submit])
              case command
              when :list
                return {:type=>:object_list,:data=>api_console.read('smart_transfers')[:data]}
              when :submit
                smart_id = self.options.get_next_argument("smart_id")
                params = self.options.get_next_argument("transfer parameters")
                return {:type=>:object_list,:data=>api_console.create('smart_transfers/'+smart_id,params)[:data]}
              end
            when :current
              command=self.options.get_next_command([ :list ])
              case command
              when :list
                return {:type=>:object_list,
                  :data=>api_console.read('transfers',{
                  'from'=>self.options.get_option(:filter_from,:mandatory),
                  'to'=>self.options.get_option(:filter_to,:mandatory)
                  })[:data],
                  :fields=>['id','contact','name','status']}
              end
            end
          end
        end
      end # Console
    end # Plugins
  end # Cli
end # Aspera
