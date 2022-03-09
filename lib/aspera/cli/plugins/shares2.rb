# frozen_string_literal: true
require 'aspera/cli/plugins/node'
require 'uri'

module Aspera
  module Cli
    module Plugins
      class Shares2 < BasicAuthPlugin
        def initialize(env)
          super(env)
          options.add_opt_simple(:organization,'organization')
          options.add_opt_simple(:project,'project')
          options.add_opt_simple(:share,'share')
          options.parse_options!
          return if env[:man_only]
          # get parameters
          shares2_api_base_url=options.get_option(:url,:mandatory)
          shares2_username=options.get_option(:username,:mandatory)
          shares2_password=options.get_option(:password,:mandatory)

          # create object for REST calls to Shares2
          @api_shares2_oauth=Rest.new({
            base_url:  shares2_api_base_url,
            auth:      {
            type:       :oauth2,
            base_url:   shares2_api_base_url+'/oauth2',
            grant:      :header_userpass,
            user_name:  shares2_username,
            user_pass:  shares2_password
            }})

          @api_node=Rest.new({
            base_url:  shares2_api_base_url+'/node_api',
            auth:      {
            type:      :basic,
            username:  shares2_username,
            password:  shares2_password}})
        end

        # path_prefix is either "" or "res/id/"
        # adds : prefix+"res/id/"
        # modify parameter string
        def set_resource_path_by_id_or_name(resource_path,resource_sym)
          res_id=options.get_option(resource_sym,:mandatory)
          # lets get the class path
          resource_path<<"#{resource_sym}s"
          # is this an integer ? or a name
          if res_id.to_i.to_s != res_id
            all=@api_shares2_oauth.read(resource_path)[:data]
            one=all.select{|i|i['name'].start_with?(res_id)}
            Log.log.debug(one)
            raise CliBadArgument,"No matching name for #{res_id} in #{all}" if one.empty?
            raise CliBadArgument,"More than one match: #{one}" if one.length > 1
            res_id=one.first['id'].to_s
          end
          Log.log.debug("res_id=#{res_id}")
          resource_path<<"/#{res_id}/"
          return resource_path
        end

        # path_prefix is empty or ends with slash
        def process_entity_action(resource_sym,path_prefix)
          resource_path=path_prefix+resource_sym.to_s+'s'
          operations=[:list,:create,:delete]
          command=options.get_next_command(operations)
          case command
          when :create
            params=options.get_next_argument('creation data (json structure)')
            resp=@api_shares2_oauth.create(resource_path,params)
            return {data: resp[:data],type: :other_struct}
          when :list
            default_fields=['id','name']
            query=options.get_option(:query,:optional)
            args=query.nil? ? nil : {'json_query'=>query}
            Log.log.debug(args.to_s.bg_red)
            return {data: @api_shares2_oauth.read(resource_path,args)[:data],fields: default_fields,type: :object_list}
          when :delete
            @api_shares2_oauth.delete(set_resource_path_by_id_or_name(path_prefix,resource_sym))
            return Main.result_status('deleted')
          when :info
            return {type: :other_struct,data: @api_shares2_oauth.read(set_resource_path_by_id_or_name(path_prefix,resource_sym),args)[:data]}
          else raise :ERROR
          end
        end

        ACTIONS=[:repository,:organization,:project,:team,:share,:appinfo,:userinfo,:admin]

        def execute_action
          command=options.get_next_command(ACTIONS)
          case command
          when :repository
            command=options.get_next_command(Node::COMMON_ACTIONS)
            return Node.new(@agents.merge(skip_basic_auth_options: true, node_api: @api_node)).execute_action(command)
          when :appinfo
            node_info=@api_node.call({operation: 'GET',subpath: 'app',headers: {'Accept'=>'application/json','Content-Type'=>'application/json'}})[:data]
            return { type: :single_object,data:  node_info }
          when :userinfo
            node_info=@api_node.call({operation: 'GET',subpath: 'current_user',headers: {'Accept'=>'application/json','Content-Type'=>'application/json'}})[:data]
            return { type: :single_object,data:  node_info }
          when :organization,:project,:share,:team
            prefix=''
            set_resource_path_by_id_or_name(prefix,:organization) if [:project,:team,:share].include?(command)
            set_resource_path_by_id_or_name(prefix,:project) if [:share].include?(command)
            process_entity_action(command,prefix)
          when :admin
            command=options.get_next_command([:users,:groups,:nodes])
            return entity_action(@api_shares2_oauth,"system/#{command}")
          end # command
        end # execute_action
      end # Files
    end # Plugins
  end # Cli
end # Aspera
