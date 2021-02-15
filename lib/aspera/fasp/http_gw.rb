#!/bin/echo this is a ruby class:
require 'aspera/fasp/manager'
require 'aspera/log'
require 'aspera/rest'
require 'websocket-client-simple'

#require 'websocket' # https://rdoc.info/github/imanel/websocket-ruby/frames

require 'openssl'
require 'base64'
require 'json'
require 'uri'

# ref: https://api.ibm.com/explorer/catalog/aspera/product/ibm-aspera/api/http-gateway-api/doc/guides-toc
module Aspera
  module Fasp
    # executes a local "ascp", connects mgt port, equivalent of "Fasp Manager"
    class HttpGW < Manager
      OK_MESSAGE='end upload'
      UPLOAD_REFRESH_SEC=0.5
      private_constant :OK_MESSAGE,:UPLOAD_REFRESH_SEC
      def ws_send(ws,type,data)
        ws.send(JSON.generate({type => data}))
      end

      def upload(transfer_spec)
        # precalculate size
        total_size=0
        transfer_spec['paths'].each do |item|
          total_size+=item['file_size']=File.size(item['source'])
        end
        session_id=123456
        ws=::WebSocket::Client::Simple::Client.new
        error=nil
        received=0
        ws.on :message do |msg|
          Log.log.info("ws: message: #{msg.data}")
          message=msg.data
          if message.eql?(OK_MESSAGE)
            received+=1
          else
            message.chomp!
            if message[0].eql?('"') and message[-1].eql?('"')
              error=JSON.parse(Base64.strict_decode64(message.chomp[1..-2]))['message']
            else
              error="expecting quotes in [#{message}]"
            end
          end
        end
        ws.on :error do |e|
          error=e
        end
        ws.on :open do
          Log.log.info("ws: open")
        end
        ws.on :close do
          Log.log.info("ws: close")
        end
        ws.connect("#{@gw_api.params[:base_url]}/upload")
        while !ws.open? and error.nil? do
          Log.log.info("ws: wait")
          sleep(0.2)
        end
        notify_listeners('emulated',{Manager::LISTENER_SESSION_ID_B=>session_id,'Type'=>'NOTIFICATION','PreTransferBytes'=>total_size})
        ws_send(ws,:transfer_spec,transfer_spec)
        filenum=0
        sent_bytes=0
        lastevent=Time.now-1
        transfer_spec['paths'].each do |item|
          destination_path=item['source']
          file_mime_type=''
          total=File.size(item['source'])
          numslices=1+(total-1)/@upload_chunksize
          slicenum=0
          File.open(item['source']) do |file|
            while !file.eof? do
              #puts "loop -------"
              data=file.read(@upload_chunksize)
              slice_data={
                name: destination_path,
                type: file_mime_type,
                size: total,
                data: Base64.strict_encode64(data),
                slice: slicenum,
                total_slices: numslices,
                fileIndex: filenum
              }
              ws_send(ws,:slice_upload, slice_data)
              sent_bytes+=data.length
              currenttime=Time.now
              if (currenttime-lastevent)>UPLOAD_REFRESH_SEC
                notify_listeners('emulated',{Manager::LISTENER_SESSION_ID_B=>session_id,'Type'=>'STATS','Bytescont'=>sent_bytes})
                lastevent=currenttime
              end
              slicenum+=1
              raise error unless error.nil?
            end
          end
          filenum+=1
        end
        ws.close
        notify_listeners('emulated',{Manager::LISTENER_SESSION_ID_B=>session_id,'Type'=>'DONE'})
      end

      def download(transfer_spec)
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
      end

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
          upload(transfer_spec)
        when 'receive'
          download(transfer_spec)
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
        @upload_chunksize=128000 # TODO: configurable ?
      end

    end # LocalHttp
  end
end
