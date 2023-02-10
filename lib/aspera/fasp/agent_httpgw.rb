# frozen_string_literal: true

require 'aspera/fasp/agent_base'
require 'aspera/fasp/transfer_spec'
require 'aspera/log'
require 'aspera/rest'
require 'securerandom'
require 'websocket'
require 'base64'
require 'json'

# ref: https://api.ibm.com/explorer/catalog/aspera/product/ibm-aspera/api/http-gateway-api/doc/guides-toc
# https://developer.ibm.com/apis/catalog?search=%22aspera%20http%22
module Aspera
  module Fasp
    # start a transfer using Aspera HTTP Gateway, using web socket session for uploads
    class AgentHttpgw < Aspera::Fasp::AgentBase
      # message returned by HTTP GW in case of success
      MSG_END_UPLOAD = 'end upload'
      MSG_END_SLICE = 'end_slice_upload'
      # options available in CLI (transfer_info)
      DEFAULT_OPTIONS = {
        url:                    nil,
        upload_chunk_size:      64_000,
        upload_bar_refresh_sec: 0.5
      }.freeze
      DEFAULT_BASE_PATH = '/aspera/http-gwy'
      # upload endpoints
      V1_UPLOAD = '/v1/upload'
      V2_UPLOAD = '/v2/upload'
      private_constant :DEFAULT_OPTIONS, :MSG_END_UPLOAD, :MSG_END_SLICE, :V1_UPLOAD, :V2_UPLOAD

      # send message on http gw web socket
      def ws_snd_json(data)
        @slice_uploads += 1 if data.key?(:slice_upload)
        Log.log.debug{JSON.generate(data)}
        ws_send(JSON.generate(data))
      end

      def ws_send(data, type: :text)
        frame = ::WebSocket::Frame::Outgoing::Client.new(data: data, type: type, version: @ws_handshake.version)
        @ws_io.write(frame.to_s)
      end

      def upload(transfer_spec)
        # total size of all files
        total_size = 0
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
          total_size += item['file_size']
          # save so that we can actually read the file later
          source_paths.push(full_src_filepath)
        end
        # identify this session uniquely
        session_id = SecureRandom.uuid
        @slice_uploads = 0
        # web socket endpoint: by default use v2 (newer gateways), without base64 encoding
        upload_api_version = V2_UPLOAD
        # is the latest supported? else revert to old api
        upload_api_version = V1_UPLOAD unless @api_info['endpoints'].any?{|i|i.include?(upload_api_version)}
        Log.log.debug{"api version: #{upload_api_version}"}
        url = File.join(@gw_api.params[:base_url], upload_api_version)
        # uri = URI.parse(url)
        # open web socket to end point (equivalent to Net::HTTP.start)
        http_socket = Rest.start_http_session(url)
        @ws_io = http_socket.instance_variable_get(:@socket)
        # @ws_io.debug_output = Log.log
        @ws_handshake = ::WebSocket::Handshake::Client.new(url: url, headers: {})
        @ws_io.write(@ws_handshake.to_s)
        sleep(0.1)
        @ws_handshake << @ws_io.readuntil("\r\n\r\n")
        raise 'Error in websocket handshake' unless @ws_handshake.finished?
        Log.log.debug('ws: handshake success')
        # data shared between main thread and read thread
        shared_info = {
          read_exception: nil, # error message if any in callback
          end_uploads:    0 # number of files totally sent
          # mutex: Mutex.new
          # cond_var: ConditionVariable.new
        }
        # start read thread
        ws_read_thread = Thread.new do
          Log.log.debug('ws: thread: started')
          frame = ::WebSocket::Frame::Incoming::Client.new
          loop do
            begin # rubocop:disable Style/RedundantBegin
              frame << @ws_io.readuntil("\n")
              while (msg = frame.next)
                Log.log.debug{"ws: thread: message: #{msg.data} #{shared_info[:end_uploads]}"}
                message = msg.data
                if message.eql?(MSG_END_UPLOAD)
                  shared_info[:end_uploads] += 1
                elsif message.eql?(MSG_END_SLICE)
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
              end
            rescue => e
              shared_info[:read_exception] = e unless e.is_a?(EOFError)
              break
            end
          end
          Log.log.debug{"ws: thread: stopping (exc=#{shared_info[:read_exception]},cls=#{shared_info[:read_exception].class})"}
        end
        # notify progress bar
        notify_begin(session_id, total_size)
        # first step send transfer spec
        Log.dump(:ws_spec, transfer_spec)
        ws_snd_json(transfer_spec: transfer_spec)
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
              data = file.read(@options[:upload_chunk_size])
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
              raise shared_info[:read_exception] unless shared_info[:read_exception].nil?
              begin
                if upload_api_version.eql?(V1_UPLOAD)
                  slice_data[:data] = Base64.strict_encode64(data)
                  ws_snd_json(slice_upload: slice_data)
                else
                  ws_snd_json(slice_upload: slice_data) if slice_index.eql?(0)
                  ws_send(data, type: :binary)
                  Log.log.debug{"ws: sent buffer: #{file_index} / #{slice_index}"}
                  ws_snd_json(slice_upload: slice_data) if slice_index.eql?(slice_total - 1)
                end
              rescue Errno::EPIPE => e
                raise shared_info[:read_exception] unless shared_info[:read_exception].nil?
                raise e
              end
              sent_bytes += data.length
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

        Log.log.debug('Finished upload')
        ws_read_thread.join
        Log.log.debug{"result: #{shared_info[:end_uploads]} / #{@slice_uploads}"}
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
        Log.log.debug{"local options= #{opts}"}
        # set default options and override if specified
        @options = DEFAULT_OPTIONS.dup
        raise "httpgw agent parameters (transfer_info): expecting Hash, but have #{opts.class}" unless opts.is_a?(Hash)
        opts.symbolize_keys.each do |k, v|
          raise "httpgw agent parameter: Unknown: #{k}, expect one of #{DEFAULT_OPTIONS.keys.map(&:to_s).join(',')}" unless DEFAULT_OPTIONS.key?(k)
          @options[k] = v
        end
        raise 'missing param: url' if @options[:url].nil?
        # remove /v1 from end
        @options[:url].gsub(%r{/v1/*$}, '')
        super()
        @gw_api = Rest.new({base_url: @options[:url]})
        @api_info = @gw_api.read('v1/info')[:data]
        Log.log.info(@api_info.to_s)
      end
    end # AgentHttpgw
  end
end
