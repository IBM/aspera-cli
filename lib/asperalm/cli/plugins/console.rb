require 'asperalm/cli/main'
require 'asperalm/cli/basic_auth_plugin'

module Asperalm
  module Cli
    module Plugins
      class Console < BasicAuthPlugin
        alias super_declare_options declare_options
        def declare_options
          super_declare_options
          Main.tool.options.set_option(:filter_from,Manager.time_to_string(Time.now - 3*3600))
          Main.tool.options.set_option(:filter_to,Manager.time_to_string(Time.now))
          Main.tool.options.add_opt_date(:filter_from,"DATE","only after date")
          Main.tool.options.add_opt_date(:filter_to,"DATE","only before date")
        end

        def action_list; [:transfer];end

        def execute_action
          api_console=basic_auth_api('api')
          #api_console=Rest.new(Main.tool.options.get_option(:url,:mandatory)+'/api',{:auth=>{:type=>:basic,:username=>Main.tool.options.get_option(:username,:mandatory), :password=>Main.tool.options.get_option(:password,:mandatory)}})
          command=Main.tool.options.get_next_argument('command',action_list)
          case command
          when :transfer
            command=Main.tool.options.get_next_argument('command',[ :current, :smart ])
            case command
            when :smart
              command=Main.tool.options.get_next_argument('command',[:list,:submit])
              case command
              when :list
                return {:type=>:hash_array,:data=>api_console.read('smart_transfers')[:data]}
              when :submit
                smart_id = Main.tool.options.get_next_argument("smart_id")
                params = Main.tool.options.get_next_argument("transfer parameters")
                return {:type=>:hash_array,:data=>api_console.create('smart_transfers/'+smart_id,params)[:data]}
              end
            when :current
              command=Main.tool.options.get_next_argument('command',[ :list ])
              return {:type=>:hash_array,
                :data=>api_console.read('transfers',{
                'from'=>Main.tool.options.get_option(:filter_from,:mandatory),
                'to'=>Main.tool.options.get_option(:filter_to,:mandatory)
                })[:data],
                :fields=>['id','contact','name','status']}
            end
          end
        end
      end # Console
    end # Plugins
  end # Cli
end # Asperalm
