#!/bin/echo this is a ruby class:
require 'aspera/fasp/manager'
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
    class HttpGW < Manager
      # message returned by HTTP GW in case of success
      OK_MESSAGE='end upload'
      # refresh rate for progress
      UPLOAD_REFRESH_SEC=0.5
      private_constant :OK_MESSAGE,:UPLOAD_REFRESH_SEC
      # send message on http gw web socket
      def ws_send(ws,type,data)
        ws.send(JSON.generate({type => data}))
      end

      def upload(transfer_spec)
        # total size of all files
        total_size=0
        # we need to keep track of actual file path because transfer spec is modified to be sent in web socket
        source_paths=[]
        # get source root or nil
        source_root = (transfer_spec.has_key?('source_root') and !transfer_spec['source_root'].empty?) ? transfer_spec['source_root'] : nil
        # source root is ignored by GW, used only here
        transfer_spec.delete('source_root')
        # compute total size of files to upload (for progress)
        # modify transfer spec to be suitable for GW
        transfer_spec['paths'].each do |item|
          # save actual file location to be able read contents later
          full_src_filepath=item['source']
          # add source root if needed
          full_src_filepath=File.join(source_root,full_src_filepath) unless source_root.nil?
          # GW expects a simple file name in 'source' but if user wants to change the name, we take it
          item['source']=File.basename(item['destination'].nil? ? item['source'] : item['destination'])
          item['file_size']=File.size(full_src_filepath)
          total_size+=item['file_size']
          # save so that we can actually read the file later
          source_paths.push(full_src_filepath)
        end

        session_id=SecureRandom.uuid
        ws=::WebSocket::Client::Simple::Client.new
        # error message if any in callback
        error=nil
        # number of files totally sent
        received=0
        # setup callbacks on websocket
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
        # open web socket to end point
        ws.connect("#{@gw_api.params[:base_url]}/upload")
        # async wait ready
        while !ws.open? and error.nil? do
          Log.log.info("ws: wait")
          sleep(0.2)
        end
        # notify progress bar
        notify_begin(session_id,total_size)
        # first step send transfer spec
        Log.dump(:ws_spec,transfer_spec)
        ws_send(ws,:transfer_spec,transfer_spec)
        # current file index
        file_index=0
        # aggregate size sent
        sent_bytes=0
        # last progress event
        lastevent=nil
        transfer_spec['paths'].each do |item|
          # TODO: get mime type?
          file_mime_type=''
          file_size=item['file_size']
          file_name=File.basename(item[item['destination'].nil? ? 'source' : 'destination'])
          # compute total number of slices
          numslices=1+(file_size-1)/@upload_chunksize
          File.open(source_paths[file_index]) do |file|
            # current slice index
            slicenum=0
            while !file.eof? do
              data=file.read(@upload_chunksize)
              slice_data={
                name: file_name,
                type: file_mime_type,
                size: file_size,
                data: Base64.strict_encode64(data),
                slice: slicenum,
                total_slices: numslices,
                fileIndex: file_index
              }
              # log without data
              Log.dump(:slide_data,slice_data.keys.inject({}){|m,i|m[i]=i.eql?(:data)?'base64 data':slice_data[i];m}) if slicenum.eql?(0)
              ws_send(ws,:slice_upload, slice_data)
              sent_bytes+=data.length
              currenttime=Time.now
              if lastevent.nil? or (currenttime-lastevent)>UPLOAD_REFRESH_SEC
                notify_progress(session_id,sent_bytes)
                lastevent=currenttime
              end
              slicenum+=1
              raise error unless error.nil?
            end
          end
          file_index+=1
        end
        ws.close
        notify_end(session_id)
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
        raise "only token based transfer is supported in GW" unless transfer_spec['token'].is_a?(String)
        Log.dump(:user_spec,transfer_spec)
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

    end # HttpGW
  end
end
