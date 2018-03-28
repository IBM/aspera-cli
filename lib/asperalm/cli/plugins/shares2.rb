#require 'asperalm/cli/basic_auth_plugin'
require 'asperalm/cli/plugins/node'
require 'asperalm/oauth'
require 'uri'

module Asperalm
  module Cli
    module Plugins
      class Shares2 < BasicAuthPlugin
        alias super_declare_options declare_options
        def declare_options
          super_declare_options
          Main.tool.options.add_opt_simple(:organization,"organization")
          Main.tool.options.add_opt_simple(:project,"project")
          Main.tool.options.add_opt_simple(:share,"share")
        end

        def action_list; [ :repository,:organization,:project,:team,:share,:appinfo,:userinfo];end

        def init_apis
          # get parameters
          shares2_api_base_url=Main.tool.options.get_option(:url,:mandatory)
          shares2_username=Main.tool.options.get_option(:username,:mandatory)
          shares2_password=Main.tool.options.get_option(:password,:mandatory)
          # auth API
          @api_shares2_oauth=Oauth.new({
            :baseurl            => shares2_api_base_url,
            :authorize_path     => "oauth2/authorize",
            :token_path         => "oauth2/token",
            :persist_folder     => Main.tool.config_folder,
            :type               => :basic,
            :basic_type         => :header,
            :username           => shares2_username,
            :password           => shares2_password
          })

          # create object for REST calls to Shares2
          @api_shares2_admin=Rest.new(shares2_api_base_url,{:auth=>{:type=>:oauth2,:obj=>@api_shares2_oauth,:scope=>'admin'}})

          @api_shares_node=Rest.new(shares2_api_base_url+'/node_api',{:auth=>{:type=>:basic,:username=>shares2_username, :password=>shares2_password}})
        end

        # path_prefix is either "" or "res/id/"
        # adds : prefix+"res/id/"
        # modify parameter string
        def set_resource_path_by_id_or_name(resource_path,resource_sym)
          res_id=Main.tool.options.get_option(resource_sym,:mandatory)
          # lets get the class path
          resource_path<<resource_sym.to_s+'s'
          # is this an integer ? or a name
          if res_id.to_i.to_s != res_id
            all=@api_shares2_admin.read(resource_path)[:data]
            one=all.select{|i|i['name'].start_with?(res_id)}
            Log.log.debug(one)
            raise CliBadArgument,"No matching name for #{res_id} in #{all}" if one.empty?
            raise CliBadArgument,"More than one match: #{one}" if one.length > 1
            res_id=one.first['id'].to_s
          end
          Log.log.debug("res_id=#{res_id}")
          resource_path<<'/'+res_id+'/'
          return resource_path
        end

        # path_prefix is empty or ends with slash
        def process_entity_action(resource_sym,path_prefix)
          resource_path=path_prefix+resource_sym.to_s+'s'
          operations=[:list,:create,:delete]
          command=Main.tool.options.get_next_argument('command',operations)
          case command
          when :create
            params=Main.tool.options.get_next_argument("creation data (json structure)")
            resp=@api_shares2_admin.create(resource_path,params)
            return {:data=>resp[:data],:type => :other_struct}
          when :list
            default_fields=['id','name']
            query=Main.tool.options.get_option(:query,:optional)
            args=query.nil? ? nil : {'json_query'=>query}
            Log.log.debug("#{args}".bg_red)
            return {:data=>@api_shares2_admin.read(resource_path,args)[:data],:fields=>default_fields,:type=>:hash_array}
          when :delete
            @api_shares2_admin.delete(set_resource_path_by_id_or_name(path_prefix,resource_sym))
            return Main.result_status('deleted')
          when :info
            return {:type=>:other_struct,:data=>@api_shares2_admin.read(set_resource_path_by_id_or_name(path_prefix,resource_sym),args)[:data]}
          else raise :ERROR
          end
        end

        def execute_action
          init_apis

          command=Main.tool.options.get_next_argument('command',action_list)
          case command
          when :repository
            command=Main.tool.options.get_next_argument('command',Node.common_actions)
            return Node.execute_common(command,@api_shares_node)
          when :appinfo
            node_info=@api_shares_node.call({:operation=>'GET',:subpath=>'app',:headers=>{'Accept'=>'application/json','Content-Type'=>'application/json'}})[:data]
            return { :type=>:key_val_list ,:data => node_info }
          when :userinfo
            node_info=@api_shares_node.call({:operation=>'GET',:subpath=>'current_user',:headers=>{'Accept'=>'application/json','Content-Type'=>'application/json'}})[:data]
            return { :type=>:key_val_list ,:data => node_info }
          when :organization,:project,:share,:team
            prefix=''
            set_resource_path_by_id_or_name(prefix,:organization) if [:project,:team,:share].include?(command)
            set_resource_path_by_id_or_name(prefix,:project) if [:share].include?(command)
            process_entity_action(command,prefix)
          end # command
        end # execute_action
      end # Files
    end # Plugins
  end # Cli
end # Asperalm
