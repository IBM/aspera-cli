require 'asperalm/cli/basic_auth_plugin'
require 'asperalm/oauth'
require 'asperalm/cli/plugins/node'

module Asperalm
  module Cli
    module Plugins
      class Shares2 < Plugin
        def declare_options
          Main.tool.options.add_opt_list(:auth,'TYPE',Oauth.auth_types,"type of authentication",'-tTYPE')
        end

        def action_list; [ :repository];end

        def execute_action
          #command=Main.tool.options.get_next_arg_from_list('command',action_list)

          # get parameters
          shares2_api_base_url=Main.tool.options.get_option_mandatory(:url)

          auth_data={
            :baseurl =>shares2_api_base_url,
            :authorize_path => "oauth2/authorize",
            :token_path => "oauth2/token",
            :persist_identifier => 'the_url_host',
            :persist_folder => Main.tool.config_folder,
            :type=>Main.tool.options.get_option_mandatory(:auth),
            :client_id =>Main.tool.options.get_option_mandatory(:client_id),
            :client_secret=>Main.tool.options.get_option_mandatory(:client_secret)
          }

          case auth_data[:type]
          when :basic
            auth_data[:username]=Main.tool.options.get_option_mandatory(:username)
            auth_data[:password]=Main.tool.options.get_option_mandatory(:password)
            auth_data[:basic_type]=:header
          when :web
            auth_data[:redirect_uri]=Main.tool.options.get_option_mandatory(:redirect_uri)
            Log.log.info("redirect_uri=#{auth_data[:redirect_uri]}")
          when :jwt
            auth_data[:private_key]=OpenSSL::PKey::RSA.new(Main.tool.options.get_option_mandatory(:private_key))
            auth_data[:subject]=Main.tool.options.get_option_mandatory(:username)
            Log.log.info("private_key=#{auth_data[:private_key]}")
            Log.log.info("subject=#{auth_data[:subject]}")
          when :url_token
            auth_data[:url_token]=Main.tool.options.get_option_mandatory(:url_token)
          else
            raise "unknown auth type: #{auth_data[:type]}"
          end

          # auth API
          @api_files_oauth=Oauth.new(auth_data)

          # create object for REST calls to Files with scope "user:all"
          @api_files_user=Rest.new(shares2_api_base_url,{:auth=>{:type=>:oauth2,:obj=>@api_files_oauth,:scope=>'admin'}})

          org_id=6

          # get our user's default information
          #self_data=@api_files_user.read("organizations/#{org_id}/projects")[:data]
          #self_data=@api_files_user.read("organizations")[:data]
          #self_data=@api_files_user.read("node_api/info")[:data]
          #return { :type=>:hash_array, :data => self_data }

          command=Main.tool.options.get_next_arg_from_list('command',action_list)
          case command
          when :repository
            api_shares_node=Rest.new(Main.tool.options.get_option_mandatory(:url)+'/node_api',{:auth=>{:type=>:basic,:username=>Main.tool.options.get_option_mandatory(:username), :password=>Main.tool.options.get_option_mandatory(:password)}})
            command=Main.tool.options.get_next_arg_from_list('command',Node.common_actions)
            case command
            when *Node.common_actions; return Node.execute_common(command,api_shares_node)
            else raise "INTERNAL ERROR, unknown command: [#{command}]"
            end
          end
        end
      end # Files
    end # Plugins
  end # Cli
end # Asperalm
