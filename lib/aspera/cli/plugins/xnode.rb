require 'aspera/cli/basic_auth_plugin'
require 'aspera/persistency_file'
require "base64"

module Aspera
  module Cli
    module Plugins
      # experiments
      class Xnode < BasicAuthPlugin
        def initialize(env)
          super(env)
          self.options.add_opt_simple(:filter_transfer,"Ruby expression for filter at transfer level (cleanup)")
          self.options.add_opt_simple(:filter_file,"Ruby expression for filter at file level (cleanup)")
          self.options.parse_options!
        end
        # "transfer_filter"=>"t['status'].eql?('completed') and t['start_spec']['remote_user'].eql?('faspex')", :file_filter=>"f['status'].eql?('completed') and 0 != f['size'] and t['start_spec']['direction'].eql?('send')"

        ACTIONS=[ :postprocess, :cleanup, :forward ]

        # retrieve tranfer list using API and persistency file
        def self.get_transfers_iteration(api_node,params)
          # array with one element max
          iteration_data=[]
          iteration_persistency=nil
          if self.options.get_option(:once_only,:mandatory)
            iteration_persistency=PersistencyFile.new(
            data: iteration_data,
            ids:  ['xnode',self.options.get_option(:url,:mandatory),self.options.get_option(:username,:mandatory)])
          end
          iteration_data[0]=process_file_events(iteration_data[0])
          # first time run ? or subsequent run ?
          params[:iteration_token]=iteration_data[0] unless iteration_data[0].nil?
          resp=api_node.read('ops/transfers',params)
          transfers=resp[:data]
          if transfers.is_a?(Array) then
            # 3.7.2, released API
            iteration_data[0]=URI.decode_www_form(URI.parse(resp[:http]['Link'].match(/<([^>]+)>/)[1]).query).to_h['iteration_token']
          else
            # 3.5.2, deprecated API
            iteration_data[0]=transfers['iteration_token']
            transfers=transfers['transfers']
          end
          iteration_persistency.save unless iteration_persistency.nil?
          return transfers
        end

        def execute_action
          api_node=Rest.new({
            :base_url => self.options.get_option(:url,:mandatory),
            :auth     => {
            :type     => :basic,
            :username => self.options.get_option(:username,:mandatory),
            :password => self.options.get_option(:password,:mandatory)
            }})
          command=self.options.get_next_command(ACTIONS)
          case command
          when :cleanup
            transfers=self.class.get_transfers_iteration(api_node,{:active_only=>false})
            filter_transfer=self.options.get_option(:filter_transfer,:mandatory)
            filter_file=self.options.get_option(:filter_file,:mandatory)
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
            return Main.result_nothing
          when :forward
            # detect transfer sessions since last call
            transfers=self.class.get_transfers_iteration(api_node,{:active_only=>false})
            # build list of all files received in all sessions
            filelist=[]
            transfers.select { |t| t['status'].eql?('completed') and t['start_spec']['direction'].eql?('receive') }.each do |t|
              t['files'].each { |f| filelist.push(f['path']) }
            end
            if filelist.empty?
              Log.log.debug("NO TRANSFER".red)
              return Main.result_nothing
            end
            Log.log.debug("file list=#{filelist}")
            # get download transfer spec on destination node
            transfer_params={ :transfer_requests => [ { :transfer_request => { :paths => filelist.map {|i| {:source=>i} } } } ] }
            send_result=api_node.call({:operation=>'POST',:subpath=>'files/download_setup',:json_params=>transfer_params})
            # only one request, so only one answer
            transfer_spec=send_result[:data]['transfer_specs'].first['transfer_spec']
            # execute transfer
            return Main.result_transfer(self.transfer.start(transfer_spec,{:src=>:node_gen3}))
          when :postprocess
            transfers=self.class.get_transfers_iteration(api_node,{:view=>'summary',:direction=>'receive',:active_only=>false})
            return { :type=>:object_list,:data => transfers }
          end # case command
          raise "ERROR: shall not reach this line"
        end # execute_action
      end # Main
    end # Plugin
  end # Cli
end # Aspera
