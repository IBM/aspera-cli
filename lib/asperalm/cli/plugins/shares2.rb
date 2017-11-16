#require 'asperalm/cli/basic_auth_plugin'
require 'asperalm/cli/plugins/node'
require 'asperalm/oauth'

module Asperalm
  module Cli
    module Plugins
      class Shares2 < Plugin
        def declare_options
          Main.tool.options.add_opt_list(:auth,'TYPE',Oauth.auth_types,"type of authentication",'-tTYPE')
        end

        def action_list; [ :repository,:test];end

        def init_apis
          # get parameters
          shares2_api_base_url=Main.tool.options.get_option(:url,:mandatory)

          auth_data={
            :baseurl =>shares2_api_base_url,
            :authorize_path => "oauth2/authorize",
            :token_path => "oauth2/token",
            :persist_identifier => 'the_url_host',
            :persist_folder => Main.tool.config_folder,
            :type=>Main.tool.options.get_option(:auth,:mandatory)
            #            :client_id =>Main.tool.options.get_option(:client_id,:mandatory),
            #            :client_secret=>Main.tool.options.get_option(:client_secret,:mandatory)
          }

          case auth_data[:type]
          when :basic
            auth_data[:username]=Main.tool.options.get_option(:username,:mandatory)
            auth_data[:password]=Main.tool.options.get_option(:password,:mandatory)
            auth_data[:basic_type]=:header
            #          when :web
            #            auth_data[:redirect_uri]=Main.tool.options.get_option(:redirect_uri,:mandatory)
            #            Log.log.info("redirect_uri=#{auth_data[:redirect_uri]}")
            #          when :jwt
            #            auth_data[:private_key]=OpenSSL::PKey::RSA.new(Main.tool.options.get_option(:private_key,:mandatory))
            #            auth_data[:subject]=Main.tool.options.get_option(:username,:mandatory)
            #            Log.log.info("private_key=#{auth_data[:private_key]}")
            #            Log.log.info("subject=#{auth_data[:subject]}")
            #          when :url_token
            #            auth_data[:url_token]=Main.tool.options.get_option(:url_token,:mandatory)
          else
            raise "unknown auth type: #{auth_data[:type]}"
          end

          # auth API
          @api_shares2_oauth=Oauth.new(auth_data)

          # create object for REST calls to Files with scope "user:all"
          @api_shares2_admin=Rest.new(shares2_api_base_url,{:auth=>{:type=>:oauth2,:obj=>@api_shares2_oauth,:scope=>'admin'}})
        end

        def execute_action
          init_apis

          command=Main.tool.options.get_next_argument('command',action_list)
          case command
          when :repository
            api_shares_node=Rest.new(Main.tool.options.get_option(:url,:mandatory)+'/node_api',{:auth=>{:type=>:basic,:username=>Main.tool.options.get_option(:username,:mandatory), :password=>Main.tool.options.get_option(:password,:mandatory)}})
            command=Main.tool.options.get_next_argument('command',Node.common_actions.dup.push(:appinfo,:userinfo))
            case command
            when *Node.common_actions; return Node.execute_common(command,api_shares_node)
            when :appinfo
              node_info=api_shares_node.call({:operation=>'GET',:subpath=>'app',:headers=>{'Accept'=>'application/json'}})[:data]
              return { :type=>:other_struct ,:data => node_info }
            when :userinfo
              node_info=api_shares_node.call({:operation=>'GET',:subpath=>'current_user',:headers=>{'Accept'=>'application/json'}})[:data]
              return { :type=>:other_struct ,:data => node_info }
            else raise "INTERNAL ERROR, unknown command: [#{command}]"
            end
          when :test
            # how to get org id ?
            org_id=6
            # get our user's default information
            #self_data=@api_shares2_admin.read("organizations/#{org_id}/projects")[:data]
            self_data=@api_shares2_admin.read("organizations")[:data]
            #self_data=@api_shares2_admin.read("profile")[:data]
            #self_data=@api_shares2_admin.read("node_api/info")[:data]
            return { :type=>:hash_array, :data => self_data }
          end # command
        end # execute_action
      end # Files
    end # Plugins
  end # Cli
end # Asperalm
