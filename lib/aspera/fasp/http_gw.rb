#!/bin/echo this is a ruby class:
require 'aspera/fasp/manager'
require 'aspera/log'
require 'aspera/rest'
require 'socket'
require 'websocket' # https://rdoc.info/github/imanel/websocket-ruby/frames
require 'openssl'
require 'base64'
require 'json'
require 'uri'

# ref: https://api.ibm.com/explorer/catalog/aspera/product/ibm-aspera/api/http-gateway-api/doc/guides-toc
module Aspera
  module Fasp
    class SimpleWs
      def initialize(url)
        url=url.gsub(/^http/,'ws')
        handshake=WebSocket::Handshake::Client.new(url: url, headers: { 'User-Agent' => 'ascli/4.0' })
        uri=URI.parse(url)
        @socket  = TCPSocket.new(uri.host, uri.port)
        if uri.scheme.eql?('wss')
          @socket = OpenSSL::SSL::SSLSocket.new(@socket)
          @socket.sync_close = true
          @socket.connect
          @socket.write(handshake.to_s)
        end
        handshake << @socket.readpartial(1024)
        raise "not finished" unless handshake.finished?
        raise "not valid" unless handshake.valid?
        @version=handshake.version
        @fr_from_server ||= WebSocket::Frame::Incoming::Server.new(version: @version)
        @process_from_server=nil
      end

      def process_from_server(&block)
        @process_from_server=block
      end

      def send_message(textdata)
        fr_to_server = WebSocket::Frame::Outgoing::Client.new(version: @version, data: textdata, type: :text)
        @socket.write(fr_to_server.to_s)
        if @socket.eof?
          raise "premature"
          return
        end
        readnet=@socket.readpartial(65536)
        @fr_from_server << readnet
        while f=@fr_from_server.next
          #puts "<<#{f.type}<#{f.to_s}"
          if f.type.eql?(:text)
            @process_from_server.call(f.to_s)
          else
            puts("ignore: error? #{f.error?}")
            puts("ignore: f #{f}")
          end
        end
        raise "@fr_from_server error:#{@fr_from_server.error}" if @fr_from_server.error?
      end
    end

    class FileSender
      OK_MESSAGE="end upload"
      def initialize(url)
        @chunksize=128000 # todo configurable ?
        @ws=SimpleWs.new(url)
        # process_from_server message from server
        @ws.process_from_server do |message|
          if !message.eql?(OK_MESSAGE)
            message.chomp!
            raise "expecting quotes in [#{message}]" unless message[0].eql?('"') and message[-1].eql?('"')
            err=JSON.parse(Base64.strict_decode64(message.chomp[1..-2]))
            raise err['message']
          end
        end
      end

      def send_msg(obj)
        @ws.send_message(JSON.generate(obj))
      end

      def upload(transfer_spec)
        #send_msg("xxx")
        send_msg({transfer_spec: transfer_spec})
        filenum=0
        transfer_spec['paths'].each do |item|
          source_path=item['source']
          destination_path=source_path
          file_type=''
          STDOUT.write("#{source_path}")
          total=File.size(source_path)
          numslices=1+(total-1)/@chunksize
          slicenum=0
          File.open(source_path) do |file|
            while !file.eof? do
              STDOUT.write(".")
              data=file.read(@chunksize)
              slice_data={
                name: destination_path,
                type: file_type,
                size: total,
                data: Base64.strict_encode64(data),
                slice: slicenum,
                total_slices: numslices,
                fileIndex: filenum
              }
              send_msg({slice_upload: slice_data})
              slicenum+=1
            end
            STDOUT.write("\n")
          end
          filenum+=1
        end
      end
    end

    # executes a local "ascp", connects mgt port, equivalent of "Fasp Manager"
    class HttpGW < Manager
      # start FASP transfer based on transfer spec (hash table)
      # note that it is asynchronous
      # HTTP download only supports file list
      def start_transfer(transfer_spec,options={})
        raise "GW URL must be set" unless !@gw_api.nil?
        raise "option: must be hash (or nil)" unless options.is_a?(Hash)
        raise "paths: must be Array" unless transfer_spec['paths'].is_a?(Array)
        raise "on token based transfer is supported in GW" unless transfer_spec['token'].is_a?(String)
        transfer_spec['authentication']||='token'
        case transfer_spec['direction']
        when 'send'
          # this is a websocket
          #raise "error, not implemented"
          FileSender.new("#{@gw_api.params[:base_url]}/upload").upload(transfer_spec)
        when 'receive'
          transfer_spec['zip_required']||=false
          transfer_spec['source_root']||='/'
          # is normally provided by application, like package name
          if !transfer_spec.has_key?('download_name')
            # by default it is the name of first file
            dname=File.basename(transfer_spec['paths'].first['source'])
            # we remove extension
            dname=dname.gsub(/\.@gw_api.*$/,'')
            # ands add indication of number of files if there is more than one
            if transfer_spec['paths'].length > 1
              dname=dname+" #{transfer_spec['paths'].length} Files"
            end
            transfer_spec['download_name']=dname
          end
          creation=@gw_api.create('download',{'transfer_spec'=>transfer_spec})[:data]
          transfer_uuid=creation['url'].split('/').last
          if transfer_spec['zip_required'] or transfer_spec['paths'].length > 1
            # it is a zip file if zip is required or there is more than 1 file
            file_dest=transfer_spec['download_name']+'.zip'
          else
            # it is a plain file if we don't require zip and there is only one file
            file_dest=File.basename(transfer_spec['paths'].first['source'])
          end
          file_dest=File.join(transfer_spec['destination_root'],file_dest)
          @gw_api.call({:operation=>'GET',:subpath=>"download/#{transfer_uuid}",:save_to_file=>file_dest})
        else
          raise "error"
        end
      end # start_transfer

      # wait for completion of all jobs started
      # @return list of :success or error message
      def wait_for_transfers_completion
        return [:success]
      end

      # terminates monitor thread
      def shutdown
      end

      def url=(api_url)
      end

      private

      def initialize(params)
        raise "params must be Hash" unless params.is_a?(Hash)
        params=params.symbolize_keys
        raise "must have only one param: url" unless params.keys.eql?([:url])
        super()
        @gw_api=Rest.new({:base_url => params[:url]})
        api_info = @gw_api.read('info')[:data]
        Log.log.info("#{api_info}")
      end

    end # LocalHttp
  end
end
