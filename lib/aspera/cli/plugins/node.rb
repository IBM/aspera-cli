require 'aspera/cli/basic_auth_plugin'
require 'aspera/nagios'
require 'aspera/hash_ext'
require 'aspera/id_generator'
require 'base64'
require 'zlib'

module Aspera
  module Cli
    module Plugins
      class Node < BasicAuthPlugin
        SAMPLE_SOAP_CALL='<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="urn:Aspera:XML:FASPSessionNET:2009/11:Types"><soapenv:Header></soapenv:Header><soapenv:Body><typ:GetSessionInfoRequest><SessionFilter><SessionStatus>running</SessionStatus></SessionFilter></typ:GetSessionInfoRequest></soapenv:Body></soapenv:Envelope>'
        private_constant :SAMPLE_SOAP_CALL
        def initialize(env)
          super(env)
          # this is added to some requests , for instance to add tags
          @add_request_param = env[:add_request_param] || {}
          unless env[:skip_basic_auth_options]
            self.options.add_opt_simple(:validator,"identifier of validator (optional for central)")
            self.options.add_opt_simple(:asperabrowserurl,"URL for simple aspera web ui")
            self.options.add_opt_simple(:name,"sync name")
            self.options.add_opt_list(:token,[:aspera,:basic,:auto],'todo: type of token used for transfers')
            self.options.set_option(:asperabrowserurl,'https://asperabrowser.mybluemix.net')
            self.options.set_option(:token,:aspera)
            self.options.parse_options!
          end
          return if env[:man_only]
          if env.has_key?(:node_api)
            @api_node=env[:node_api]
          else
            if self.options.get_option(:password,:mandatory).start_with?('Bearer ')
              # info is provided like node_info of aoc
              @api_node=Rest.new({
                base_url: self.options.get_option(:url,:mandatory),
                headers: {
                'Authorization'      => self.options.get_option(:password,:mandatory),
                'X-Aspera-AccessKey' => self.options.get_option(:username,:mandatory),
                }
              })
            else
              # this is normal case
              @api_node=basic_auth_api unless env[:man_only]
            end
          end
        end

        def c_textify_browse(table_data)
          return table_data.map {|i| i['permissions']=i['permissions'].map { |x| x['name'] }.join(','); i }
        end

        # key/value is defined in main in hash_table
        def c_textify_bool_list_result(list,name_list)
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
        def c_result_remove_prefix_path(result,column,path_prefix)
          if !path_prefix.nil?
            case result[:type]
            when :object_list
              result[:data].each do |item|
                item[column].replace(item[column][path_prefix.length..-1]) if item[column].start_with?(path_prefix)
              end
            when :single_object
              item=result[:data]
              item[column].replace(item[column][path_prefix.length..-1]) if item[column].start_with?(path_prefix)
            end
          end
          return result
        end

        # translates paths results into CLI result, and removes prefix
        def c_result_translate_rem_prefix(resp,type,success_msg,path_prefix)
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

        # get path arguments from command line, and add prefix
        def get_next_arg_add_prefix(path_prefix,name,number=:single)
          thepath=self.options.get_next_argument(name,number)
          return thepath if path_prefix.nil?
          return File.join(path_prefix,thepath) if thepath.is_a?(String)
          return thepath.map {|p| File.join(path_prefix,p)} if thepath.is_a?(Array)
          raise StandardError,"expect: nil, String or Array"
        end

        SIMPLE_ACTIONS=[:health,:events, :space, :info, :license, :mkdir, :mklink, :mkfile, :rename, :delete, :search ]

        COMMON_ACTIONS=[:browse, :upload, :download, :api_details ].concat(SIMPLE_ACTIONS)

        # common API to node and Shares
        # prefix_path is used to list remote sources in Faspex
        def execute_simple_common(command,prefix_path)
          case command
          when :health
            nagios=Nagios.new
            begin
              info=@api_node.read('info')[:data]
              nagios.add_ok('node api','accessible')
              nagios.check_time_offset(info['current_time'],'node api')
              nagios.check_product_version( 'node api','entsrv', info['version'])
            rescue => e
              nagios.add_critical('node api',e.to_s)
            end
            begin
              @api_node.call({:operation=>'POST',:subpath=>'services/soap/Transfer-201210',:headers=>{'Content-Type'=>'text/xml;charset=UTF-8','SOAPAction'=>'FASPSessionNET-200911#GetSessionInfo'},:text_body_params=>SAMPLE_SOAP_CALL})[:http].body
              nagios.add_ok('central','accessible by node')
            rescue => e
              nagios.add_critical('central',e.to_s)
            end
            return nagios.result
          when :events
            events=@api_node.read('events',self.options.get_option(:value,:optional))[:data]
            return { :type=>:object_list, :data => events}
          when :info
            node_info=@api_node.read('info')[:data]
            return { :type=>:single_object, :data => node_info, :textify => lambda { |table_data| c_textify_bool_list_result(table_data,['capabilities','settings'])}}
          when :license # requires: asnodeadmin -mu <node user> --acl-add=internal --internal
            node_license=@api_node.read('license')[:data]
            if node_license['failure'].is_a?(String) and node_license['failure'].include?('ACL')
              Log.log.error("server must have: asnodeadmin -mu <node user> --acl-add=internal --internal")
            end
            return { :type=>:single_object, :data => node_license}
          when :delete
            paths_to_delete = get_next_arg_add_prefix(prefix_path,"file list",:multiple)
            resp=@api_node.create('files/delete',{:paths=>paths_to_delete.map{|i| {'path'=>i.start_with?('/') ? i : '/'+i} }})
            return c_result_translate_rem_prefix(resp,'file','deleted',prefix_path)
          when :search
            search_root = get_next_arg_add_prefix(prefix_path,"search root")
            parameters={'path'=>search_root}
            other_options=self.options.get_option(:value,:optional)
            parameters.merge!(other_options) unless other_options.nil?
            resp=@api_node.create('files/search',parameters)
            result={ :type=>:object_list, :data => resp[:data]['items']}
            return Main.result_empty if result[:data].empty?
            result[:fields]=result[:data].first.keys.select{|i|!['basename','permissions'].include?(i)}
            self.format.display_status("Items: #{resp[:data]['item_count']}/#{resp[:data]['total_count']}")
            self.format.display_status("params: #{resp[:data]['parameters'].keys.map{|k|"#{k}:#{resp[:data]['parameters'][k]}"}.join(',')}")
            return c_result_remove_prefix_path(result,'path',prefix_path)
          when :space
            # TODO: could be a list of path
            path_list=get_next_arg_add_prefix(prefix_path,"folder path or ext.val. list")
            path_list=[path_list] unless path_list.is_a?(Array)
            resp=@api_node.create('space',{ "paths" => path_list.map {|i| {:path=>i} } } )
            result={:data=>resp[:data]['paths'],:type=>:object_list}
            #return c_result_translate_rem_prefix(resp,'folder','created',prefix_path)
            return c_result_remove_prefix_path(result,'path',prefix_path)
          when :mkdir
            path_list=get_next_arg_add_prefix(prefix_path,"folder path or ext.val. list")
            path_list=[path_list] unless path_list.is_a?(Array)
            #TODO
            #resp=@api_node.create('space',{ "paths" => path_list.map {|i| {:type=>:directory,:path=>i} } } )
            resp=@api_node.create('files/create',{ "paths" => [{ :type => :directory, :path => path_list } ] } )
            return c_result_translate_rem_prefix(resp,'folder','created',prefix_path)
          when :mklink
            target=get_next_arg_add_prefix(prefix_path,"target")
            path_list=get_next_arg_add_prefix(prefix_path,"link path")
            resp=@api_node.create('files/create',{ "paths" => [{ :type => :symbolic_link, :path => path_list, :target => {:path => target} } ] } )
            return c_result_translate_rem_prefix(resp,'folder','created',prefix_path)
          when :mkfile
            path_list=get_next_arg_add_prefix(prefix_path,"file path")
            contents64=Base64.strict_encode64(self.options.get_next_argument("contents"))
            resp=@api_node.create('files/create',{ "paths" => [{ :type => :file, :path => path_list, :contents => contents64 } ] } )
            return c_result_translate_rem_prefix(resp,'folder','created',prefix_path)
          when :rename
            path_base=get_next_arg_add_prefix(prefix_path,"path_base")
            path_src=get_next_arg_add_prefix(prefix_path,"path_src")
            path_dst=get_next_arg_add_prefix(prefix_path,"path_dst")
            resp=@api_node.create('files/rename',{ "paths" => [{ "path" => path_base, "source" => path_src, "destination" => path_dst } ] } )
            return c_result_translate_rem_prefix(resp,'entry','moved',prefix_path)
          when :browse
            thepath=get_next_arg_add_prefix(prefix_path,"path")
            query={ :path => thepath}
            additional_query=self.options.get_option(:query,:optional)
            query.merge!(additional_query) unless additional_query.nil?
            send_result=@api_node.create('files/browse', query)[:data]
            #example: send_result={'items'=>[{'file'=>"filename1","permissions"=>[{'name'=>'read'},{'name'=>'write'}]}]}
            # if there is no items
            case send_result['self']['type']
            when 'directory','container' # directory: node, container: shares
              result={ :data => send_result['items'] , :type => :object_list, :textify => lambda { |table_data| c_textify_browse(table_data) } }
              self.format.display_status("Items: #{send_result['item_count']}/#{send_result['total_count']}")
            else # 'file','symbolic_link'
              result={ :data => send_result['self'] , :type => :single_object}
              #result={ :data => [send_result['self']] , :type => :object_list, :textify => lambda { |table_data| c_textify_browse(table_data) } }
              #raise "unknown type: #{send_result['self']['type']}"
            end
            return c_result_remove_prefix_path(result,'path',prefix_path)
          when :upload
            # we send only a list of one transfer request
            transfer_request = { :paths => [ { :destination => self.transfer.destination_folder('send') } ] }
            transfer_request.deep_merge!(@add_request_param)
            send_result=@api_node.create('files/upload_setup',{:transfer_requests => [ { :transfer_request => transfer_request } ] } )[:data]
            # only one request, so only one answer
            transfer_spec=send_result['transfer_specs'].first['transfer_spec']
            # delete this part, as the returned value contains only destination, and not sources
            transfer_spec.delete('paths')
            return Main.result_transfer(self.transfer.start(transfer_spec,{:src=>:node_gen3}))
          when :download
            transfer_request = {:paths => self.transfer.ts_source_paths }
            transfer_request.deep_merge!(@add_request_param)
            send_result=@api_node.create('files/download_setup',{:transfer_requests => [ { :transfer_request => transfer_request } ] } )[:data]
            # only one request, so only one answer
            transfer_spec=send_result['transfer_specs'].first['transfer_spec']
            return Main.result_transfer(self.transfer.start(transfer_spec,{:src=>:node_gen3}))
          when :api_details
            return { :type=>:single_object, :data => @api_node.params }
          end
        end

        def execute_async
          command=self.options.get_next_command([:list,:delete,:files,:show,:counters,:bandwidth])
          unless command.eql?(:list)
            asyncname=self.options.get_option(:name,:optional)
            if asyncname.nil?
              asyncid=self.options.get_option(:id,:mandatory)
              if asyncid.eql?('ALL') and [:show,:delete].include?(command)
                asyncids=@api_node.read('async/list')[:data]['sync_ids']
              else
                Integer(asyncid) # must be integer
                asyncids=[asyncid]
              end
            else
              asyncids=@api_node.read('async/list')[:data]['sync_ids']
              summaries=@api_node.create('async/summary',{'syncs' => asyncids})[:data]['sync_summaries']
              selected=summaries.select{|s|s['name'].eql?(asyncname)}.first
              raise "no such sync: #{asyncname}" if selected.nil?
              asyncid=selected['snid']
              asyncids=[asyncid]
            end
            pdata={'syncs' => asyncids}
          end
          case command
          when :list
            resp=@api_node.read('async/list')[:data]['sync_ids']
            return { :type => :value_list, :data => resp, :name=>'id'  }
          when :show
            resp=@api_node.create('async/summary',pdata)[:data]['sync_summaries']
            return Main.result_empty if resp.empty?
            if asyncid.eql?('ALL')
              return { :type => :object_list, :data => resp, :fields => ['snid','name','local_dir','remote_dir'] }
            else
              return { :type => :single_object, :data => resp.first }
            end
          when :delete
            resp=@api_node.create('async/delete',pdata)[:data]
            return { :type => :single_object, :data => resp, :name=>'id'  }
          when :bandwidth
            pdata['seconds']=100  # TODO: as parameter with --value
            resp=@api_node.create('async/bandwidth',pdata)[:data]
            data=resp['bandwidth_data']
            return Main.result_empty if data.empty?
            data=data.first[asyncid]['data']
            return { :type => :object_list, :data => data, :name=>'id'  }
          when :files
            # count int
            # filename str
            # skip int
            # status int
            filter=self.options.get_option(:value,:optional)
            pdata.merge!(filter) unless filter.nil?
            resp=@api_node.create('async/files',pdata)[:data]
            data=resp['sync_files']
            data=data.first[asyncid] unless data.empty?
            iteration_data=[]
            skip_ids_persistency=nil
            if self.options.get_option(:once_only,:mandatory)
              skip_ids_persistency=PersistencyActionOnce.new(
              manager: @agents[:persistency],
              data:    iteration_data,
              id:      IdGenerator.from_list(['sync_files',self.options.get_option(:url,:mandatory),self.options.get_option(:username,:mandatory),asyncid]))
              unless iteration_data.first.nil?
                data.select!{|l| l['fnid'].to_i>iteration_data.first}
              end
              iteration_data[0]=data.last['fnid'].to_i unless data.empty?
            end
            return Main.result_empty if data.empty?
            skip_ids_persistency.save unless skip_ids_persistency.nil?
            return { :type => :object_list, :data => data, :name=>'id'  }
          when :counters
            resp=@api_node.create('async/counters',pdata)[:data]["sync_counters"].first[asyncid].last
            return Main.result_empty if resp.nil?
            return { :type => :single_object, :data => resp }
          end
        end

        ACTIONS=[ :postprocess,:stream, :transfer, :cleanup, :forward, :access_key, :watch_folder, :service, :async, :central, :asperabrowser, :basic_token ].concat(COMMON_ACTIONS)

        def execute_action(command=nil,prefix_path=nil)
          command||=self.options.get_next_command(ACTIONS)
          case command
          when *COMMON_ACTIONS; return execute_simple_common(command,prefix_path)
          when :async; return execute_async()
          when :stream
            command=self.options.get_next_command([ :list, :create, :show, :modify, :cancel ])
            case command
            when :list
              resp=@api_node.read('ops/transfers',self.options.get_option(:value,:optional))
              return { :type => :object_list, :data => resp[:data], :fields=>['id','status']  } # TODO
            when :create
              resp=@api_node.create('streams',self.options.get_option(:value,:mandatory))
              return { :type => :single_object, :data => resp[:data] }
            when :show
              trid=self.options.get_next_argument("transfer id")
              resp=@api_node.read('ops/transfers/'+trid)
              return { :type=>:other_struct, :data => resp[:data] }
            when :modify
              trid=self.options.get_next_argument("transfer id")
              resp=@api_node.update('streams/'+trid,self.options.get_option(:value,:mandatory))
              return { :type=>:other_struct, :data => resp[:data] }
            when :cancel
              trid=self.options.get_next_argument("transfer id")
              resp=@api_node.cancel('streams/'+trid)
              return { :type=>:other_struct, :data => resp[:data] }
            else
              raise "error"
            end
          when :transfer
            command=self.options.get_next_command([ :list, :cancel, :show ])
            res_class_path='ops/transfers'
            if [:cancel, :show].include?(command)
              one_res_id=self.options.get_option(:id,:mandatory)
              one_res_path="#{res_class_path}/#{one_res_id}"
            end
            case command
            when :list
              # could use ? :subpath=>'transfers'
              resp=@api_node.read(res_class_path,self.options.get_option(:value,:optional))
              return { :type => :object_list, :data => resp[:data], :fields=>['id','status','start_spec.direction','start_spec.remote_user','start_spec.remote_host','start_spec.destination_path']}
            when :cancel
              resp=@api_node.cancel(one_res_path)
              return { :type=>:other_struct, :data => resp[:data] }
            when :show
              resp=@api_node.read(one_res_path)
              return { :type=>:other_struct, :data => resp[:data] }
            else
              raise "error"
            end
          when :access_key
            return self.entity_action(@api_node,'access_keys',nil,:id,'self')
          when :service
            command=self.options.get_next_command([ :list, :create, :delete])
            if [:delete].include?(command)
              svcid=self.options.get_option(:id,:mandatory)
            end
            case command
            when :list
              resp=@api_node.read('rund/services')
              return { :type=>:object_list, :data => resp[:data]["services"] }
            when :create
              # @json:'{"type":"WATCHFOLDERD","run_as":{"user":"user1"}}'
              params=self.options.get_next_argument("Run creation data (structure)")
              resp=@api_node.create('rund/services',params)
              return Main.result_status("#{resp[:data]['id']} created")
            when :delete
              resp=@api_node.delete("rund/services/#{svcid}")
              return Main.result_status("#{svcid} deleted")
            end
          when :watch_folder
            res_class_path='v3/watchfolders'
            #return entity_action(@api_node,'v3/watchfolders',nil,:id)
            command=self.options.get_next_command([ :create, :list, :show, :modify, :delete, :state])
            if [:show,:modify,:delete,:state].include?(command)
              one_res_id=self.options.get_option(:id,:mandatory)
              one_res_path="#{res_class_path}/#{one_res_id}"
            end
            # hum, to avoid: Unable to convert 2016_09_14 configuration
            @api_node.params[:headers]||={}
            @api_node.params[:headers]['X-aspera-WF-version']='2017_10_23'
            case command
            when :create
              resp=@api_node.create(res_class_path,self.options.get_option(:value,:mandatory))
              return Main.result_status("#{resp[:data]['id']} created")
            when :list
              resp=@api_node.read(res_class_path,self.options.get_option(:value,:optional))
              return { :type=>:value_list, :data => resp[:data]['ids'], :name=>'id' }
            when :show
              return {:type=>:single_object, :data=>@api_node.read(one_res_path)[:data]}
            when :modify
              @api_node.update(one_res_path,self.options.get_option(:value,:mandatory))
              return Main.result_status("#{one_res_id} updated")
            when :delete
              @api_node.delete(one_res_path)
              return Main.result_status("#{one_res_id} deleted")
            when :state
              return { :type=>:single_object, :data => @api_node.read("#{one_res_path}/state")[:data] }
            end
          when :central
            command=self.options.get_next_command([ :session,:file])
            validator_id=self.options.get_option(:validator)
            validation={"validator_id"=>validator_id} unless validator_id.nil?
            request_data=self.options.get_option(:value,:optional)
            request_data||={}
            case command
            when :session
              command=self.options.get_next_command([ :list])
              case command
              when :list
                request_data.deep_merge!({"validation"=>validation}) unless validation.nil?
                resp=@api_node.create('services/rest/transfers/v1/sessions',request_data)
                return {:type=>:object_list,:data=>resp[:data]["session_info_result"]["session_info"],:fields=>["session_uuid","status","transport","direction","bytes_transferred"]}
              end
            when :file
              command=self.options.get_next_command([ :list, :modify])
              case command
              when :list
                request_data.deep_merge!({'validation'=>validation}) unless validation.nil?
                resp=@api_node.create('services/rest/transfers/v1/files',request_data)[:data]
                resp=JSON.parse(resp) if resp.is_a?(String)
                Log.dump(:resp,resp)
                return {:type=>:object_list,:data=>resp['file_transfer_info_result']['file_transfer_info'],:fields=>["session_uuid","file_id","status","path"]}
              when :modify
                request_data.deep_merge!(validation) unless validation.nil?
                @api_node.update('services/rest/transfers/v1/files',request_data)
                return Main.result_status('updated')
              end
            end
          when :asperabrowser
            browse_params={
              'nodeUser' => self.options.get_option(:username,:mandatory),
              'nodePW'   => self.options.get_option(:password,:mandatory),
              'nodeURL'  => self.options.get_option(:url,:mandatory)
            }
            # encode parameters so that it looks good in url
            encoded_params=Base64.strict_encode64(Zlib::Deflate.deflate(JSON.generate(browse_params))).gsub(/=+$/, '').tr('+/', '-_').reverse
            OpenApplication.instance.uri(self.options.get_option(:asperabrowserurl)+'?goto='+encoded_params)
            return Main.result_status('done')
          when :basic_token
            return Main.result_status("Basic "+Base64.strict_encode64("#{self.options.get_option(:username,:mandatory)}:#{self.options.get_option(:password,:mandatory)}"))
          end # case command
          raise "ERROR: shall not reach this line"
        end # execute_action
      end # Main
    end # Plugin
  end # Cli
end # Aspera
