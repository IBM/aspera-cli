# frozen_string_literal: true

require 'aspera/fasp/agent_base'
require 'aspera/fasp/transfer_spec'
require 'aspera/fasp/faux_file'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/rest'
require 'securerandom'
require 'websocket'
require 'base64'
require 'json'

module Aspera
  module Fasp
    # Start a transfer using Aspera HTTP Gateway, using web socket secure for uploads
    # ref: https://api.ibm.com/explorer/catalog/aspera/product/ibm-aspera/api/http-gateway-api/doc/guides-toc
    # https://developer.ibm.com/apis/catalog?search=%22aspera%20http%22
    # HTTP GW Upload protocol:
    #   #     type                Contents            Ack                 Counter
    # v1
    #   0     JSON.transfer_spec  Transfer Spec       "end upload"        sent_general
    #   1..   JSON.slice_upload   File base64 chunks  "end upload"        sent_general
    # v2
    #   0     JSON.transfer_spec  Transfer Spec       "end upload"        sent_general
    #   1     JSON.slice_upload   File start          "end_slice_upload"  sent_v2_delimiter
    #   2..   Binary              File binary chunks  "end upload"        sent_general
    #   last  JSON.slice_upload   File end            "end_slice_upload"  sent_v2_delimiter
    class AgentHttpgw < Aspera::Fasp::AgentBase
      MSG_SEND_TRANSFER_SPEC = 'transfer_spec'
      MSG_SEND_SLICE_UPLOAD = 'slice_upload'
      MSG_RECV_DATA_RECEIVED_SIGNAL = 'end upload'
      MSG_RECV_SLICE_UPLOAD_SIGNAL = 'end_slice_upload'
      # upload API versions
      API_V1 = 'v1'
      API_V2 = 'v2'
      # options available in CLI (transfer_info)
      DEFAULT_OPTIONS = {
        url:               :required,
        upload_chunk_size: 64_000,
        api_version:       API_V2,
        synchronous:       false
      }.freeze
      DEFAULT_BASE_PATH = '/aspera/http-gwy'
      THR_RECV = 'recv'
      LOG_WS_SEND = 'ws: send: '.red
      LOG_WS_RECV = "ws: #{THR_RECV}: ".green
      private_constant :DEFAULT_OPTIONS, :MSG_RECV_DATA_RECEIVED_SIGNAL, :MSG_RECV_SLICE_UPLOAD_SIGNAL, :API_V1, :API_V2

      # send message on http gw web socket
      def ws_snd_json(msg_type, payload)
        if msg_type.eql?(MSG_SEND_SLICE_UPLOAD) && @options[:api_version].eql?(API_V2)
          @shared_info[:count][:sent_v2_delimiter] += 1
        else
          @shared_info[:count][:sent_general] += 1
        end
        Log.log.debug do
          log_data = payload.dup
          log_data[:data] = "[data #{log_data[:data].length} bytes]" if log_data.key?(:data)
          "#{LOG_WS_SEND}json: #{msg_type}: #{JSON.generate(log_data)}"
        end
        ws_send(ws_type: :text, data: JSON.generate({msg_type => payload}))
      end

      # send data on http gw web socket
      def ws_send(ws_type:, data:)
        Log.log.debug{"#{LOG_WS_SEND}sending: #{ws_type} (#{data&.length || 0} bytes)"}
        @shared_info[:count][:sent_general] += 1 if ws_type.eql?(:binary)
        frame_generator = ::WebSocket::Frame::Outgoing::Client.new(data: data, type: ws_type, version: @ws_handshake.version)
        @ws_io.write(frame_generator.to_s)
        if @options[:synchronous]
          @shared_info[:mutex].synchronize do
            # if read thread exited, there will be no more updates
            # we allow for 1 of difference else it stays blocked
            while @ws_read_thread.alive? &&
                @shared_info[:read_exception].nil? &&
                (((@shared_info[:count][:sent_general] - @shared_info[:count][:received_general]) > 1) ||
                  ((@shared_info[:count][:received_v2_delimiter] - @shared_info[:count][:sent_v2_delimiter]) > 1))
              if !@shared_info[:cond_var].wait(@shared_info[:mutex], 2.0)
                Log.log.debug{"#{LOG_WS_SEND}#{'timeout'.blue}: #{@shared_info[:count]}"}
              end
            end
          end
        end
        raise @shared_info[:read_exception] unless @shared_info[:read_exception].nil?
        Log.log.debug{"#{LOG_WS_SEND}counts: #{@shared_info[:count]}"}
      end

      # message processing for read thread
      def process_received_message(message)
        Log.log.debug{"#{LOG_WS_RECV}message: [#{message}] (#{message.class})"}
        if message.eql?(MSG_RECV_DATA_RECEIVED_SIGNAL)
          @shared_info[:mutex].synchronize do
            @shared_info[:count][:received_general] += 1
            @shared_info[:cond_var].signal
          end
        elsif message.eql?(MSG_RECV_SLICE_UPLOAD_SIGNAL)
          @shared_info[:mutex].synchronize do
            @shared_info[:count][:received_v2_delimiter] += 1
            @shared_info[:cond_var].signal
          end
        else
          message.chomp!
          error_message =
            if message.start_with?('"') && message.end_with?('"')
              # remove double quotes : 1..-2
              JSON.parse(Base64.strict_decode64(message.chomp[1..-2]))['message']
            elsif message.start_with?('{') && message.end_with?('}')
              JSON.parse(message)['message']
            else
              "unknown message from gateway: [#{message}]"
            end
          raise error_message
        end
      end

      # main function of read thread
      def process_read_thread
        Log.log.debug{"#{LOG_WS_RECV}read thread started"}
        frame_parser = ::WebSocket::Frame::Incoming::Client.new(version: @ws_handshake.version)
        until @ws_io.eof?
          begin # rubocop:disable Style/RedundantBegin
            # ready byte by byte until frame is ready
            # blocking read
            byte = @ws_io.read(1)
            Log.log.trace1{"#{LOG_WS_RECV}read: #{byte} (#{byte.class}) eof=#{@ws_io.eof?}"}
            frame_parser << byte
            frame_ok = frame_parser.next
            next if frame_ok.nil?
            process_received_message(frame_ok.data.to_s)
            Log.log.debug{"#{LOG_WS_RECV}counts: #{@shared_info[:count]}"}
          rescue => e
            Log.log.debug{"#{LOG_WS_RECV}Exception: #{e}"}
            @shared_info[:mutex].synchronize do
              @shared_info[:read_exception] = e
              @shared_info[:cond_var].signal
            end
            break
          end # begin/rescue
        end # loop
        Log.log.debug do
          "#{LOG_WS_RECV}exception: #{@shared_info[:read_exception]},cls=#{@shared_info[:read_exception].class})"
        end unless @shared_info[:read_exception].nil?
        Log.log.debug{"#{LOG_WS_RECV}read thread stopped (ws eof=#{@ws_io.eof?})"}
      end

      def upload(transfer_spec)
        # identify this session uniquely
        session_id = SecureRandom.uuid
        notify_progress(session_id: nil, type: :pre_start, info: 'starting')
        # total size of all files
        total_bytes_to_transfer = 0
        # we need to keep track of actual file path because transfer spec is modified to be sent in web socket
        files_to_read = []
        # get source root or nil
        source_root = transfer_spec.key?('source_root') && !transfer_spec['source_root'].empty? ? transfer_spec['source_root'] : nil
        # source root is ignored by GW, used only here
        transfer_spec.delete('source_root')
        # compute total size of files to upload (for progress)
        # modify transfer spec to be suitable for GW
        transfer_spec['paths'].each do |item|
          # save actual file location to be able read contents later
          file_to_add = FauxFile.open(item['source'])
          if file_to_add
            item['source'] = file_to_add.path
            item['file_size'] = file_to_add.size
          else
            file_to_add = item['source']
            # add source root if needed
            file_to_add = File.join(source_root, file_to_add) unless source_root.nil?
            # GW expects a simple file name in 'source' but if user wants to change the name, we take it
            item['source'] = File.basename(item['destination'].nil? ? item['source'] : item['destination'])
            item['file_size'] = File.size(file_to_add)
          end
          # save so that we can actually read the file later
          files_to_read.push(file_to_add)
          total_bytes_to_transfer += item['file_size']
        end
        upload_url = File.join(@gw_api.params[:base_url], @options[:api_version], 'upload')
        notify_progress(session_id: nil, type: :pre_start, info: 'connecting wss')
        # open web socket to end point (equivalent to Net::HTTP.start)
        http_session = Rest.start_http_session(upload_url)
        # get the underlying socket i/o
        @ws_io = Rest.io_http_session(http_session)
        @ws_handshake = ::WebSocket::Handshake::Client.new(url: upload_url, headers: {})
        @ws_io.write(@ws_handshake.to_s)
        sleep(0.1)
        @ws_handshake << @ws_io.readuntil("\r\n\r\n")
        Aspera.assert(@ws_handshake.finished?){'Error in websocket handshake'}
        Log.log.debug{"#{LOG_WS_SEND}handshake success"}
        # start read thread after handshake
        @ws_read_thread = Thread.new {process_read_thread}
        notify_progress(session_id: session_id, type: :session_start)
        notify_progress(session_id: session_id, type: :session_size, info: total_bytes_to_transfer)
        sleep(1)
        # data shared between main thread and read thread
        @shared_info = {
          read_exception: nil, # error message if any in callback
          count:          {
            sent_general:          0,
            received_general:      0,
            sent_v2_delimiter:     0,
            received_v2_delimiter: 0
          },
          mutex:          Mutex.new,
          cond_var:       ConditionVariable.new
        }
        # notify progress bar
        notify_progress(type: :session_size, session_id: session_id, info: total_bytes_to_transfer)
        # first step send transfer spec
        Log.log.debug{Log.dump(:ws_spec, transfer_spec)}
        ws_snd_json(MSG_SEND_TRANSFER_SPEC, transfer_spec)
        # current file index
        file_index = 0
        # aggregate size sent
        session_sent_bytes = 0
        # process each file
        transfer_spec['paths'].each do |item|
          slice_info = {
            name:       nil,
            # TODO: get mime type?
            type:       'application/octet-stream',
            size:       item['file_size'],
            slice:      0, # current slice index
            # index of last slice (i.e number of slices - 1)
            last_slice: (item['file_size'] - 1) / @options[:upload_chunk_size],
            fileIndex:  file_index
          }
          file = files_to_read[file_index]
          if file.is_a?(FauxFile)
            slice_info[:name] = file.path
          else
            file = File.open(file)
            slice_info[:name] = File.basename(item[item['destination'].nil? ? 'source' : 'destination'])
          end
          begin
            until file.eof?
              slice_bin_data = file.read(@options[:upload_chunk_size])
              # interrupt main thread if read thread failed
              raise @shared_info[:read_exception] unless @shared_info[:read_exception].nil?
              begin
                if @options[:api_version].eql?(API_V1)
                  slice_info[:data] = Base64.strict_encode64(slice_bin_data)
                  ws_snd_json(MSG_SEND_SLICE_UPLOAD, slice_info)
                else
                  # send once, before data, at beginning
                  ws_snd_json(MSG_SEND_SLICE_UPLOAD, slice_info) if slice_info[:slice].eql?(0)
                  ws_send(ws_type: :binary, data: slice_bin_data)
                  Log.log.debug{"#{LOG_WS_SEND}buffer: file: #{file_index}, slice: #{slice_info[:slice]}/#{slice_info[:last_slice]}"}
                  # send once, after data, at end
                  ws_snd_json(MSG_SEND_SLICE_UPLOAD, slice_info) if slice_info[:slice].eql?(slice_info[:last_slice])
                end
              rescue Errno::EPIPE => e
                raise @shared_info[:read_exception] unless @shared_info[:read_exception].nil?
                raise e
              rescue Net::ReadTimeout => e
                Log.log.warn{'A timeout condition using HTTPGW may signal a permission problem on destination. Check ascp logs on httpgw.'}
                raise e
              end
              session_sent_bytes += slice_bin_data.length
              notify_progress(type: :transfer, session_id: session_id, info: session_sent_bytes)
              slice_info[:slice] += 1
            end
          ensure
            file.close
          end
          file_index += 1
        end # loop on files
        # throttling may have skipped last one
        notify_progress(type: :transfer, session_id: session_id, info: session_sent_bytes)
        notify_progress(type: :end, session_id: session_id)
        ws_send(ws_type: :close, data: nil)
        Log.log.debug("Finished upload, waiting for end of #{THR_RECV} thread.")
        @ws_read_thread.join
        Log.log.debug{'Read thread joined'}
        # session no more used
        @ws_io = nil
        http_session&.finish
      end

      def download(transfer_spec)
        transfer_spec['zip_required'] ||= false
        transfer_spec['source_root'] ||= '/'
        # is normally provided by application, like package name
        if !transfer_spec.key?('download_name')
          # by default it is the name of first file
          download_name = File.basename(transfer_spec['paths'].first['source'])
          # we remove extension
          download_name = download_name.gsub(/\.@gw_api.*$/, '')
          # ands add indication of number of files if there is more than one
          if transfer_spec['paths'].length > 1
            download_name += " #{transfer_spec['paths'].length} Files"
          end
          transfer_spec['download_name'] = download_name
        end
        creation = @gw_api.create('v1/download', {'transfer_spec' => transfer_spec})[:data]
        transfer_uuid = creation['url'].split('/').last
        file_name =
          if transfer_spec['zip_required'] || transfer_spec['paths'].length > 1
            # it is a zip file if zip is required or there is more than 1 file
            transfer_spec['download_name'] + '.zip'
          else
            # it is a plain file if we don't require zip and there is only one file
            File.basename(transfer_spec['paths'].first['source'])
          end
        file_path = File.join(transfer_spec['destination_root'], file_name)
        @gw_api.call({operation: 'GET', subpath: "v1/download/#{transfer_uuid}", save_to_file: file_path})
      end

      # start FASP transfer based on transfer spec (hash table)
      # note that it is asynchronous
      # HTTP download only supports file list
      def start_transfer(transfer_spec, token_regenerator: nil)
        raise 'GW URL must be set' if @gw_api.nil?
        Aspera.assert_type(transfer_spec['paths'], Array){'paths'}
        Aspera.assert_type(transfer_spec['token'], String){'only token based transfer is supported in GW'}
        Log.log.debug{Log.dump(:user_spec, transfer_spec)}
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
        # well ... transfer was done in "start"
        return [:success]
      end

      # TODO: is that useful?
      def url=(api_url); end

      private

      def initialize(opts)
        super(opts)
        @options = AgentBase.options(default: DEFAULT_OPTIONS, options: opts)
        # remove /v1 from end of user-provided GW url: we need the base url only
        @options[:url].gsub(%r{/v1/*$}, '')
        @gw_api = Rest.new({base_url: @options[:url]})
        @api_info = @gw_api.read('v1/info')[:data]
        Log.log.debug{Log.dump(:api_info, @api_info)}
        # web socket endpoint: by default use v2 (newer gateways), without base64 encoding
        # is the latest supported? else revert to old api
        if !@options[:api_version].eql?(API_V1)
          if !@api_info['endpoints'].any?{|i|i.include?(@options[:api_version])}
            Log.log.warn{"API version #{@options[:api_version]} not supported, reverting to #{API_V1}"}
            @options[:api_version] = API_V1
          end
        end
        @options.freeze
        Log.log.debug{Log.dump(:agent_options, @options)}
      end
    end # AgentHttpgw
  end
end
