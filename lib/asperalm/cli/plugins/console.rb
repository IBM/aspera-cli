require 'asperalm/cli/basic_auth_plugin'

module Asperalm
  module Cli
    module Plugins
      class Console < BasicAuthPlugin
        alias super_declare_options declare_options
        def declare_options
          super_declare_options
          self.options.add_opt_date(:filter_from,"only after date")
          self.options.add_opt_date(:filter_to,"only before date")
          self.options.set_option(:filter_from,Manager.time_to_string(Time.now - 3*3600))
          self.options.set_option(:filter_to,Manager.time_to_string(Time.now))
        end

        def action_list; [:transfer];end

        def execute_action
          api_console=basic_auth_api('api')
          command=self.options.get_next_command(action_list)
          case command
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
end # Asperalm
