require 'asperalm/cli/basic_auth_plugin'
require 'base64'
require 'zlib'

module Asperalm
  module Cli
    module Plugins
      class Node < BasicAuthPlugin
        alias super_declare_options declare_options
        def declare_options
          super_declare_options
          Main.instance.options.add_opt_simple(:value,"extended value for create, update, list filter")
          Main.instance.options.add_opt_simple(:validator,"identifier of validator (optional for central)")
          Main.instance.options.add_opt_simple(:id,"entity identifier for update, show, and modify")
          Main.instance.options.add_opt_simple(:asperabrowserurl,"URL for simple aspera web ui")
          #Main.instance.options.set_option(:value,'@json:{"active_only":false}')
          Main.instance.options.set_option(:asperabrowserurl,'https://asperabrowser.mybluemix.net')
        end

        def self.c_textify_browse(table_data)
          return table_data.map {|i| i['permissions']=i['permissions'].map { |x| x['name'] }.join(','); i }
        end

        # key/value is defined in main in hash_table
        def self.c_textify_bool_list_result(list,name_list)
          list.each_index do |i|
            if name_list.include?(list[i]['key'])
              list[i]['value'].each do |item|
                list.push({'key'=>item['name'],'value'=>item['value']})
              end
              list.delete_at(i)
              # continue at same index because we delete current one
              redo
            end
          end
        end

        # reduce the path from a result on given named column
        def self.c_result_remove_prefix_path(result,column,path_prefix)
          if !path_prefix.nil?
            result[:data].each do |r|
              r[column].replace(r[column][path_prefix.length..-1]) if r[column].start_with?(path_prefix)
            end
          end
          return result
        end

        # translates paths results into CLI result, and removes prefix
        def self.c_result_translate_rem_prefix(resp,type,success_msg,path_prefix)
          resres={:data=>[],:type=>:object_list,:fields=>[type,'result']}
          JSON.parse(resp[:http].body)['paths'].each do |p|
            result=success_msg
            if p.has_key?('error')
              Log.log.error("#{p['error']['user_message']} : #{p['path']}")
              result="ERROR: "+p['error']['user_message']
            end
            resres[:data].push({type=>p['path'],'result'=>result})
          end
          return c_result_remove_prefix_path(resres,type,path_prefix)
        end

        def self.c_delete_files(api_node,paths_to_delete,prefix_path)
          resp=api_node.create('files/delete',{:paths=>paths_to_delete.map{|i| {'path'=>i.start_with?('/') ? i : '/'+i} }})
          return c_result_translate_rem_prefix(resp,'file','deleted',prefix_path)
        end

        # get path arguments from command line, and add prefix
        def get_next_arg_add_prefix(path_prefix,name,number=:single)
          thepath=Main.instance.options.get_next_argument(name,number)
          return thepath if path_prefix.nil?
          return File.join(path_prefix,thepath) if thepath.is_a?(String)
          return thepath.map {|p| File.join(path_prefix,p)} if thepath.is_a?(Array)
          raise StandardError,"expect: nil, String or Array"
        end

        def self.simple_actions; [:events, :space, :info, :mkdir, :mklink, :mkfile, :rename, :delete ];end

        def self.common_actions; simple_actions.clone.concat([:browse, :upload, :download ]);end

        # common API to node and Shares
        # prefix_path is used to list remote sources in Faspex
        def execute_common(command,api_node,prefix_path=nil)
          case command
          when :events
            events=api_node.read('events')[:data]
            return { :type=>:object_list, :data => events}
          when :info
            node_info=api_node.read('info')[:data]
            return { :type=>:single_object, :data => node_info, :textify => lambda { |table_data| self.class.c_textify_bool_list_result(table_data,['capabilities','settings'])}}
          when :delete
            paths_to_delete = get_next_arg_add_prefix(prefix_path,"file list",:multiple)
            return self.class.c_delete_files(api_node,paths_to_delete,prefix_path)
          when :space
            # TODO: could be a list of path
            path_list=get_next_arg_add_prefix(prefix_path,"folder path or ext.val. list")
            path_list=[path_list] unless path_list.is_a?(Array)
            resp=api_node.create('space',{ "paths" => path_list.map {|i| {:path=>i} } } )
            result={:data=>resp[:data]['paths'],:type=>:object_list}
            #return c_result_translate_rem_prefix(resp,'folder','created',prefix_path)
            return self.class.c_result_remove_prefix_path(result,'path',prefix_path)
          when :mkdir
            path_list=get_next_arg_add_prefix(prefix_path,"folder path or ext.val. list")
            path_list=[path_list] unless path_list.is_a?(Array)
            #TODO
            #resp=api_node.create('space',{ "paths" => path_list.map {|i| {:type=>:directory,:path=>i} } } )
            resp=api_node.create('files/create',{ "paths" => [{ :type => :directory, :path => path_list } ] } )
            return self.class.c_result_translate_rem_prefix(resp,'folder','created',prefix_path)
          when :mklink
            target=get_next_arg_add_prefix(prefix_path,"target")
            path_list=get_next_arg_add_prefix(prefix_path,"link path")
            resp=api_node.create('files/create',{ "paths" => [{ :type => :symbolic_link, :path => path_list, :target => {:path => target} } ] } )
            return self.class.c_result_translate_rem_prefix(resp,'folder','created',prefix_path)
          when :mkfile
            path_list=get_next_arg_add_prefix(prefix_path,"file path")
            contents64=Base64.strict_encode64(Main.instance.options.get_next_argument("contents"))
            resp=api_node.create('files/create',{ "paths" => [{ :type => :file, :path => path_list, :contents => contents64 } ] } )
            return self.class.c_result_translate_rem_prefix(resp,'folder','created',prefix_path)
          when :rename
            path_base=get_next_arg_add_prefix(prefix_path,"path_base")
            path_src=get_next_arg_add_prefix(prefix_path,"path_src")
            path_dst=get_next_arg_add_prefix(prefix_path,"path_dst")
            resp=api_node.create('files/rename',{ "paths" => [{ "path" => path_base, "source" => path_src, "destination" => path_dst } ] } )
            return self.class.c_result_translate_rem_prefix(resp,'entry','moved',prefix_path)
          when :browse
            thepath=get_next_arg_add_prefix(prefix_path,"path")
            query={ :path => thepath}
            additional_query=Main.instance.options.get_option(:query,:optional)
            query.merge!(additional_query) unless additional_query.nil?
            send_result=api_node.create('files/browse', query)
            #send_result={:data=>{'items'=>[{'file'=>"filename1","permissions"=>[{'name'=>'read'},{'name'=>'write'}]}]}}
            return Plugin.result_empty if !send_result[:data].has_key?('items')
            result={ :data => send_result[:data]['items'] , :type => :object_list, :textify => lambda { |table_data| self.class.c_textify_browse(table_data) } }
            Main.instance.display_status("Items: #{send_result[:data]['item_count']}/#{send_result[:data]['total_count']}")
            return self.class.c_result_remove_prefix_path(result,'path',prefix_path)
          when :upload
            filelist = Main.instance.options.get_next_argument("source file list",:multiple)
            Log.log.debug("file list=#{filelist}")
            destination=Main.instance.destination_folder('send')
            send_result=api_node.create('files/upload_setup',{ :transfer_requests => [ { :transfer_request => { :paths => [ { :destination => destination } ] } } ] } )
            raise send_result[:data]['error']['user_message'] if send_result[:data].has_key?('error')
            raise send_result[:data]['transfer_specs'][0]['error']['user_message'] if send_result[:data]['transfer_specs'][0].has_key?('error')
            raise "expecting one session exactly" if send_result[:data]['transfer_specs'].length != 1
            transfer_spec=send_result[:data]['transfer_specs'].first['transfer_spec']
            transfer_spec['paths']=filelist.map { |i| {'source'=>i} }
            return Main.instance.start_transfer_wait_result(transfer_spec,:node_gen3)
          when :download
            filelist = get_next_arg_add_prefix(prefix_path,"source file list",:multiple)
            Log.log.debug("file list=#{filelist}")
            send_result=api_node.create('files/download_setup',{ :transfer_requests => [ { :transfer_request => { :paths => filelist.map {|i| {:source=>i}; } } } ] } )
            raise send_result[:data]['transfer_specs'][0]['error']['user_message'] if send_result[:data]['transfer_specs'][0].has_key?('error')
            raise "expecting one session exactly" if send_result[:data]['transfer_specs'].length != 1
            transfer_spec=send_result[:data]['transfer_specs'].first['transfer_spec']
            return Main.instance.start_transfer_wait_result(transfer_spec,:node_gen3)
          end
        end

        def action_list; self.class.common_actions.clone.concat([ :postprocess,:stream, :transfer, :cleanup, :forward, :access_key, :watch_folder, :service, :async, :central, :asperabrowser ]);end

        def execute_action
          api_node=basic_auth_api()
          command=Main.instance.options.get_next_argument('command',action_list)
          case command
          when *self.class.common_actions; return execute_common(command,api_node)
          when :async
            command=Main.instance.options.get_next_argument('command',[:list,:summary,:counters])
            if [:summary,:counters].include?(command)
              asyncid=Main.instance.options.get_option(:id,:mandatory)
            end
            case command
            when :list
              resp=api_node.read('async/list')[:data]['sync_ids']
              return { :type => :value_list, :data => resp, :name=>'id'  }
            when :summary
              resp=api_node.create('async/summary',{"syncs"=>[asyncid]})[:data]["sync_summaries"].first
              return Plugin.result_empty if resp.nil?
              return { :type => :single_object, :data => resp }
            when :counters
              resp=api_node.create('async/counters',{"syncs"=>[asyncid]})[:data]["sync_counters"].first[asyncid].last
              return Plugin.result_empty if resp.nil?
              return { :type => :single_object, :data => resp }
            end
          when :stream
            command=Main.instance.options.get_next_argument('command',[ :list, :create, :show, :modify, :cancel ])
            case command
            when :list
              resp=api_node.read('ops/transfers',Main.instance.options.get_option(:value,:optional))
              return { :type => :object_list, :data => resp[:data], :fields=>['id','status']  } # TODO
            when :create
              resp=api_node.create('streams',Main.instance.options.get_option(:value,:mandatory))
              return { :type => :single_object, :data => resp[:data] }
            when :show
              trid=Main.instance.options.get_next_argument("transfer id")
              resp=api_node.read('ops/transfers/'+trid)
              return { :type=>:other_struct, :data => resp[:data] }
            when :modify
              trid=Main.instance.options.get_next_argument("transfer id")
              resp=api_node.update('streams/'+trid,Main.instance.options.get_option(:value,:mandatory))
              return { :type=>:other_struct, :data => resp[:data] }
            when :cancel
              trid=Main.instance.options.get_next_argument("transfer id")
              resp=api_node.cancel('streams/'+trid)
              return { :type=>:other_struct, :data => resp[:data] }
            else
              raise "error"
            end
          when :transfer
            command=Main.instance.options.get_next_argument('command',[ :list, :cancel, :show ])
            res_class_path='ops/transfers'
            if [:cancel, :show].include?(command)
              one_res_id=Main.instance.options.get_option(:id,:mandatory)
              one_res_path="#{res_class_path}/#{one_res_id}"
            end
            case command
            when :list
              # could use ? :subpath=>'transfers'
              resp=api_node.read(res_class_path,Main.instance.options.get_option(:value,:optional))
              return { :type => :object_list, :data => resp[:data], :fields=>['id','status','start_spec.direction','start_spec.remote_user','start_spec.remote_host','start_spec.destination_path']}
            when :cancel
              resp=api_node.cancel(one_res_path)
              return { :type=>:other_struct, :data => resp[:data] }
            when :show
              resp=api_node.read(one_res_path)
              return { :type=>:other_struct, :data => resp[:data] }
            else
              raise "error"
            end
          when :access_key
            return Plugin.entity_action(api_node,'access_keys',['id','root_file_id','storage','license'],:id)
          when :service
            command=Main.instance.options.get_next_argument('command',[ :list, :create, :delete])
            if [:delete].include?(command)
              svcid=Main.instance.options.get_option(:id,:mandatory)
            end
            case command
            when :list
              resp=api_node.read('rund/services')
              #  :fields=>['id','root_file_id','storage','license']
              return { :type=>:object_list, :data => resp[:data]["services"] }
            when :create
              # @json:'{"type":"WATCHFOLDERD","run_as":{"user":"user1"}}'
              params=Main.instance.options.get_next_argument("Run creation data (structure)")
              resp=api_node.create('rund/services',params)
              return Plugin.result_status("#{resp[:data]['id']} created")
            when :delete
              resp=api_node.delete("rund/services/#{svcid}")
              return Plugin.result_status("#{svcid} deleted")
            end
          when :watch_folder
            res_class_path='v3/watchfolders'
            #return Plugin.entity_action(api_node,'v3/watchfolders',nil,:id)
            command=Main.instance.options.get_next_argument('command',[ :create, :list, :show, :modify, :delete, :state])
            if [:show,:modify,:delete,:state].include?(command)
              one_res_id=Main.instance.options.get_option(:id,:mandatory)
              one_res_path="#{res_class_path}/#{one_res_id}"
            end
            case command
            when :create
              resp=api_node.create(res_class_path,Main.instance.options.get_option(:value,:mandatory))
              return Plugin.result_status("#{resp[:data]['id']} created")
            when :list
              resp=api_node.read(res_class_path,Main.instance.options.get_option(:value,:optional))
              #  :fields=>['id','root_file_id','storage','license']
              return { :type=>:value_list, :data => resp[:data]['ids'], :name=>'id' }
            when :show
              return {:type=>:single_object, :data=>api_node.read(one_res_path)[:data]}
            when :modify
              api_node.update(one_res_path,Main.instance.options.get_option(:value,:mandatory))
              return Plugin.result_status("#{one_res_id} updated")
            when :delete
              api_node.delete(one_res_path)
              return Plugin.result_status("#{one_res_id} deleted")
            when :state
              return { :type=>:single_object, :data => api_node.read("#{one_res_path}/state")[:data] }
            end
          when :central
            command=Main.instance.options.get_next_argument('command',[ :session,:file])
            validator_id=Main.instance.options.get_option(:validator)
            validation={"validator_id"=>validator_id} unless validator_id.nil?
            request_data=Main.instance.options.get_option(:value,:optional)
            request_data||={}
            case command
            when :session
              command=Main.instance.options.get_next_argument('command',[ :list])
              case command
              when :list
                request_data.deep_merge!({"validation"=>validation}) unless validation.nil?
                resp=api_node.create('services/rest/transfers/v1/sessions',request_data)
                return {:type=>:object_list,:data=>resp[:data]["session_info_result"]["session_info"],:fields=>["session_uuid","status","transport","direction","bytes_transferred"]}
              end
            when :file
              command=Main.instance.options.get_next_argument('command',[ :list, :modify])
              case command
              when :list
                request_data.deep_merge!({"validation"=>validation}) unless validation.nil?
                resp=api_node.create('services/rest/transfers/v1/files',request_data)
                return {:type=>:object_list,:data=>resp[:data]["file_transfer_info_result"]["file_transfer_info"],:fields=>["session_uuid","file_id","status","path"]}
              when :modify
                request_data.deep_merge!(validation) unless validation.nil?
                api_node.update('services/rest/transfers/v1/files',request_data)
                return Plugin.result_status('updated')
              end
            end
          when :asperabrowser
            browse_params={
              'nodeUser' => Main.instance.options.get_option(:username,:mandatory),
              'nodePW'   => Main.instance.options.get_option(:password,:mandatory),
              'nodeURL'  => Main.instance.options.get_option(:url,:mandatory)
            }
            # encode parameters so that it looks good in url
            encoded_params=Base64.strict_encode64(Zlib::Deflate.deflate(JSON.generate(browse_params))).gsub(/=+$/, '').tr('+/', '-_').reverse
            OpenApplication.instance.uri(Main.instance.options.get_option(:asperabrowserurl)+'?goto='+encoded_params)
            return Plugin.result_status('done')
          end # case command
          raise "ERROR: shall not reach this line"
        end # execute_action
      end # Main
    end # Plugin
  end # Cli
end # Asperalm
