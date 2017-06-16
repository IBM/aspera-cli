require 'asperalm/cli/basic_auth_plugin'

module Asperalm
  module Cli
    module Plugins
      class Node < BasicAuthPlugin
        attr_accessor :faspmanager
        def initialize(option_parser)
          super(option_parser)
          # handler must be set before setting defaults
          self.options.set_handler(:filter_config) { |op,val| attr_filter_config(op,val) }
        end
        alias super_set_options set_options

        def set_options
          super_set_options
          self.options.set_option(:persistency,File.join($PROGRAM_FOLDER,"persistency_cleanup.txt"))
          self.options.set_option(:filter_req,'{"active_only":false}')
          self.options.add_opt_simple(:persistency,"--persistency=FILEPATH","persistency file")
          self.options.add_opt_simple(:filter_config,"--filter-config=NAME","Ruby expression for filter at transfer level")
          self.options.add_opt_simple(:filter_transfer,"--filter-transfer=EXPRESSION","Ruby expression for filter at transfer level")
          self.options.add_opt_simple(:filter_file,"--filter-file=EXPRESSION","Ruby expression for filter at file level")
          self.options.add_opt_simple(:filter_req,"--filter-request=EXPRESSION","Ruby expression for filter at file level")
        end

        def self.format_browse(items)
          items.map {|i| i['permissions']=i['permissions'].map { |x| x['name'] }.join(','); i }
        end

        def self.format_transfer_list(items)
          items.map {|i| ['remote_user','remote_host'].each { |field| i[field]=i['start_spec'][field] }; i }
        end

        def self.result_translate(resp,type,default)
          resres={:data=>[],:type=>:hash_array,:fields=>[type,'result'],}
          JSON.parse(resp[:http].body)['paths'].each do |p|
            result=default
            if p.has_key?('error')
              Log.log.error("#{p['error']['user_message']} : #{p['path']}")
              result="ERROR: "+p['error']['user_message']
            end
            resres[:data].push({type=>p['path'],'result'=>result})
          end
          return resres
        end

        def self.delete_files(api_node,paths_to_delete)
          resp=api_node.call({:operation=>'POST',:subpath=>'files/delete',:json_params=>{:paths=>paths_to_delete.map {|i| {'path'=>i.start_with?('/') ? i : '/'+i}}}})
          #resp=api_node.create('files/delete',{:paths=>...})
          return result_translate(resp,'file','deleted')
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

        #TODO: use textify
        def self.bool_param_to_string(hash,name)
          #hash[name]=hash[name].map {|i| "#{i['name']}=#{i['value']}"}.join(', ')
          hash[name].each {|i| hash[i['name']]=i['value']}
          hash.delete(name)
        end

        def self.get_prefix_path(theprefix,thepath)
          return thepath if theprefix.nil?
          return File.join(theprefix,thepath) if thepath.is_a?(String)
          return thepath.map {|p| File.join(theprefix,p)} if thepath.is_a?(Array)
          raise StandardError,"unexpected case"
        end

        def self.remove_result_prefix_path(theprefix,result,column)
          if !theprefix.nil?
            result[:data].each do |r|
              r[column].gsub!(theprefix,'')
            end
          end
          return result
        end

        def self.common_actions; [:info, :browse, :mkdir, :rename, :delete, :upload, :download ];end

        # common API to node and Shares
        def self.execute_common(command,api_node,option_parser,faspmanager,prefix_path=nil)
          case command
          when :info
            node_info=api_node.call({:operation=>'GET',:subpath=>'info',:headers=>{'Accept'=>'application/json'}})[:data]
            bool_param_to_string(node_info,'capabilities')
            bool_param_to_string(node_info,'settings')
            return { :data => node_info, :type=>:hash_table}
          when :browse
            thepath=get_prefix_path(prefix_path,option_parser.get_next_arg_value("path"))
            send_result=api_node.call({:operation=>'POST',:subpath=>'files/browse',:json_params=>{ :path => thepath} } )
            #send_result={:data=>{'items'=>[{'file'=>"filename1","permissions"=>[{'name'=>'read'},{'name'=>'write'}]}]}}
            return Main.no_result if !send_result[:data].has_key?('items')
            result={ :data => send_result[:data]['items'] , :type => :hash_array, :textify => lambda { |items| Node.format_browse(items) } }
            return remove_result_prefix_path(prefix_path,result,'path')
          when :delete
            paths_to_delete = get_prefix_path(prefix_path,option_parser.get_remaining_arguments("file list"))
            return remove_result_prefix_path(prefix_path,delete_files(api_node,paths_to_delete),'file')
          when :mkdir
            thepath=get_prefix_path(prefix_path,option_parser.get_next_arg_value("path"))
            resp=api_node.call({:operation=>'POST',:subpath=>'files/create',:json_params=>{ "paths" => [{ "path" => thepath, "type" => "directory" } ] } } )
            return remove_result_prefix_path(prefix_path,result_translate(resp,'folder','created'),'folder')
          when :rename
            path_base=get_prefix_path(prefix_path,option_parser.get_next_arg_value("path_base"))
            path_src=get_prefix_path(prefix_path,option_parser.get_next_arg_value("path_src"))
            path_dst=get_prefix_path(prefix_path,option_parser.get_next_arg_value("path_dst"))
            resp=api_node.call({:operation=>'POST',:subpath=>'files/rename',:json_params=>{ "paths" => [{ "path" => path_base, "source" => path_src, "destination" => path_dst } ] } } )
            return remove_result_prefix_path(prefix_path,result_translate(resp,'entry','moved'),'entry')
          when :upload
            filelist = option_parser.get_remaining_arguments("file list")
            Log.log.debug("file list=#{filelist}")
            raise CliBadArgument,"Missing source(s) and destination" if filelist.length < 2
            destination=get_prefix_path(prefix_path,filelist.pop)
            send_result=api_node.call({:operation=>'POST',:subpath=>'files/upload_setup',:json_params=>{ :transfer_requests => [ { :transfer_request => { :paths => [ { :destination => destination } ] } } ] }})
            raise send_result[:data]['transfer_specs'][0]['error']['user_message'] if send_result[:data]['transfer_specs'][0].has_key?('error')
            raise "expecting one session exactly" if send_result[:data]['transfer_specs'].length != 1
            transfer_spec=send_result[:data]['transfer_specs'].first['transfer_spec']
            transfer_spec['paths']=filelist.map { |i| {'source'=>i} }
            faspmanager.transfer_with_spec(transfer_spec)
            return Main.no_result
          when :download
            filelist = get_prefix_path(prefix_path,option_parser.get_remaining_arguments("file list"))
            Log.log.debug("file list=#{filelist}")
            raise CliBadArgument,"Missing source(s) and destination" if filelist.length < 2
            destination=filelist.pop
            send_result=api_node.call({:operation=>'POST',:subpath=>'files/download_setup',:json_params=>{ :transfer_requests => [ { :transfer_request => { :paths => filelist.map {|i| {:source=>i}; } } } ] }})
            raise send_result[:data]['transfer_specs'][0]['error']['user_message'] if send_result[:data]['transfer_specs'][0].has_key?('error')
            raise "expecting one session exactly" if send_result[:data]['transfer_specs'].length != 1
            transfer_spec=send_result[:data]['transfer_specs'].first['transfer_spec']
            transfer_spec['destination_root']=destination
            faspmanager.transfer_with_spec(transfer_spec)
            return Main.no_result
          end
        end

        def execute_action
          api_node=Rest.new(self.options.get_option_mandatory(:url),{:basic_auth=>{:user=>self.options.get_option_mandatory(:username), :password=>self.options.get_option_mandatory(:password)}})
          command=self.options.get_next_arg_from_list('command',self.class.common_actions.clone.concat([ :stream, :transfer, :cleanup, :forward, :access_key, :watch_folder ]))
          case command
          when *self.class.common_actions; return self.class.execute_common(command,api_node,self.options,@faspmanager)
          when :stream
            command=self.options.get_next_arg_from_list('command',[ :list, :create, :info, :modify, :cancel ])
            case command
            when :list
              filter_req=JSON.parse(self.options.get_option(:filter_req))
              resp=api_node.call({:operation=>'GET',:subpath=>'ops/transfers',:headers=>{'Accept'=>'application/json'},:url_params=>filter_req})
              return { :data => resp[:data], :type => :hash_array, :fields=>['id','status']  } # TODO
            when :create
              resp=api_node.call({:operation=>'POST',:subpath=>'streams',:headers=>{'Accept'=>'application/json'},:json_params=>FaspManager.ts_override_data})
              return { :data => resp[:data], :type => :hash_table }
            when :info
              trid=self.options.get_next_arg_value("transfer id")
              resp=api_node.call({:operation=>'GET',:subpath=>'ops/transfers/'+trid,:headers=>{'Accept'=>'application/json'}})
              return { :data => resp[:data], :type=>:unknown  }
            when :modify
              trid=self.options.get_next_arg_value("transfer id")
              resp=api_node.call({:operation=>'PUT',:subpath=>'streams/'+trid,:headers=>{'Accept'=>'application/json'},:json_params=>FaspManager.ts_override_data})
              return { :data => resp[:data], :type=>:unknown }
            when :cancel
              trid=self.options.get_next_arg_value("transfer id")
              resp=api_node.call({:operation=>'CANCEL',:subpath=>'streams/'+trid,:headers=>{'Accept'=>'application/json'}})
              return { :data => resp[:data], :type=>:unknown }
            else
              raise "error"
            end
          when :transfer
            command=self.options.get_next_arg_from_list('command',[ :list, :cancel, :info ])
            case command
            when :list
              filter_req=JSON.parse(self.options.get_option(:filter_req))
              resp=api_node.call({:operation=>'GET',:subpath=>'ops/transfers',:headers=>{'Accept'=>'application/json'},:url_params=>filter_req})
              return { :data => resp[:data], :type => :hash_array, :fields=>['id','status','remote_user','remote_host'], :textify => lambda { |items| Node.format_transfer_list(items) } } # TODO
              #resp=api_node.call({:operation=>'GET',:subpath=>'transfers',:headers=>{'Accept'=>'application/json'},:url_params=>filter_req})
              #return { :data => resp[:data], :type => :unknown}
            when :cancel
              trid=self.options.get_next_arg_value("transfer id")
              resp=api_node.call({:operation=>'CANCEL',:subpath=>'ops/transfers/'+trid,:headers=>{'Accept'=>'application/json'}})
              return { :data => resp[:data], :type=>:unknown }
            when :info
              trid=self.options.get_next_arg_value("transfer id")
              resp=api_node.call({:operation=>'GET',:subpath=>'ops/transfers/'+trid,:headers=>{'Accept'=>'application/json'}})
              return { :data => resp[:data], :type=>:unknown }
            else
              raise "error"
            end
          when :access_key
            resp=api_node.call({:operation=>'GET',:subpath=>'access_keys',:headers=>{'Accept'=>'application/json'}})
            return {:data=>resp[:data], :type => :hash_array, :fields=>['id','root_file_id','storage','license']}
          when :watch_folder
            resp=api_node.call({:operation=>'GET',:subpath=>'/v3/watchfolders',:headers=>{'Accept'=>'application/json'}})
            #  :fields=>['id','root_file_id','storage','license']
            return { :data => resp[:data], :type=>:unknown }
          when :cleanup
            transfers=self.class.get_transfers_iteration(api_node,self.options.get_option(:persistency),{:active_only=>false})
            persistencyfile=self.options.get_option_mandatory(:persistency)
            filter_transfer=self.options.get_option_mandatory(:filter_transfer)
            filter_file=self.options.get_option_mandatory(:filter_file)
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
              return self.delete_files(api_node,paths_to_delete)
            else
              Log.log.info("nothing to delete")
            end
            return Main.no_result
          when :forward
            destination=self.options.get_next_arg_value("destination folder")
            # detect transfer sessions since last call
            transfers=self.class.get_transfers_iteration(api_node,self.options.get_option(:persistency),{:active_only=>false})
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
            faspmanager.transfer_with_spec(transfer_spec)
            return Main.no_result
          end
          raise "error"
        end # execute_action
      end # Main
    end # Plugin
  end # Cli
end # Asperalm
