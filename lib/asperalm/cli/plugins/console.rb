require 'asperalm/cli/basic_auth_plugin'
require 'singleton'

module Asperalm
  module Cli
    module Plugins
      class Console < BasicAuthPlugin
        include Singleton
        alias super_declare_options declare_options
        def declare_options
          super_declare_options
          Main.instance.options.add_opt_date(:filter_from,"only after date")
          Main.instance.options.add_opt_date(:filter_to,"only before date")
          Main.instance.options.set_option(:filter_from,Manager.time_to_string(Time.now - 3*3600))
          Main.instance.options.set_option(:filter_to,Manager.time_to_string(Time.now))
        end

        def action_list; [:transfer];end

        def execute_action
          api_console=basic_auth_api('api')
          command=Main.instance.options.get_next_command(action_list)
          case command
          when :transfer
            command=Main.instance.options.get_next_command([ :current, :smart ])
            case command
            when :smart
              command=Main.instance.options.get_next_command([:list,:submit])
              case command
              when :list
                return {:type=>:object_list,:data=>api_console.read('smart_transfers')[:data]}
              when :submit
                smart_id = Main.instance.options.get_next_argument("smart_id")
                params = Main.instance.options.get_next_argument("transfer parameters")
                return {:type=>:object_list,:data=>api_console.create('smart_transfers/'+smart_id,params)[:data]}
              end
            when :current
              command=Main.instance.options.get_next_command([ :list ])
              case command
              when :list
                return {:type=>:object_list,
                  :data=>api_console.read('transfers',{
                  'from'=>Main.instance.options.get_option(:filter_from,:mandatory),
                  'to'=>Main.instance.options.get_option(:filter_to,:mandatory)
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
