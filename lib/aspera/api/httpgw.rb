# frozen_string_literal: true

require 'aspera/log'
require 'aspera/rest'
require 'aspera/transfer/faux_file'
require 'aspera/assert'
require 'securerandom'
require 'websocket'
require 'base64'
require 'json'

module Aspera
  module Api
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
    class Httpgw < Aspera::Rest
      DEFAULT_BASE_PATH = '/aspera/http-gwy'
      INFO_ENDPOINT = 'info'
      MSG_SEND_TRANSFER_SPEC = 'transfer_spec'
      MSG_SEND_SLICE_UPLOAD = 'slice_upload'
      MSG_RECV_DATA_RECEIVED_SIGNAL = 'end upload'
      MSG_RECV_SLICE_UPLOAD_SIGNAL = 'end_slice_upload'
      # upload API versions
      API_V1 = 'v1'
      API_V2 = 'v2'
      THR_RECV = 'recv'
      LOG_WS_SEND = 'ws: send: '.red
      LOG_WS_RECV = "ws: #{THR_RECV}: ".green
      private_constant :MSG_RECV_DATA_RECEIVED_SIGNAL, :MSG_RECV_SLICE_UPLOAD_SIGNAL
      # send message on http gw web socket
      def ws_snd_json(msg_type, payload)
        if msg_type.eql?(MSG_SEND_SLICE_UPLOAD) && @upload_version.eql?(API_V2)
          @shared_info[:count][:sent_v2_delimiter] += 1
        else
          @shared_info[:count][:sent_general] += 1
        end
        Log.log.trace1 do
          log_data = payload.dup
          log_data[:data] = "[data #{log_data[:data].length} bytes]" if log_data.key?(:data)
          "#{LOG_WS_SEND}json: #{msg_type}: #{JSON.generate(log_data)}"
        end
        ws_send(ws_type: :text, data: JSON.generate({msg_type => payload}))
      end

      # send data on http gw web socket
      def ws_send(ws_type:, data:)
        Log.log.trace1{"#{LOG_WS_SEND}sending: #{ws_type} (#{data&.length || 0} bytes)"}
        @shared_info[:count][:sent_general] += 1 if ws_type.eql?(:binary)
        frame_generator = ::WebSocket::Frame::Outgoing::Client.new(data: data, type: ws_type, version: @ws_handshake.version)
        @ws_io.write(frame_generator.to_s)
        if @synchronous
          @shared_info[:mutex].synchronize do
            # if read thread exited, there will be no more updates
            # we allow for 1 of difference else it stays blocked
            while @ws_read_thread.alive? &&
                @shared_info[:read_exception].nil? &&
                (((@shared_info[:count][:sent_general] - @shared_info[:count][:received_general]) > 1) ||
                  ((@shared_info[:count][:received_v2_delimiter] - @shared_info[:count][:sent_v2_delimiter]) > 1))
              if !@shared_info[:cond_var].wait(@shared_info[:mutex], 2.0)
                Log.log.trace1{"#{LOG_WS_SEND}#{'timeout'.blue}: #{@shared_info[:count]}"}
              end
            end
          end
        end
        raise @shared_info[:read_exception] unless @shared_info[:read_exception].nil?
        Log.log.trace2{"#{LOG_WS_SEND}counts: #{@shared_info[:count]}"}
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
            Log.log.trace2{"#{LOG_WS_RECV}read: #{byte} (#{byte.class}) eof=#{@ws_io.eof?}"}
            frame_parser << byte
            frame_ok = frame_parser.next
            next if frame_ok.nil?
            process_received_message(frame_ok.data.to_s)
            Log.log.trace2{"#{LOG_WS_RECV}counts: #{@shared_info[:count]}"}
          rescue => e
            Log.log.debug{"#{LOG_WS_RECV}Exception: #{e}"}
            @shared_info[:mutex].synchronize do
              @shared_info[:read_exception] = e
              @shared_info[:cond_var].signal
            end
            break
          end
        end
        Log.log.debug do
          "#{LOG_WS_RECV}exception: #{@shared_info[:read_exception]},cls=#{@shared_info[:read_exception].class})"
        end unless @shared_info[:read_exception].nil?
        Log.log.debug{"#{LOG_WS_RECV}read thread stopped (ws eof=#{@ws_io.eof?})"}
      end

      def upload(transfer_spec)
        # identify this session uniquely
        session_id = SecureRandom.uuid
        @notify_cb&.call(:sessions_init, info: 'starting')
        # process files to send, modify `paths` in transfer_spec
        files_to_send = process_upload_list(transfer_spec)
        # total size of all files is last element
        total_bytes_to_transfer = files_to_send.pop
        Log.dump(:modified_tspec, transfer_spec, level: :trace1)
        Log.dump(:files_to_send, files_to_send, level: :trace1)
        # TODO: check that this is available in endpoints: @api_info['endpoints']
        upload_url = File.join(@gw_root_url, @upload_version, 'upload')
        @notify_cb&.call(:sessions_init, info: 'connecting wss')
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
        # start read thread after handshake
        @ws_read_thread = Thread.new{process_read_thread}
        @notify_cb&.call(:session_start, session_id: session_id)
        @notify_cb&.call(:session_size, session_id: session_id, info: total_bytes_to_transfer)
        sleep(1)
        # notify progress bar
        @notify_cb&.call(:session_size, session_id: session_id, info: total_bytes_to_transfer)
        # first step send transfer spec
        ws_snd_json(MSG_SEND_TRANSFER_SPEC, transfer_spec)
        # current file index
        file_index = 0
        # aggregate size sent
        session_sent_bytes = 0
        # process each file
        files_to_send.each do |file_to_send|
          last_slice = (file_to_send[:size] - 1) / @upload_chunk_size
          slice_info = {
            name:         file_to_send[:name],
            # TODO: get mime type?
            type:         'application/octet-stream',
            size:         file_to_send[:size],
            slice:        0, # current slice index
            # index of last slice (i.e number of slices - 1)
            total_slices: last_slice + 1,
            fileIndex:    file_index
          }
          file = file_to_send[:file]
          file = File.open(file) unless file.is_a?(Transfer::FauxFile)
          begin
            until file.eof?
              slice_bin_data = file.read(@upload_chunk_size)
              # interrupt main thread if read thread failed
              raise @shared_info[:read_exception] unless @shared_info[:read_exception].nil?
              begin
                if @upload_version.eql?(API_V1)
                  slice_info[:data] = Base64.strict_encode64(slice_bin_data)
                  ws_snd_json(MSG_SEND_SLICE_UPLOAD, slice_info)
                else
                  # send once, before data, at beginning
                  ws_snd_json(MSG_SEND_SLICE_UPLOAD, slice_info) if slice_info[:slice].eql?(0)
                  ws_send(ws_type: :binary, data: slice_bin_data)
                  Log.log.trace1{"#{LOG_WS_SEND}buffer: file: #{file_index}, slice: #{slice_info[:slice]}/#{last_slice}"}
                  # send once, after data, at end
                  ws_snd_json(MSG_SEND_SLICE_UPLOAD, slice_info) if slice_info[:slice].eql?(last_slice)
                end
              rescue Errno::EPIPE => e
                raise @shared_info[:read_exception] unless @shared_info[:read_exception].nil?
                raise e
              rescue Net::ReadTimeout => e
                Log.log.warn{'A timeout condition using HTTPGW may signal a permission problem on destination. Check ascp logs on httpgw.'}
                raise e
              end
              session_sent_bytes += slice_bin_data.length
              @notify_cb&.call(:transfer, session_id: session_id, info: session_sent_bytes)
              slice_info[:slice] += 1
            end
          ensure
            file.close
          end
          file_index += 1
        end
        # throttling may have skipped last one
        @notify_cb&.call(:transfer, session_id: session_id, info: session_sent_bytes)
        @notify_cb&.call(:session_end, session_id: session_id)
        @notify_cb&.call(:end)
        ws_send(ws_type: :close, data: nil)
        Log.log.debug("Finished upload, waiting for end of #{THR_RECV} thread.")
        @ws_read_thread.join
        Log.log.debug{'Read thread joined'}
        # session no more used
        @ws_io = nil
        http_session&.finish
      end

      def download(transfer_spec)
        transfer_spec['source_root'] ||= '/'
        default_file_name = transfer_spec['paths'].first['source']
        source_is_folder = %w[. /].include?(default_file_name)
        default_file_name = 'http_download' if source_is_folder
        transfer_spec['zip_required'] ||= source_is_folder || transfer_spec['paths'].length > 1
        # is normally provided by application, like package name
        if !transfer_spec.key?('download_name')
          # by default it is the name of first file
          download_name = File.basename(default_file_name, '.*')
          # add indication of number of files if there is more than one
          if transfer_spec['paths'].length > 1
            download_name += " #{transfer_spec['paths'].length} Files"
          end
          transfer_spec['download_name'] = download_name
        end
        # start transfer session on httpgw
        creation = create('download', {'transfer_spec' => transfer_spec})
        transfer_uuid = creation['url'].split('/').last
        file_name =
          if transfer_spec['zip_required'] || transfer_spec['paths'].length > 1
            # it is a zip file if zip is required or there is more than 1 file
            transfer_spec['download_name'] + '.zip'
          else
            # it is a plain file if we don't require zip and there is only one file
            File.basename(default_file_name)
          end
        file_path = File.join(transfer_spec['destination_root'], file_name)
        call(operation: 'GET', subpath: "download/#{transfer_uuid}", save_to_file: file_path)
      end

      def info
        return @api_info
      end

      # @return the base url of the gateway
      def base_url
        return @gw_root_url
      end

      # @param url [String] URL of the HTTP Gateway, without version
      def initialize(
        url:,
        api_version:       API_V2,
        upload_chunk_size: 64_000,
        synchronous:       false,
        notify_cb:         nil,
        **opts
      )
        Log.dump(:gw_url, url)
        # add scheme if missing
        url = "https://#{url}" unless url.match?(%r{^[a-z]{1,6}://})
        raise Error, 'GW URL shall be with scheme https' unless url.start_with?('https://')
        # remove trailing slash and version (o=only once) if present
        # TODO: issue warning ?
        url = url.gsub(%r{/+$}, '').gsub(%r{/#{API_V1}$}o, '')
        # assume GW is always under specific path (TODO: remove this ?)
        url = File.join(url, DEFAULT_BASE_PATH) unless url.end_with?(DEFAULT_BASE_PATH)
        @gw_root_url = url
        super(base_url: "#{@gw_root_url}/#{API_V1}", **opts)
        @upload_version = api_version
        @upload_chunk_size = upload_chunk_size
        @synchronous = synchronous
        @notify_cb = notify_cb
        # get API info
        @api_info = read('info').freeze
        Log.dump(:api_info, @api_info)
        # web socket endpoint: by default use v2 (newer gateways), without base64 encoding
        # is the latest supported? else revert to old api
        if !@upload_version.eql?(API_V1)
          if !@api_info['endpoints'].any?{ |i| i.include?(@upload_version)}
            Log.log.warn{"API version #{@upload_version} not supported, reverting to #{API_V1}"}
            @upload_version = API_V1
          end
        end
        @shared_info = nil
        @ws_handshake = nil
        @ws_io = nil
        @ws_read_thread = nil
      end

      private

      # compute total size of files to upload (for progress)
      # modify transfer spec to be suitable for HTTPGW
      # @param transfer_spec [Hash] transfer specification
      # @return [Array] info on files to send
      def process_upload_list(transfer_spec)
        total_bytes_to_transfer = 0
        source_prefix = transfer_spec.key?('source_root') && !transfer_spec['source_root'].empty? ? transfer_spec['source_root'] + '/' : ''
        files_to_send = []
        transfer_spec['paths'].each do |one_path|
          source_path = source_prefix + one_path['source']
          faux_file = Transfer::FauxFile.create(source_path)
          if faux_file
            total_bytes_to_transfer += faux_file.size
            files_to_send.push({
              file: faux_file,
              name: faux_file.path,
              size: faux_file.size
            })
          elsif File.file?(source_path)
            # regular file
            file_size = File.size(source_path)
            total_bytes_to_transfer += file_size
            files_to_send.push({
              file: source_path,
              # GW expects a simple file name in 'source' but if user wants to change the name, we take it
              name: File.basename(one_path['destination'].nil? ? source_path : one_path['destination']),
              size: file_size
            })
          elsif File.directory?(source_path)
            folders_to_process = [source_path]
            until folders_to_process.empty?
              folder = folders_to_process.shift
              # read all entries
              Dir.entries(folder).each do |entry|
                next if entry.eql?('.') || entry.eql?('..')
                entry_path = File.join(folder, entry)
                if File.directory?(entry_path)
                  folders_to_process.push(entry_path)
                elsif File.file?(entry_path)
                  file_size = File.size(entry_path)
                  total_bytes_to_transfer += file_size
                  files_to_send.push({
                    file: entry_path,
                    name: entry_path,
                    size: file_size
                  })
                else
                  Log.log.warn{"Ignoring non file/directory: #{entry_path}"}
                end
              end
            end
          else
            raise "File not found: #{source_path}"
          end
        end
        transfer_spec['paths'] = files_to_send.map{ |i| {'source' => i[:name]}}
        files_to_send.push(total_bytes_to_transfer)
        return files_to_send
      end
    end
  end
end
