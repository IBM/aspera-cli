require 'aspera/cli/plugins/node'

module Aspera
  module Cli
    module Plugins
      class Shares < BasicAuthPlugin
        class << self
          def detect(base_url)
            api=Rest.new({base_url: base_url})
            # Shares
            begin
              # shall fail: shares requires auth, but we check error message
              api.read('node_api/app')
            rescue RestCallError => e
              if e.response.code.to_s.eql?('401') and e.response.body.eql?('{"error":{"user_message":"API user authentication failed"}}')
                return {version: 'unknown'}
              end
            rescue
            end
            nil
          end
        end

        def initialize(env)
          super(env)
          #self.options.parse_options!
        end

        ACTIONS=[:repository,:admin]

        def execute_action
          command=options.get_next_command(ACTIONS)
          case command
          when :repository
            api_shares_node=basic_auth_api('node_api')
            command=options.get_next_command(Node::COMMON_ACTIONS)
            case command
            when *Node::COMMON_ACTIONS then Node.new(@agents.merge(skip_basic_auth_options: true,node_api: api_shares_node)).execute_action(command)
            else raise "INTERNAL ERROR, unknown command: [#{command}]"
            end
          when :admin
            api_shares_admin=basic_auth_api('api/v1')
            command=options.get_next_command([:user,:share])
            case command
            when :user
              command=options.get_next_command([:list,:id])
              case command
              when :list
                return {type: :object_list,data: api_shares_admin.read('data/users')[:data],fields: ['username','email','directory_user','urn']}
              when :id
                res_id=options.get_next_argument('user id')
                command=options.get_next_command([:app_authorizations,:authorize_share])
                case command
                when :app_authorizations
                  return {type: :single_object,data: api_shares_admin.read("data/users/#{res_id}/app_authorizations")[:data]}
                when :share
                  share_name=options.get_next_argument('share name')
                  all_shares=api_shares_admin.read('data/shares')[:data]
                  share_id=all_shares.select{|s| s['name'].eql?(share_name)}.first['id']
                  return {type: :single_object,data: api_shares_admin.create("data/shares/#{share_id}/user_permissions")[:data]}
                end
              end
            when :share
              command=options.get_next_command([:list,:name])
              all_shares=api_shares_admin.read('data/shares')[:data]
              case command
              when :list
                return {type: :object_list,data: all_shares,fields: ['id','name','status','status_message']}
              when :name
                share_name=options.get_next_argument('share name')
                share_id=all_shares.select{|s| s['name'].eql?(share_name)}.first['id']
                raise "NOT IMPLEMENTED: #{share_name} #{share_id}"
              end
            end
          end
        end # execute action
      end # Shares
    end # Plugins
  end # Cli
end # Aspera
