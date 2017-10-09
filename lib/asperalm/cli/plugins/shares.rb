require 'asperalm/cli/main'
require 'asperalm/cli/plugins/node'

module Asperalm
  module Cli
    module Plugins
      class Shares < BasicAuthPlugin
        alias super_declare_options declare_options
        def declare_options
          super_declare_options
        end

        def action_list; [ :repository,:admin ];end

        def execute_action
          command=Main.tool.options.get_next_arg_from_list('command',action_list)
          case command
          when :repository
            api_shares_node=Rest.new(Main.tool.options.get_option_mandatory(:url)+'/node_api',{:auth=>{:type=>:basic,:username=>Main.tool.options.get_option_mandatory(:username), :password=>Main.tool.options.get_option_mandatory(:password)}})
            command=Main.tool.options.get_next_arg_from_list('command',Node.common_actions)
            case command
            when *Node.common_actions; return Node.execute_common(command,api_shares_node)
            else raise "INTERNAL ERROR, unknown command: [#{command}]"
            end
          when :admin
            api_shares_admin=Rest.new(Main.tool.options.get_option_mandatory(:url)+'/api/v1',{:auth=>{:type=>:basic,:username=>Main.tool.options.get_option_mandatory(:username), :password=>Main.tool.options.get_option_mandatory(:password)}})
            command=Main.tool.options.get_next_arg_from_list('command',[:user,:share])
            case command
            when :user
              command=Main.tool.options.get_next_arg_from_list('command',[:list,:id])
              case command
              when :list
                return {:type=>:hash_array,:data=>api_shares_admin.read('data/users')[:data],:fields=>['username','email','directory_user','urn']}
              when :id
                res_id=Main.tool.options.get_next_arg_value('user id')
                command=Main.tool.options.get_next_arg_from_list('command',[:app_authorizations,:authorize_share])
                case command
                when :app_authorizations
                  return {:type=>:key_val_list,:data=>api_shares_admin.read("data/users/#{res_id}/app_authorizations")[:data]}
                when :share
                  share_name=Main.tool.options.get_next_arg_value('share name')
                  all_shares=api_shares_admin.read('data/shares')[:data]
                  share_id=all_shares.select{|s| s['name'].eql?(share_name)}.first['id']
                  return {:type=>:key_val_list,:data=>api_shares_admin.create("data/shares/#{share_id}/user_permissions")[:data]}
                end
              end
            when :share
              command=Main.tool.options.get_next_arg_from_list('command',[:list,:name])
              all_shares=api_shares_admin.read('data/shares')[:data]
              case command
              when :list
                return {:type=>:hash_array,:data=>all_shares,:fields=>['id','name','status','status_message']}
              when :name
                share_name=Main.tool.options.get_next_arg_value('share name')
                share_id=all_shares.select{|s| s['name'].eql?(share_name)}.first['id']
                raise "TODO"
              end
            end
          end
        end # execute action
      end # Shares
    end # Plugins
  end # Cli
end # Asperalm
