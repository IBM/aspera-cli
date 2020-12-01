#!/bin/echo this is a ruby class:
require 'aspera/fasp/manager'
require 'aspera/log'
require 'aspera/rest'

# ref: https://api.ibm.com/explorer/catalog/aspera/product/ibm-aspera/api/http-gateway-api/doc/guides-toc
module Aspera
  module Fasp
    # executes a local "ascp", connects mgt port, equivalent of "Fasp Manager"
    class HttpGW < Manager
      # start FASP transfer based on transfer spec (hash table)
      # note that it is asynchronous
      # HTTP download only supports file list
      def start_transfer(transfer_spec,options={})
        raise "GW URL must be set" unless !@gw_api.nil?
        raise "option: must be hash (or nil)" unless options.is_a?(Hash)
        raise "paths: must be Array" unless transfer_spec['paths'].is_a?(Array)
        case transfer_spec['direction']
        when 'send'
          # this is a websocket
          raise "error, not implemented"
        when 'receive'
          transfer_spec['zip_required']||=false
          transfer_spec['authentication']||='token'
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
