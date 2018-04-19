require 'asperalm/cli/basic_auth_plugin'

module Asperalm
  module Cli
    module Plugins
      class Console < BasicAuthPlugin
        alias super_declare_options declare_options
        def declare_options
          super_declare_options
          @optmgr.add_opt_date(:filter_from,"only after date")
          @optmgr.add_opt_date(:filter_to,"only before date")
          @optmgr.set_option(:filter_from,Manager.time_to_string(Time.now - 3*3600))
          @optmgr.set_option(:filter_to,Manager.time_to_string(Time.now))
        end

        def action_list; [:transfer];end

        def execute_action
          api_console=basic_auth_api('api')
          #api_console=Rest.new(@optmgr.get_option(:url,:mandatory)+'/api',{:auth=>{:type=>:basic,:username=>@optmgr.get_option(:username,:mandatory), :password=>@optmgr.get_option(:password,:mandatory)}})
          command=@optmgr.get_next_argument('command',action_list)
          case command
          when :transfer
            command=@optmgr.get_next_argument('command',[ :current, :smart ])
            case command
            when :smart
              command=@optmgr.get_next_argument('command',[:list,:submit])
              case command
              when :list
                return {:type=>:hash_array,:data=>api_console.read('smart_transfers')[:data]}
              when :submit
                smart_id = @optmgr.get_next_argument("smart_id")
                params = @optmgr.get_next_argument("transfer parameters")
                return {:type=>:hash_array,:data=>api_console.create('smart_transfers/'+smart_id,params)[:data]}
              end
            when :current
              command=@optmgr.get_next_argument('command',[ :list ])
              case command
              when :list
                return {:type=>:hash_array,
                  :data=>api_console.read('transfers',{
                  'from'=>@optmgr.get_option(:filter_from,:mandatory),
                  'to'=>@optmgr.get_option(:filter_to,:mandatory)
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
