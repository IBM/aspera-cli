require 'asperalm/cli/plugins/node'
require 'singleton'

module Asperalm
  module Cli
    module Plugins
      class Shares < BasicAuthPlugin
        include Singleton
        alias super_declare_options declare_options
        def declare_options
          super_declare_options
        end

        def action_list; [ :repository,:admin ];end

        def execute_action
          command=Main.instance.options.get_next_command(action_list)
          case command
          when :repository
            api_shares_node=basic_auth_api('node_api')
            command=Main.instance.options.get_next_command(Node.common_actions)
            case command
            when *Node.common_actions; Node.execute_common(command,api_shares_node)
            else raise "INTERNAL ERROR, unknown command: [#{command}]"
            end
          when :admin
            api_shares_admin=basic_auth_api('api/v1')
            command=Main.instance.options.get_next_command([:user,:share])
            case command
            when :user
              command=Main.instance.options.get_next_command([:list,:id])
              case command
              when :list
                return {:type=>:object_list,:data=>api_shares_admin.read('data/users')[:data],:fields=>['username','email','directory_user','urn']}
              when :id
                res_id=Main.instance.options.get_next_argument('user id')
                command=Main.instance.options.get_next_command([:app_authorizations,:authorize_share])
                case command
                when :app_authorizations
                  return {:type=>:single_object,:data=>api_shares_admin.read("data/users/#{res_id}/app_authorizations")[:data]}
                when :share
                  share_name=Main.instance.options.get_next_argument('share name')
                  all_shares=api_shares_admin.read('data/shares')[:data]
                  share_id=all_shares.select{|s| s['name'].eql?(share_name)}.first['id']
                  return {:type=>:single_object,:data=>api_shares_admin.create("data/shares/#{share_id}/user_permissions")[:data]}
                end
              end
            when :share
              command=Main.instance.options.get_next_command([:list,:name])
              all_shares=api_shares_admin.read('data/shares')[:data]
              case command
              when :list
                return {:type=>:object_list,:data=>all_shares,:fields=>['id','name','status','status_message']}
              when :name
                share_name=Main.instance.options.get_next_argument('share name')
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
