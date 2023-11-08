# frozen_string_literal: true

require 'aspera/fasp/agent_base'
require 'aspera/fasp/transfer_spec'
require 'aspera/log'
require 'aspera/rest'
require 'securerandom'
require 'websocket'
require 'base64'
require 'json'

module Aspera
  module Fasp
    # generates a pseudo file stream
    class FauxFile
      # marker for faux file
      PREFIX = 'faux:///'
      # size suffix
      SUFFIX = %w[k m g t p e]
      class << self
        def open(name)
          return nil unless name.start_with?(PREFIX)
          parts = name[PREFIX.length..-1].split('?')
          raise 'Format: #{PREFIX}<file path>?<size>' unless parts.length.eql?(2)
          raise "Format: <integer>[#{SUFFIX.join(',')}]" unless (m = parts[1].downcase.match(/^(\d+)([#{SUFFIX.join('')}])$/))
          size = m[1].to_i
          suffix = m[2]
          SUFFIX.each do |s|
            size *= 1024
            break if s.eql?(suffix)
          end
          return FauxFile.new(parts[0], size)
        end
      end
      attr_reader :path, :size

      def initialize(path, size)
        @path = path
        @size = size
        @offset = 0
        # we cache large chunks, anyway most of them will be the same size
        @chunk_by_size = {}
      end

      def read(chunk_size)
        return nil if eof?
        bytes_to_read = [chunk_size, @size - @offset].min
        @offset += bytes_to_read
        @chunk_by_size[bytes_to_read] = "\x00" * bytes_to_read unless @chunk_by_size.key?(bytes_to_read)
        return @chunk_by_size[bytes_to_read]
      end

      def close
      end

      def eof?
        return @offset >= @size
      end
    end

    # Start a transfer using Aspera HTTP Gateway, using web socket secure for uploads
    # ref: https://api.ibm.com/explorer/catalog/aspera/product/ibm-aspera/api/http-gateway-api/doc/guides-toc
    # https://developer.ibm.com/apis/catalog?search=%22aspera%20http%22
    # HTTP GW Upload protocol:
    #   #     type                Contents            Ack                 Counter
    # v1
    #   0     JSON.transfer_spec  Transfer Spec       "end upload"        sent_general
    #   1..   JSON.slice_upload   Slice data base64   "end upload"        sent_general
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
        url:                    nil,
        upload_chunk_size:      64_000,
        upload_bar_refresh_sec: 0.5,
        api_version:            API_V2,
        synchronous:            true
      }.freeze
      DEFAULT_BASE_PATH = '/aspera/http-gwy'
      LOG_WS_SEND = 'ws: send: '.red
      LOG_WS_RECV = 'ws: recv: '.green
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
          "send_txt: #{msg_type}: #{JSON.generate(log_data)}"
        end
        ws_send(JSON.generate({msg_type => payload}))
      end

      def ws_send(data_to_send, type: :text)
        Log.log.debug{"#{LOG_WS_SEND}sending: #{type}"}
        @shared_info[:count][:sent_general] += 1 if type.eql?(:binary)
        Log.log.debug{"#{LOG_WS_SEND}counts: #{@shared_info[:count]}"}
        frame_generator = ::WebSocket::Frame::Outgoing::Client.new(data: data_to_send, type: type, version: @ws_handshake.version)
        @ws_io.write(frame_generator.to_s)
      end

      # wait for all message sent to be acknowledged by HTTPGW server, and check presence of exception
      def wait_for_sent_msg_ack_or_end_read_thread
        if @options[:synchronous]
          @shared_info[:mutex].synchronize do
            while (@shared_info[:count][:received_general] != @shared_info[:count][:sent_general]) ||
                (@shared_info[:count][:received_v2_delimiter] != @shared_info[:count][:sent_v2_delimiter])
              Log.log.debug{"#{LOG_WS_SEND}wait: counts: #{@shared_info[:count]}"}
              @shared_info[:cond_var].wait(@shared_info[:mutex], 1.0)
              raise @shared_info[:read_exception] unless @shared_info[:read_exception].nil?
              # if read thread exited, there will be no more updates
              break unless @ws_read_thread.alive?
            end
          end
        else
          raise @shared_info[:read_exception] unless @shared_info[:read_exception].nil?
        end
        Log.log.debug{"#{LOG_WS_SEND}sync ok: counts: #{@shared_info[:count]}"}
      end

      # message processing for read thread
      def process_received_message(message)
        Log.log.debug{"#{LOG_WS_RECV}message: [#{message}]"}
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
            while (frame_ok = frame_parser.next).nil?
              # blocking read
              frame_parser << @ws_io.read(1)
            end
            # Log.log.debug{"#{LOG_WS_RECV}type: #{frame_ok.class}"}
            process_received_message(frame_ok.data)
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
        # identify this session uniquely
        session_id = SecureRandom.uuid
        upload_url = File.join(@gw_api.params[:base_url], @options[:api_version], 'upload')
        # open web socket to end point (equivalent to Net::HTTP.start)
        http_session = Rest.start_http_session(upload_url)
        # get the underlying socket i/o
        @ws_io = Rest.io_http_session(http_session)
        @ws_handshake = ::WebSocket::Handshake::Client.new(url: upload_url, headers: {})
        @ws_io.write(@ws_handshake.to_s)
        sleep(0.1)
        @ws_handshake << @ws_io.readuntil("\r\n\r\n")
        raise 'Error in websocket handshake' unless @ws_handshake.finished?
        Log.log.debug{"#{LOG_WS_SEND}handshake success"}
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
        # start read thread
        @ws_read_thread = Thread.new {process_read_thread}
        # notify progress bar
        notify_begin(session_id, total_bytes_to_transfer)
        # first step send transfer spec
        Log.dump(:ws_spec, transfer_spec)
        ws_snd_json(MSG_SEND_TRANSFER_SPEC, transfer_spec)
        wait_for_sent_msg_ack_or_end_read_thread
        # current file index
        file_index = 0
        # aggregate size sent
        session_sent_bytes = 0
        # last progress event
        last_progress_time = nil
        # process each file
        transfer_spec['paths'].each do |item|
          slice_info = {
            name:         nil,
            # TODO: get mime type?
            type:         '',
            size:         item['file_size'],
            slice:        0, # current slice index
            # compute total number of slices
            total_slices: ((item['file_size'] - 1) / @options[:upload_chunk_size]) + 1,
            fileIndex:    file_index
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
                  ws_send(slice_bin_data, type: :binary)
                  Log.log.debug{"#{LOG_WS_SEND}sent bin buffer: #{file_index} / #{slice_info[:slice]}"}
                  # send once, after data, at end
                  ws_snd_json(MSG_SEND_SLICE_UPLOAD, slice_info) if slice_info[:slice].eql?(slice_info[:total_slices] - 1)
                end
                wait_for_sent_msg_ack_or_end_read_thread
              rescue Errno::EPIPE => e
                raise @shared_info[:read_exception] unless @shared_info[:read_exception].nil?
                raise e
              rescue Net::ReadTimeout => e
                Log.log.warn{'A timeout condition using HTTPGW may signal a permission problem on destination. Check ascp logs on httpgw.'}
                raise e
              end
              session_sent_bytes += slice_bin_data.length
              current_time = Time.now
              if last_progress_time.nil? || ((current_time - last_progress_time) > @options[:upload_bar_refresh_sec])
                notify_progress(session_id, session_sent_bytes)
                last_progress_time = current_time
              end
              slice_info[:slice] += 1
            end
          ensure
            file.close
          end
          file_index += 1
        end
        # throttling may have skipped last one
        notify_progress(session_id, session_sent_bytes)
        notify_end(session_id)
        Log.log.debug('Finished upload, waiting for end of read thread.')
        @ws_read_thread.join
        Log.log.debug{"Read thread joined, result: #{@shared_info[:count][:received_general]} / #{@shared_info[:count][:sent_general]}"}
        ws_send(nil, type: :close) unless @ws_io.nil?
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
        # init super class without arguments
        super()
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
        # remove /v1 from end of user-provided GW url: we need the base url only
        @options[:url].gsub(%r{/v1/*$}, '')
        @gw_api = Rest.new({base_url: @options[:url]})
        @api_info = @gw_api.read('v1/info')[:data]
        Log.dump(:api_info, @api_info)
        # web socket endpoint: by default use v2 (newer gateways), without base64 encoding
        # is the latest supported? else revert to old api
        if !@options[:api_version].eql?(API_V1)
          if !@api_info['endpoints'].any?{|i|i.include?(@options[:api_version])}
            Log.log.warn{"API version #{@options[:api_version]} not supported, reverting to #{API_V1}"}
            @options[:api_version] = API_V1
          end
        end
        @options.freeze
        Log.dump(:final_options, @options)
      end
    end # AgentHttpgw
  end
end
