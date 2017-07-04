require 'asperalm/cli/main'
require 'asperalm/cli/basic_auth_plugin'
require "base64"

module Asperalm
  module Cli
    module Plugins
      class Node < BasicAuthPlugin
        alias super_declare_options declare_options
        def declare_options
          super_declare_options
          Main.tool.options.set_option(:persistency,File.join(Main.tool.config_folder,"persistency_cleanup.txt"))
          Main.tool.options.set_option(:filter_req,'{"active_only":false}')
          Main.tool.options.add_opt_simple(:persistency,"--persistency=FILEPATH","persistency file (cleanup,forward)")
          Main.tool.options.add_opt_simple(:filter_transfer,"--filter-transfer=EXPRESSION","Ruby expression for filter at transfer level (cleanup)")
          Main.tool.options.add_opt_simple(:filter_file,"--filter-file=EXPRESSION","Ruby expression for filter at file level (cleanup)")
          Main.tool.options.add_opt_simple(:filter_req,"--filter-request=EXPRESSION","JSON expression for filter on API request")
        end

        def self.textify_browse(table_data)
          return table_data.map {|i| i['permissions']=i['permissions'].map { |x| x['name'] }.join(','); i }
        end

        def self.textify_transfer_list(table_data)
          return table_data.map {|i| ['remote_user','remote_host'].each { |field| i[field]=i['start_spec'][field] }; i }
        end

        # key/value is defined in main in hash_table
        def self.textify_bool_list_result(list,name_list)
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

        def self.result_remove_prefix_path(result,column,path_prefix)
          if !path_prefix.nil?
            result[:data].each do |r|
              r[column].replace(r[column][path_prefix.length..-1]) if r[column].start_with?(path_prefix)
            end
          end
          return result
        end

        # translates paths results into CLI result, and removes prefix
        def self.result_translate_rem_prefix(resp,type,success_msg,path_prefix)
          resres={:data=>[],:type=>:hash_array,:fields=>[type,'result'],}
          JSON.parse(resp[:http].body)['paths'].each do |p|
            result=success_msg
            if p.has_key?('error')
              Log.log.error("#{p['error']['user_message']} : #{p['path']}")
              result="ERROR: "+p['error']['user_message']
            end
            resres[:data].push({type=>p['path'],'result'=>result})
          end
          return result_remove_prefix_path(resres,type,path_prefix)
        end

        def self.delete_files(api_node,paths_to_delete,prefix_path)
          #resp=api_node.create('files/delete',{:paths=>...})
          resp=api_node.call({:operation=>'POST',:subpath=>'files/delete',:json_params=>{:paths=>paths_to_delete.map {|i| {'path'=>i.start_with?('/') ? i : '/'+i}}}})
          return result_translate_rem_prefix(resp,'file','deleted',prefix_path)
        end

        # retrieve tranfer list using API and persistency file
        def self.get_transfers_iteration(api_node,persistencyfile,params)
          # first time run ? or subsequent run ?
          iteration_token=nil
          if !persistencyfile.nil? and File.exist?(persistencyfile)
            iteration_token=File.read(persistencyfile)
          end
          params[:iteration_token]=iteration_token unless iteration_token.nil?
          resp=api_node.list('ops/transfers',params)
          transfers=resp[:data]
          if transfers.is_a?(Array) then
            # 3.7.2, released API
            iteration_token=URI.decode_www_form(URI.parse(resp[:http]['Link'].match(/<([^>]+)>/)[1]).query).to_h['iteration_token']
          else
            # 3.5.2, deprecated API
            iteration_token=transfers['iteration_token']
            transfers=transfers['transfers']
          end
          File.write(persistencyfile,iteration_token) if (!persistencyfile.nil?)
          return transfers
        end

        # get path arguments from command line, and add prefix
        def self.get_next_arg_add_prefix(path_prefix,name,number=:one)
          case number
          when :one; thepath=Main.tool.options.get_next_arg_value(name)
          when :all; thepath=Main.tool.options.get_remaining_arguments(name)
          when :all_but_one; thepath=Main.tool.options.get_remaining_arguments(name,1)
          else raise "ERROR"
          end
          return thepath if path_prefix.nil?
          return File.join(path_prefix,thepath) if thepath.is_a?(String)
          return thepath.map {|p| File.join(path_prefix,p)} if thepath.is_a?(Array)
          raise StandardError,"expect: nil, String or Array"
        end

        def self.common_actions; [:info, :browse, :mkdir, :mklink, :mkfile, :rename, :delete, :upload, :download ];end

        # common API to node and Shares
        # prefix_path is used to list remote sources in Faspex
        def self.execute_common(command,api_node,prefix_path=nil)
          case command
          when :info
            node_info=api_node.call({:operation=>'GET',:subpath=>'info',:headers=>{'Accept'=>'application/json'}})[:data]
            return { :data => node_info, :type=>:key_val_list, :textify => lambda { |table_data| textify_bool_list_result(table_data,['capabilities','settings'])}}
          when :browse
            thepath=get_next_arg_add_prefix(prefix_path,"path")
            send_result=api_node.call({:operation=>'POST',:subpath=>'files/browse',:json_params=>{ :path => thepath} } )
            #send_result={:data=>{'items'=>[{'file'=>"filename1","permissions"=>[{'name'=>'read'},{'name'=>'write'}]}]}}
            return Main.no_result if !send_result[:data].has_key?('items')
            result={ :data => send_result[:data]['items'] , :type => :hash_array, :textify => lambda { |table_data| Node.textify_browse(table_data) } }
            #display_prefix=thepath
            #display_prefix=File.join(prefix_path,display_prefix) if !prefix_path.nil?
            #puts display_prefix.red
            return result_remove_prefix_path(result,'path',prefix_path)
          when :delete
            paths_to_delete = get_next_arg_add_prefix(prefix_path,"file list",:all)
            return delete_files(api_node,paths_to_delete,prefix_path)
          when :mkdir
            thepath=get_next_arg_add_prefix(prefix_path,"folder path")
            resp=api_node.call({:operation=>'POST',:subpath=>'files/create',:json_params=>{ "paths" => [{ :type => :directory, :path => thepath } ] } } )
            return result_translate_rem_prefix(resp,'folder','created',prefix_path)
          when :mklink
            target=get_next_arg_add_prefix(prefix_path,"target")
            thepath=get_next_arg_add_prefix(prefix_path,"link path")
            resp=api_node.call({:operation=>'POST',:subpath=>'files/create',:json_params=>{ "paths" => [{ :type => :symbolic_link, :path => thepath, :target => {:path => target} } ] } } )
            return result_translate_rem_prefix(resp,'folder','created',prefix_path)
          when :mkfile
            thepath=get_next_arg_add_prefix(prefix_path,"file path")
            contents64=Base64.strict_encode64(Main.tool.options.get_next_arg_value("contents"))
            resp=api_node.call({:operation=>'POST',:subpath=>'files/create',:json_params=>{ "paths" => [{ :type => :file, :path => thepath, :contents => contents64 } ] } } )
            return result_translate_rem_prefix(resp,'folder','created',prefix_path)
          when :rename
            path_base=get_next_arg_add_prefix(prefix_path,"path_base")
            path_src=get_next_arg_add_prefix(prefix_path,"path_src")
            path_dst=get_next_arg_add_prefix(prefix_path,"path_dst")
            resp=api_node.call({:operation=>'POST',:subpath=>'files/rename',:json_params=>{ "paths" => [{ "path" => path_base, "source" => path_src, "destination" => path_dst } ] } } )
            return result_translate_rem_prefix(resp,'entry','moved',prefix_path)
          when :upload
            filelist = Main.tool.options.get_remaining_arguments("source file list",1)
            Log.log.debug("file list=#{filelist}")
            destination=get_next_arg_add_prefix(prefix_path,"path_dst")
            send_result=api_node.call({:operation=>'POST',:subpath=>'files/upload_setup',:json_params=>{ :transfer_requests => [ { :transfer_request => { :paths => [ { :destination => destination } ] } } ] }})
            raise send_result[:data]['error']['user_message'] if send_result[:data].has_key?('error')
            raise send_result[:data]['transfer_specs'][0]['error']['user_message'] if send_result[:data]['transfer_specs'][0].has_key?('error')
            raise "expecting one session exactly" if send_result[:data]['transfer_specs'].length != 1
            transfer_spec=send_result[:data]['transfer_specs'].first['transfer_spec']
            transfer_spec['paths']=filelist.map { |i| {'source'=>i} }
            Main.tool.faspmanager.transfer_with_spec(transfer_spec)
            return Main.result_success
          when :download
            filelist = get_next_arg_add_prefix(prefix_path,"source file list",:all_but_one)
            Log.log.debug("file list=#{filelist}")
            destination=Main.tool.options.get_next_arg_value("path_dst")
            send_result=api_node.call({:operation=>'POST',:subpath=>'files/download_setup',:json_params=>{ :transfer_requests => [ { :transfer_request => { :paths => filelist.map {|i| {:source=>i}; } } } ] }})
            raise send_result[:data]['transfer_specs'][0]['error']['user_message'] if send_result[:data]['transfer_specs'][0].has_key?('error')
            raise "expecting one session exactly" if send_result[:data]['transfer_specs'].length != 1
            transfer_spec=send_result[:data]['transfer_specs'].first['transfer_spec']
            transfer_spec['destination_root']=destination
            Main.tool.faspmanager.transfer_with_spec(transfer_spec)
            return Main.result_success
          end
        end

        def action_list; self.class.common_actions.clone.concat([ :stream, :transfer, :cleanup, :forward, :access_key, :watch_folder ]);end

        def execute_action
          api_node=Rest.new(Main.tool.options.get_option_mandatory(:url),{:auth=>{:type=>:basic,:user=>Main.tool.options.get_option_mandatory(:username), :password=>Main.tool.options.get_option_mandatory(:password)}})
          command=Main.tool.options.get_next_arg_from_list('command',action_list)
          case command
          when *self.class.common_actions; return self.class.execute_common(command,api_node)
          when :stream
            command=Main.tool.options.get_next_arg_from_list('command',[ :list, :create, :info, :modify, :cancel ])
            case command
            when :list
              filter_req=JSON.parse(Main.tool.options.get_option(:filter_req))
              resp=api_node.call({:operation=>'GET',:subpath=>'ops/transfers',:headers=>{'Accept'=>'application/json'},:url_params=>filter_req})
              return { :data => resp[:data], :type => :hash_array, :fields=>['id','status']  } # TODO
            when :create
              resp=api_node.call({:operation=>'POST',:subpath=>'streams',:headers=>{'Accept'=>'application/json'},:json_params=>FaspManager.ts_override_data})
              return { :data => resp[:data], :type => :key_val_list }
            when :info
              trid=Main.tool.options.get_next_arg_value("transfer id")
              resp=api_node.call({:operation=>'GET',:subpath=>'ops/transfers/'+trid,:headers=>{'Accept'=>'application/json'}})
              return { :data => resp[:data], :type=>:other_struct  }
            when :modify
              trid=Main.tool.options.get_next_arg_value("transfer id")
              resp=api_node.call({:operation=>'PUT',:subpath=>'streams/'+trid,:headers=>{'Accept'=>'application/json'},:json_params=>FaspManager.ts_override_data})
              return { :data => resp[:data], :type=>:other_struct }
            when :cancel
              trid=Main.tool.options.get_next_arg_value("transfer id")
              resp=api_node.call({:operation=>'CANCEL',:subpath=>'streams/'+trid,:headers=>{'Accept'=>'application/json'}})
              return { :data => resp[:data], :type=>:other_struct }
            else
              raise "error"
            end
          when :transfer
            command=Main.tool.options.get_next_arg_from_list('command',[ :list, :cancel, :info ])
            case command
            when :list
              filter_req=JSON.parse(Main.tool.options.get_option(:filter_req))
              resp=api_node.call({:operation=>'GET',:subpath=>'ops/transfers',:headers=>{'Accept'=>'application/json'},:url_params=>filter_req})
              return { :data => resp[:data], :type => :hash_array, :fields=>['id','status','remote_user','remote_host'], :textify => lambda { |table_data| Node.textify_transfer_list(table_data) } } # TODO
              #resp=api_node.call({:operation=>'GET',:subpath=>'transfers',:headers=>{'Accept'=>'application/json'},:url_params=>filter_req})
              #return { :data => resp[:data], :type => :other_struct}
            when :cancel
              trid=Main.tool.options.get_next_arg_value("transfer id")
              resp=api_node.call({:operation=>'CANCEL',:subpath=>'ops/transfers/'+trid,:headers=>{'Accept'=>'application/json'}})
              return { :data => resp[:data], :type=>:other_struct }
            when :info
              trid=Main.tool.options.get_next_arg_value("transfer id")
              resp=api_node.call({:operation=>'GET',:subpath=>'ops/transfers/'+trid,:headers=>{'Accept'=>'application/json'}})
              return { :data => resp[:data], :type=>:other_struct }
            else
              raise "error"
            end
          when :access_key
            resp=api_node.call({:operation=>'GET',:subpath=>'access_keys',:headers=>{'Accept'=>'application/json'}})
            return {:data=>resp[:data], :type => :hash_array, :fields=>['id','root_file_id','storage','license']}
          when :watch_folder
            resp=api_node.call({:operation=>'GET',:subpath=>'/v3/watchfolders',:headers=>{'Accept'=>'application/json'}})
            #  :fields=>['id','root_file_id','storage','license']
            return { :data => resp[:data], :type=>:other_struct }
          when :cleanup
            transfers=self.class.get_transfers_iteration(api_node,Main.tool.options.get_option(:persistency),{:active_only=>false})
            persistencyfile=Main.tool.options.get_option_mandatory(:persistency)
            filter_transfer=Main.tool.options.get_option_mandatory(:filter_transfer)
            filter_file=Main.tool.options.get_option_mandatory(:filter_file)
            Log.log.debug("filter_transfer: #{filter_transfer}")
            Log.log.debug("filter_file: #{filter_file}")
            # build list of files to delete: non zero files, downloads, for specified user
            paths_to_delete=[]
            transfers.each do |t|
              if eval(filter_transfer)
                t['files'].each do |f|
                  if eval(filter_file)
                    if !paths_to_delete.include?(f['path'])
                      paths_to_delete.push(f['path'])
                      Log.log.info("to delete: #{f['path']}")
                    end
                  end
                end
              end
            end
            # delete files, if any
            if paths_to_delete.length != 0
              Log.log.info("deletion")
              return self.delete_files(api_node,paths_to_delete,nil)
            else
              Log.log.info("nothing to delete")
            end
            return Main.no_result
          when :forward
            destination=Main.tool.options.get_next_arg_value("destination folder")
            # detect transfer sessions since last call
            transfers=self.class.get_transfers_iteration(api_node,Main.tool.options.get_option(:persistency),{:active_only=>false})
            # build list of all files received in all sessions
            filelist=[]
            transfers.select { |t| t['status'].eql?('completed') and t['start_spec']['direction'].eql?('receive') }.each do |t|
              t['files'].each { |f| filelist.push(f['path']) }
            end
            if filelist.empty?
              Log.log.debug("NO TRANSFER".red)
              return Main.no_result
            end
            Log.log.debug("file list=#{filelist}")
            # get download transfer spec on destination node
            transfer_params={ :transfer_requests => [ { :transfer_request => { :paths => filelist.map {|i| {:source=>i} } } } ] }
            send_result=api_node.call({:operation=>'POST',:subpath=>'files/download_setup',:json_params=>transfer_params})
            raise "expecting one session exactly" if send_result[:data]['transfer_specs'].length != 1
            transfer_data=send_result[:data]['transfer_specs'].first
            raise TransferError,transfer_data['error']['user_message'] if transfer_data.has_key?('error')
            transfer_spec=transfer_data['transfer_spec']
            transfer_spec['destination_root']=destination
            # execute transfer
            Main.tool.faspmanager.transfer_with_spec(transfer_spec)
            return Main.result_success
          end
          raise "error"
        end # execute_action
      end # Main
    end # Plugin
  end # Cli
end # Asperalm
