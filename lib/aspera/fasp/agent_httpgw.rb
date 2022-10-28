# frozen_string_literal: true

require 'aspera/fasp/agent_base'
require 'aspera/fasp/transfer_spec'
require 'aspera/log'
require 'aspera/rest'
require 'websocket-client-simple'
require 'securerandom'
require 'base64'
require 'json'

# ref: https://api.ibm.com/explorer/catalog/aspera/product/ibm-aspera/api/http-gateway-api/doc/guides-toc
# https://developer.ibm.com/apis/catalog?search=%22aspera%20http%22
module Aspera
  module Fasp
    # start a transfer using Aspera HTTP Gateway, using web socket session
    class AgentHttpgw < AgentBase
      # message returned by HTTP GW in case of success
      MSG_END_UPLOAD = 'end upload'
      MSG_END_SLICE = 'end_slice_upload'
      DEFAULT_OPTIONS = {
        url:                    nil,
        upload_chunksize:       64_000,
        upload_bar_refresh_sec: 0.5
      }.freeze
      private_constant :DEFAULT_OPTIONS,:MSG_END_UPLOAD,:MSG_END_SLICE
      # send message on http gw web socket
      def ws_snd_json(ws,type,data)
        ws.send(JSON.generate({type => data}))
      end

      def upload(transfer_spec)
        # total size of all files
        total_size = 0
        # we need to keep track of actual file path because transfer spec is modified to be sent in web socket
        source_paths = []
        # get source root or nil
        source_root = transfer_spec.has_key?('source_root') && !transfer_spec['source_root'].empty? ? transfer_spec['source_root'] : nil
        # source root is ignored by GW, used only here
        transfer_spec.delete('source_root')
        # compute total size of files to upload (for progress)
        # modify transfer spec to be suitable for GW
        transfer_spec['paths'].each do |item|
          # save actual file location to be able read contents later
          full_src_filepath = item['source']
          # add source root if needed
          full_src_filepath = File.join(source_root,full_src_filepath) unless source_root.nil?
          # GW expects a simple file name in 'source' but if user wants to change the name, we take it
          item['source'] = File.basename(item['destination'].nil? ? item['source'] : item['destination'])
          item['file_size'] = File.size(full_src_filepath)
          total_size += item['file_size']
          # save so that we can actually read the file later
          source_paths.push(full_src_filepath)
        end
        # identify this session uniquely
        session_id = SecureRandom.uuid
        ws = ::WebSocket::Client::Simple::Client.new
        # error message if any in callback
        current_error = nil
        # number of files totally sent
        received = 0
        # setup callbacks on websocket
        ws.on(:message) do |msg|
          Log.log.info("ws: message: #{msg.data}")
          message = msg.data
          if message.eql?(MSG_END_UPLOAD)
            received += 1
          elsif message.eql?(MSG_END_SLICE)
          else
            message.chomp!
            current_error =
              if message.start_with?('"') && message.end_with?('"')
                JSON.parse(Base64.strict_decode64(message.chomp[1..-2]))['message']
              else
                "unknown message from gateway: [#{message}]"
              end
          end
        end
        ws.on(:error) do |e|
          current_error = e
        end
        ws.on(:open) do
          Log.log.info('ws: open')
        end
        ws.on(:close) do
          Log.log.info('ws: close')
        end
        # web socket endpoint
        ws_url = "#{@gw_api.params[:base_url]}/v1/upload"
        # use base64 encoding if gateway does not support v2
        use_base64_encoding = @api_info['endpoints'].select{|i|i.include?('/v2/upload')}.empty?
        ws_url.gsub!('/v1/','/v2/') unless use_base64_encoding
        Log.log.debug("base64: #{use_base64_encoding}, url: #{ws_url}")
        # open web socket to end point
        ws.connect(ws_url)
        # async wait ready
        while !ws.open? && current_error.nil?
          Log.log.info('ws: wait')
          sleep(0.2)
        end
        # notify progress bar
        notify_begin(session_id,total_size)
        # first step send transfer spec
        Log.dump(:ws_spec,transfer_spec)
        ws_snd_json(ws,:transfer_spec,transfer_spec)
        # current file index
        file_index = 0
        # aggregate size sent
        sent_bytes = 0
        # last progress event
        lastevent = nil
        transfer_spec['paths'].each do |item|
          # TODO: get mime type?
          file_mime_type = ''
          file_size = item['file_size']
          file_name = File.basename(item[item['destination'].nil? ? 'source' : 'destination'])
          # compute total number of slices
          numslices = 1 + ((file_size - 1) / @options[:upload_chunksize])
          File.open(source_paths[file_index]) do |file|
            # current slice index
            slicenum = 0
            while !file.eof?
              data = file.read(@options[:upload_chunksize])
              slice_data = {
                name:         file_name,
                type:         file_mime_type,
                size:         file_size,
                slice:        slicenum,
                total_slices: numslices,
                fileIndex:    file_index
              }
              #Log.dump(:slice_data,slice_data) #if slicenum.eql?(0)
              if use_base64_encoding
                slice_data[:data] = Base64.strict_encode64(data)
                ws_snd_json(ws,:slice_upload, slice_data)
              else
                ws_snd_json(ws,:slice_upload, slice_data) if slicenum.eql?(0)
                ws.send(data)
                ws_snd_json(ws,:slice_upload, slice_data) if slicenum.eql?(numslices-1)
              end
              # log without data
              sent_bytes += data.length
              currenttime = Time.now
              if lastevent.nil? || ((currenttime - lastevent) > @options[:upload_bar_refresh_sec])
                notify_progress(session_id,sent_bytes)
                lastevent = currenttime
              end
              slicenum += 1
              raise current_error unless current_error.nil?
            end
          end
          file_index += 1
        end
        ws.close
        notify_end(session_id)
      end

      def download(transfer_spec)
        transfer_spec['zip_required'] ||= false
        transfer_spec['source_root'] ||= '/'
        # is normally provided by application, like package name
        if !transfer_spec.has_key?('download_name')
          # by default it is the name of first file
          dname = File.basename(transfer_spec['paths'].first['source'])
          # we remove extension
          dname = dname.gsub(/\.@gw_api.*$/,'')
          # ands add indication of number of files if there is more than one
          if transfer_spec['paths'].length > 1
            dname += " #{transfer_spec['paths'].length} Files"
          end
          transfer_spec['download_name'] = dname
        end
        creation = @gw_api.create('v1/download',{'transfer_spec' => transfer_spec})[:data]
        transfer_uuid = creation['url'].split('/').last
        file_dest =
          if transfer_spec['zip_required'] || transfer_spec['paths'].length > 1
            # it is a zip file if zip is required or there is more than 1 file
            transfer_spec['download_name'] + '.zip'
          else
            # it is a plain file if we don't require zip and there is only one file
            File.basename(transfer_spec['paths'].first['source'])
          end
        file_dest = File.join(transfer_spec['destination_root'],file_dest)
        @gw_api.call({operation: 'GET',subpath: "v1/download/#{transfer_uuid}",save_to_file: file_dest})
      end

      # start FASP transfer based on transfer spec (hash table)
      # note that it is asynchronous
      # HTTP download only supports file list
      def start_transfer(transfer_spec,options={})
        raise 'GW URL must be set' if @gw_api.nil?
        raise 'option: must be hash (or nil)' unless options.is_a?(Hash)
        raise 'paths: must be Array' unless transfer_spec['paths'].is_a?(Array)
        raise 'only token based transfer is supported in GW' unless transfer_spec['token'].is_a?(String)
        Log.dump(:user_spec,transfer_spec)
        transfer_spec['authentication'] ||= 'token'
        case transfer_spec['direction']
        when Fasp::TransferSpec::DIRECTION_SEND
          upload(transfer_spec)
        when Fasp::TransferSpec::DIRECTION_RECEIVE
          download(transfer_spec)
        else
          raise "unexpected direction: [#{transfer_spec['direction']}]"
        end
      end # start_transfer

      # wait for completion of all jobs started
      # @return list of :success or error message
      def wait_for_transfers_completion
        return [:success]
      end

      # terminates monitor thread
      def shutdown; end

      def url=(api_url); end

      private

      def initialize(opts)
        Log.log.debug("local options= #{opts}")
        # set default options and override if specified
        @options = DEFAULT_OPTIONS.dup
        raise "httpgw agent parameters (transfer_info): expecting Hash, but have #{opts.class}" unless opts.is_a?(Hash)
        opts.symbolize_keys.each do |k,v|
          raise "httpgw agent parameter: Unknown: #{k}, expect one of #{DEFAULT_OPTIONS.keys.map(&:to_s).join(',')}" unless DEFAULT_OPTIONS.has_key?(k)
          @options[k] = v
        end
        raise 'missing param: url' if @options[:url].nil?
        # remove /v1 from end
        @options[:url].gsub(%r{/v1/*$},'')
        super()
        @gw_api = Rest.new({base_url: @options[:url]})
        @api_info = @gw_api.read('v1/info')[:data]
        Log.log.info(@api_info.to_s)
      end
    end # AgentHttpgw
  end
end
