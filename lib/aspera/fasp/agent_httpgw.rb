# frozen_string_literal: true

require 'aspera/fasp/agent_base'
require 'aspera/fasp/transfer_spec'
require 'aspera/log'
require 'aspera/rest'
require 'securerandom'
require 'websocket'
require 'base64'
require 'json'

# HTTP GW Upload protocol
# -----------------------
# v1
# 1 - MessageType: String (Transfer Spec) JSON : type: transfer_spec, acknowledged with "end upload"
# 2.. - MessageType: String (Slice Upload start) JSON : type: slice_upload, acknowledged with "end upload"
# v2
# 1 - MessageType: String (Transfer Spec) JSON : type: transfer_spec, acknowledged with "end upload"
# 2 - MessageType: String (Slice Upload start) JSON : type: slice_upload, acknowledged with "end_slice_upload"
# 3.. - MessageType: ByteArray (File Size) Chunks : acknowledged with "end upload"
# last - MessageType: String (Slice Upload end) JSON : type: slice_upload, acknowledged with "end_slice_upload"

# ref: https://api.ibm.com/explorer/catalog/aspera/product/ibm-aspera/api/http-gateway-api/doc/guides-toc
# https://developer.ibm.com/apis/catalog?search=%22aspera%20http%22
module Aspera
  module Fasp
    # start a transfer using Aspera HTTP Gateway, using web socket session for uploads
    class AgentHttpgw < Aspera::Fasp::AgentBase
      # message returned by HTTP GW in case of success
      MSG_RECV_DATA_RECEIVED_SIGNAL = 'end upload'
      MSG_RECV_SLICE_UPLOAD_SIGNAL = 'end_slice_upload'
      MSG_SEND_SLICE_UPLOAD = 'slice_upload'
      MSG_SEND_TRANSFER_SPEC = 'transfer_spec'
      # upload API versions
      API_V1 = 'v1'
      API_V2 = 'v2'
      # options available in CLI (transfer_info)
      DEFAULT_OPTIONS = {
        url:                    nil,
        upload_chunk_size:      64_000,
        upload_bar_refresh_sec: 0.5,
        api_version:            API_V2,
        synchronous:            true
      }.freeze
      DEFAULT_BASE_PATH = '/aspera/http-gwy'
      LOG_WS_MAIN = 'ws: send: '.green
      LOG_WS_THREAD = 'ws: ack: '.red
      private_constant :DEFAULT_OPTIONS, :MSG_RECV_DATA_RECEIVED_SIGNAL, :MSG_RECV_SLICE_UPLOAD_SIGNAL, :API_V1, :API_V2

      # send message on http gw web socket
      def ws_snd_json(msg_type, payload)
        if msg_type.eql?(MSG_SEND_SLICE_UPLOAD) && @options[:api_version].eql?(API_V2)
          @shared_info[:count][:sent_v2_slice] += 1
        else
          @shared_info[:count][:sent_other] += 1
        end
        Log.log.debug do
          log_data = payload.dup
          log_data[:data] = "[data #{log_data[:data].length} bytes]" if log_data.key?(:data)
          "send_txt: #{msg_type}: #{JSON.generate(log_data)}"
        end
        ws_send(JSON.generate({msg_type => payload}))
      end

      def ws_send(data_to_send, type: :text)
        Log.log.debug{"#{LOG_WS_MAIN}send low: type: #{type}"}
        @shared_info[:count][:sent_other] += 1 if type.eql?(:binary)
        Log.log.debug{"#{LOG_WS_MAIN}counts: #{@shared_info[:count]}"}
        frame = ::WebSocket::Frame::Outgoing::Client.new(data: data_to_send, type: type, version: @ws_handshake.version)
        @ws_io.write(frame.to_s)
      end

      # wait for all message sent to be acknowledged by HTTPGW server
      def wait_for_sent_msg_ack_or_exception
        return unless @options[:synchronous]
        @shared_info[:mutex].synchronize do
          while (@shared_info[:count][:received_data] != @shared_info[:count][:sent_other]) ||
              (@shared_info[:count][:received_v2_slice] != @shared_info[:count][:sent_v2_slice])
            Log.log.debug{"#{LOG_WS_MAIN}wait: counts: #{@shared_info[:count]}"}
            @shared_info[:cond_var].wait(@shared_info[:mutex], 1.0)
            raise @shared_info[:read_exception] unless @shared_info[:read_exception].nil?
          end
        end
        Log.log.debug{"#{LOG_WS_MAIN}sync ok: counts: #{@shared_info[:count]}"}
      end

      def upload(transfer_spec)
        # total size of all files
        total_bytes_to_transfer = 0
        # we need to keep track of actual file path because transfer spec is modified to be sent in web socket
        source_paths = []
        # get source root or nil
        source_root = transfer_spec.key?('source_root') && !transfer_spec['source_root'].empty? ? transfer_spec['source_root'] : nil
        # source root is ignored by GW, used only here
        transfer_spec.delete('source_root')
        # compute total size of files to upload (for progress)
        # modify transfer spec to be suitable for GW
        transfer_spec['paths'].each do |item|
          # save actual file location to be able read contents later
          full_src_filepath = item['source']
          # add source root if needed
          full_src_filepath = File.join(source_root, full_src_filepath) unless source_root.nil?
          # GW expects a simple file name in 'source' but if user wants to change the name, we take it
          item['source'] = File.basename(item['destination'].nil? ? item['source'] : item['destination'])
          item['file_size'] = File.size(full_src_filepath)
          total_bytes_to_transfer += item['file_size']
          # save so that we can actually read the file later
          source_paths.push(full_src_filepath)
        end
        # identify this session uniquely
        session_id = SecureRandom.uuid
        upload_url = File.join(@gw_api.params[:base_url], @options[:api_version], 'upload')
        # uri = URI.parse(upload_url)
        # open web socket to end point (equivalent to Net::HTTP.start)
        http_socket = Rest.start_http_session(upload_url)
        # little hack to get the socket opened for HTTP, handy because HTTP debug will be available
        @ws_io = http_socket.instance_variable_get(:@socket)
        # @ws_io.debug_output = Log.log
        @ws_handshake = ::WebSocket::Handshake::Client.new(url: upload_url, headers: {})
        @ws_io.write(@ws_handshake.to_s)
        sleep(0.1)
        @ws_handshake << @ws_io.readuntil("\r\n\r\n")
        raise 'Error in websocket handshake' unless @ws_handshake.finished?
        Log.log.debug{"#{LOG_WS_MAIN}handshake success"}
        # data shared between main thread and read thread
        @shared_info = {
          read_exception: nil, # error message if any in callback
          count:          {
            received_data:     0, # number of files received on other side
            received_v2_slice: 0, # number of slices received on other side
            sent_other:        0,
            sent_v2_slice:     0
          },
          mutex:          Mutex.new,
          cond_var:       ConditionVariable.new
        }
        # start read thread
        ws_read_thread = Thread.new do
          Log.log.debug{"#{LOG_WS_THREAD}read started"}
          frame = ::WebSocket::Frame::Incoming::Client.new(version: @ws_handshake.version)
          loop do
            begin # rubocop:disable Style/RedundantBegin
              # unless (recv_data = @ws_io.getc)
              #  sleep(0.1)
              #  next
              # end
              # frame << recv_data
              # frame << @ws_io.readuntil("\n")
              # frame << @ws_io.read_all
              frame << @ws_io.read(1)
              while (msg = frame.next)
                Log.log.debug{"#{LOG_WS_THREAD}type: #{msg.class}"}
                message = msg.data
                Log.log.debug{"#{LOG_WS_THREAD}message: [#{message}]"}
                if message.eql?(MSG_RECV_DATA_RECEIVED_SIGNAL)
                  @shared_info[:mutex].synchronize do
                    @shared_info[:count][:received_data] += 1
                    @shared_info[:cond_var].signal
                  end
                elsif message.eql?(MSG_RECV_SLICE_UPLOAD_SIGNAL)
                  @shared_info[:mutex].synchronize do
                    @shared_info[:count][:received_v2_slice] += 1
                    @shared_info[:cond_var].signal
                  end
                else
                  message.chomp!
                  error_message =
                    if message.start_with?('"') && message.end_with?('"')
                      JSON.parse(Base64.strict_decode64(message.chomp[1..-2]))['message']
                    elsif message.start_with?('{') && message.end_with?('}')
                      JSON.parse(message)['message']
                    else
                      "unknown message from gateway: [#{message}]"
                    end
                  raise error_message
                end
                Log.log.debug{"#{LOG_WS_THREAD}counts: #{@shared_info[:count]}"}
              end # while
            rescue => e
              Log.log.debug{"#{LOG_WS_THREAD}Exception: #{e}"}
              @shared_info[:mutex].synchronize do
                @shared_info[:read_exception] = e unless e.is_a?(EOFError)
                @shared_info[:cond_var].signal
              end
              break
            end # begin
          end # loop
          Log.log.debug{"#{LOG_WS_THREAD}stopping (exc=#{@shared_info[:read_exception]},cls=#{@shared_info[:read_exception].class})"}
        end
        # notify progress bar
        notify_begin(session_id, total_bytes_to_transfer)
        # first step send transfer spec
        Log.dump(:ws_spec, transfer_spec)
        ws_snd_json(MSG_SEND_TRANSFER_SPEC, transfer_spec)
        wait_for_sent_msg_ack_or_exception
        # current file index
        file_index = 0
        # aggregate size sent
        sent_bytes = 0
        # last progress event
        last_progress_time = nil

        transfer_spec['paths'].each do |item|
          # TODO: get mime type?
          file_mime_type = ''
          file_size = item['file_size']
          file_name = File.basename(item[item['destination'].nil? ? 'source' : 'destination'])
          # compute total number of slices
          slice_total = ((file_size - 1) / @options[:upload_chunk_size]) + 1
          File.open(source_paths[file_index]) do |file|
            # current slice index
            slice_index = 0
            until file.eof?
              file_bin_data = file.read(@options[:upload_chunk_size])
              slice_data = {
                name:         file_name,
                type:         file_mime_type,
                size:         file_size,
                slice:        slice_index,
                total_slices: slice_total,
                fileIndex:    file_index
              }
              # Log.dump(:slice_data,slice_data) #if slice_index.eql?(0)
              # interrupt main thread if read thread failed
              raise @shared_info[:read_exception] unless @shared_info[:read_exception].nil?
              begin
                if @options[:api_version].eql?(API_V1)
                  slice_data[:data] = Base64.strict_encode64(file_bin_data)
                  ws_snd_json(MSG_SEND_SLICE_UPLOAD, slice_data)
                else
                  ws_snd_json(MSG_SEND_SLICE_UPLOAD, slice_data) if slice_index.eql?(0)
                  ws_send(file_bin_data, type: :binary)
                  Log.log.debug{"#{LOG_WS_MAIN}sent bin buffer: #{file_index} / #{slice_index}"}
                  ws_snd_json(MSG_SEND_SLICE_UPLOAD, slice_data) if slice_index.eql?(slice_total - 1)
                end
                wait_for_sent_msg_ack_or_exception
              rescue Errno::EPIPE => e
                raise @shared_info[:read_exception] unless @shared_info[:read_exception].nil?
                raise e
              rescue Net::ReadTimeout => e
                Log.log.warn{'A timeout condition using HTTPGW may signal a permission problem on destination. Check ascp logs on httpgw.'}
                raise e
              end
              sent_bytes += file_bin_data.length
              current_time = Time.now
              if last_progress_time.nil? || ((current_time - last_progress_time) > @options[:upload_bar_refresh_sec])
                notify_progress(session_id, sent_bytes)
                last_progress_time = current_time
              end
              slice_index += 1
            end
          end
          file_index += 1
        end

        Log.log.debug('Finished upload, waiting for end of read thread.')
        ws_read_thread.join
        Log.log.debug{"Read thread joined, result: #{@shared_info[:count][:received_data]} / #{@shared_info[:count][:sent_other]}"}
        ws_send(nil, type: :close) unless @ws_io.nil?
        @ws_io = nil
        http_socket&.finish
        notify_progress(session_id, sent_bytes)
        notify_end(session_id)
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
        file_dest =
          if transfer_spec['zip_required'] || transfer_spec['paths'].length > 1
            # it is a zip file if zip is required or there is more than 1 file
            transfer_spec['download_name'] + '.zip'
          else
            # it is a plain file if we don't require zip and there is only one file
            File.basename(transfer_spec['paths'].first['source'])
          end
        file_dest = File.join(transfer_spec['destination_root'], file_dest)
        @gw_api.call({operation: 'GET', subpath: "v1/download/#{transfer_uuid}", save_to_file: file_dest})
      end

      # start FASP transfer based on transfer spec (hash table)
      # note that it is asynchronous
      # HTTP download only supports file list
      def start_transfer(transfer_spec, token_regenerator: nil)
        raise 'GW URL must be set' if @gw_api.nil?
        raise 'paths: must be Array' unless transfer_spec['paths'].is_a?(Array)
        raise 'only token based transfer is supported in GW' unless transfer_spec['token'].is_a?(String)
        Log.dump(:user_spec, transfer_spec)
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
        Log.dump(:in_options, opts)
        # set default options and override if specified
        @options = DEFAULT_OPTIONS.dup
        raise "httpgw agent parameters (transfer_info): expecting Hash, but have #{opts.class}" unless opts.is_a?(Hash)
        opts.symbolize_keys.each do |k, v|
          raise "httpgw agent parameter: Unknown: #{k}, expect one of #{DEFAULT_OPTIONS.keys.map(&:to_s).join(',')}" unless DEFAULT_OPTIONS.key?(k)
          @options[k] = v
        end
        if @options[:url].nil?
          available = DEFAULT_OPTIONS.map { |k, v| "#{k}(#{v})"}.join(', ')
          raise "Missing mandatory parameter for HTTP GW in transfer_info: url. Allowed parameters: #{available}."
        end
        # remove /v1 from end
        @options[:url].gsub(%r{/v1/*$}, '')
        super()
        @gw_api = Rest.new({base_url: @options[:url]})
        @api_info = @gw_api.read('v1/info')[:data]
        Log.dump(:api_info, @api_info)
        if @options[:api_version].nil?
          # web socket endpoint: by default use v2 (newer gateways), without base64 encoding
          @options[:api_version] = API_V2
          # is the latest supported? else revert to old api
          @options[:api_version] = API_V1 unless @api_info['endpoints'].any?{|i|i.include?(@options[:api_version])}
        end
        @options.freeze
        Log.dump(:final_options, @options)
      end
    end # AgentHttpgw
  end
end
