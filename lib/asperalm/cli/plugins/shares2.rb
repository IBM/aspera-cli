require 'asperalm/cli/plugins/node'
require 'uri'

module Asperalm
  module Cli
    module Plugins
      class Shares2 < BasicAuthPlugin
        alias super_declare_options declare_options
        def declare_options
          super_declare_options
          Main.instance.options.add_opt_simple(:organization,"organization")
          Main.instance.options.add_opt_simple(:project,"project")
          Main.instance.options.add_opt_simple(:share,"share")
        end

        def action_list; [ :repository,:organization,:project,:team,:share,:appinfo,:userinfo];end

        def init_apis
          # get parameters
          shares2_api_base_url=Main.instance.options.get_option(:url,:mandatory)
          shares2_username=Main.instance.options.get_option(:username,:mandatory)
          shares2_password=Main.instance.options.get_option(:password,:mandatory)

          # create object for REST calls to Shares2
          @api_shares2_admin=Rest.new({
            :base_url             => shares2_api_base_url,
            :auth_type            => :oauth2,
            :oauth_base_url       => shares2_api_base_url+'/oauth2',
            :oauth_path_token     => 'token',
            :oauth_type           => :header_userpass,
            :oauth_user_name      => shares2_username,
            :oauth_user_pass      => shares2_password,
            :oauth_scope          => 'admin'
          })

          @api_shares_node=Rest.new({
            :base_url       => shares2_api_base_url+'/node_api',
            :auth_type      => :basic,
            :basic_username => shares2_username,
            :basic_password => shares2_password})
        end

        # path_prefix is either "" or "res/id/"
        # adds : prefix+"res/id/"
        # modify parameter string
        def set_resource_path_by_id_or_name(resource_path,resource_sym)
          res_id=Main.instance.options.get_option(resource_sym,:mandatory)
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
          command=Main.instance.options.get_next_argument('command',operations)
          case command
          when :create
            params=Main.instance.options.get_next_argument("creation data (json structure)")
            resp=@api_shares2_admin.create(resource_path,params)
            return {:data=>resp[:data],:type => :other_struct}
          when :list
            default_fields=['id','name']
            query=Main.instance.options.get_option(:query,:optional)
            args=query.nil? ? nil : {'json_query'=>query}
            Log.log.debug("#{args}".bg_red)
            return {:data=>@api_shares2_admin.read(resource_path,args)[:data],:fields=>default_fields,:type=>:object_list}
          when :delete
            @api_shares2_admin.delete(set_resource_path_by_id_or_name(path_prefix,resource_sym))
            return Plugin.result_status('deleted')
          when :info
            return {:type=>:other_struct,:data=>@api_shares2_admin.read(set_resource_path_by_id_or_name(path_prefix,resource_sym),args)[:data]}
          else raise :ERROR
          end
        end

        def execute_action
          init_apis

          command=Main.instance.options.get_next_argument('command',action_list)
          case command
          when :repository
            command=Main.instance.options.get_next_argument('command',Node.common_actions)
            return Node.new.execute_common(command,@api_shares_node)
          when :appinfo
            node_info=@api_shares_node.call({:operation=>'GET',:subpath=>'app',:headers=>{'Accept'=>'application/json','Content-Type'=>'application/json'}})[:data]
            return { :type=>:single_object ,:data => node_info }
          when :userinfo
            node_info=@api_shares_node.call({:operation=>'GET',:subpath=>'current_user',:headers=>{'Accept'=>'application/json','Content-Type'=>'application/json'}})[:data]
            return { :type=>:single_object ,:data => node_info }
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
