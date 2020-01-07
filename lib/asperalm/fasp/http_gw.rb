#!/bin/echo this is a ruby class:
require 'asperalm/fasp/manager'
require 'asperalm/fasp/resume_policy'
require 'asperalm/log'
require 'asperalm/rest'
require 'socket'
require 'timeout'
require 'singleton'
require 'securerandom'

module Asperalm
  module Fasp
    # executes a local "ascp", connects mgt port, equivalent of "Fasp Manager"
    class HttpGW < Manager
      include Singleton
      # set to false to keep ascp progress bar display (basically: removes ascp's option -q)
      attr_accessor :gw_api
      attr_accessor :resume_policy_parameters
      # start FASP transfer based on transfer spec (hash table)
      # note that it is asynchronous
      # HTTP download only supports file list
      def start_transfer(transfer_spec,options={})
        raise "GW URL must be set" unless !@gw_api.nil?
        raise "option: must be hash (or nil)" unless options.is_a?(Hash)
        raise "only one source allowed in http mode" unless transfer_spec['paths'].is_a?(Array) and transfer_spec['paths'].length.eql?(1)
        case transfer_spec['direction']
        when 'send'
          raise "error"
        when 'receive'
          transfer_spec['zip_required']=true
          transfer_spec['authentication']='token'
          transfer_spec['download_name']='my_download' # TODO
          transfer_spec['source_root']=transfer_spec['paths'].first['source']
          transfer_spec['paths'].first['source']='200KB.1' #TODO: how to get list of files ?
          creation=@gw_api.create('download',{'transfer_spec'=>transfer_spec})
          transfer_uuid=creation[:data]['url'].split('/').last
          file_dest=File.join(transfer_spec['destination_root'],'toto.bin')
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
        @gw_api=Rest.new({:base_url => api_url})
        api_info = @gw_api.read('info')[:data]
        Log.log.error("#{api_info}")
      end

      private

      def initialize
        super
        @gw_url=nil
      end

    end # LocalHttp
  end
end
