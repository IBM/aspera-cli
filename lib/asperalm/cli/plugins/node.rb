require 'asperalm/cli/plugin'

module Asperalm
  module Cli
    module Plugins
      class Node < Plugin
        def opt_names; [:url,:username,:password,:persistency]; end

        attr_accessor :faspmanager

        def command_list;[ :put, :get, :transfers, :info, :cleanup ];end

        def set_options
          self.add_opt_simple(:url,"-wURI", "--url=URI","URL of application, e.g. http://org.asperafiles.com")
          self.add_opt_simple(:username,"-uSTRING", "--username=STRING","username to log in")
          self.add_opt_simple(:password,"-pSTRING", "--password=STRING","password")
          @persistency=File.join(home,"persistency_cleanup.txt")
          self.add_opt_simple(:persistency,"--persistency=FILEPATH","persistency file")
          @transfer_filter="t['status'].eql?('completed') and t['start_spec']['remote_user'].eql?(@config[:filter_transfer_user])"
          @file_filter="f['status'].eql?('completed') and 0 != f['size'] and t['start_spec']['direction'].eql?(@config[:filter_direction])"
          self.add_opt_simple(:transfer_filter,"--transfer-filter=EXPRESSION","Ruby expression for filter at transfer level")
          self.add_opt_simple(:file_filter,"--file-filter=EXPRESSION","Ruby expression for filter at file level")
        end

        def dojob(command,argv)
          api_node=Rest.new(self.get_option_mandatory(:url),{:basic_auth=>{:user=>self.get_option_mandatory(:username), :password=>self.get_option_mandatory(:password)}})
          case command
          when :put
            filelist = argv
            Log.log.debug("file list=#{filelist}")
            if filelist.length < 2 then
              raise OptionParser::InvalidArgument,"Missing source(s) and destination"
            end

            destination=filelist.pop

            send_result=api_node.call({:operation=>'POST',:subpath=>'files/upload_setup',:json_params=>{ :transfer_requests => [ { :transfer_request => { :paths => [ { :destination => destination } ] } } ] }})
            if send_result[:data]['transfer_specs'][0].has_key?('error')
              raise send_result[:data]['transfer_specs'][0]['error']['user_message']
            end
            send_result[:data]['transfer_specs'].each{ |s|
              session=s['transfer_spec']
              @faspmanager.do_transfer(
              :mode    => :send,
              :dest    => session['destination_root'],
              :user    => session['remote_user'],
              :host    => session['remote_host'],
              :token   => session['token'],
              #:cookie  => session['cookie'],
              #:tags    => session['tags'],
              :srcList => filelist,
              :rawArgs => [ '-P', '33001', '-d', '-q', '--ignore-host-key', '-k', '2', '--save-before-overwrite','--partial-file-suffix=.partial' ],
              :retries => 10,
              :use_aspera_key => true)
            }
            return
          when :get
            filelist = argv
            Log.log.debug("file list=#{filelist}")
            if filelist.length < 2 then
              raise OptionParser::InvalidArgument,"Missing source(s) and destination"
            end

            destination=filelist.pop

            send_result=api_node.call({:operation=>'POST',:subpath=>'files/download_setup',:json_params=>{ :transfer_requests => [ { :transfer_request => { :paths => filelist.map {|i| {:source=>i}; } } } ] }})
            if send_result[:data]['transfer_specs'][0].has_key?('error')
              raise send_result[:data]['transfer_specs'][0]['error']['user_message']
            end

            send_result[:data]['transfer_specs'].each{ |s|
              session=s['transfer_spec']
              srcList = session['paths'].map { |i| i['source']}
              @faspmanager.do_transfer(
              :mode    => :recv,
              :dest    => destination,
              :user    => session['remote_user'],
              :host    => session['remote_host'],
              :token   => session['token'],
              :cookie  => session['cookie'],
              :tags    => session['tags'],
              :srcList => srcList,
              :rawArgs => [ '-P', '33001', '-d', '-q', '--ignore-host-key', '-k', '2', '--save-before-overwrite','--partial-file-suffix=.partial' ],
              :retries => 10,
              :use_aspera_key => true)
              return
            }
          when :transfers
            command=self.class.get_next_arg_from_list(argv,'command',[ :list ])
            # ,:url_params=>{:active_only=>true}
            resp=api_node.call({:operation=>'GET',:subpath=>'ops/transfers',:headers=>{'Accept'=>'application/json'}})
            return resp[:data] # TODO
          when :info
            resp=api_node.call({:operation=>'GET',:subpath=>'info',:headers=>{'Accept'=>'application/json'}})
            return resp[:data] # TODO
          when :cleanup
            persistencyfile=self.get_option_mandatory(:persistency)
            # first time run ? or subsequent run ?
            iteration_token=nil
            if File.exist?(persistencyfile)
              iteration_token=File.read(persistencyfile)
            end
            params={:active_only=>false}
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
            File.write(persistencyfile,iteration_token)
            # build list of files to delete: non zero files, downloads, for specified user
            paths_to_delete=[]
            transfer_filter=self.get_option_mandatory(:transfer_filter)
            file_filter=self.get_option_mandatory(:file_filter)
            transfers.each do |t|
              if eval(transfer_filter)
                t['files'].each do |f|
                  if eval(file_filter)
                    paths_to_delete.push({'path'=>'/'+f['path']})
                    @logger.info("to delete: #{f['path']}")
                  end
                end
              end
            end
            # delete files, if any
            if paths_to_delete.length != 0
              @logger.info("deletion")
              resp=api_node.call({:operation=>'POST',:subpath=>'files/delete',:json_params=>{:paths=>paths_to_delete}})
              #resp=api_node.create('files/delete',{:paths=>paths_to_delete})
              JSON.parse(resp[:http].body)['paths'].each do |p|
                if p.has_key?('error')
                  @logger.error("#{p['error']['user_message']} : #{p['path']}")
                end
              end
            else
              @logger.info("no new package")
            end
          end

          return results
        end
      end
    end
  end # Cli
end # Asperalm
