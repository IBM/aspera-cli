#!/bin/echo this is a ruby class:
#
# FASP manager for Ruby
# Aspera 2016
# Laurent Martin
#
##############################################################################
require 'socket'
require 'timeout'
require 'json'
require 'logger'
require 'base64'
require 'singleton'
require 'asperalm/fasp/listener'
require 'asperalm/fasp/error'
require 'asperalm/fasp/parameters'
require 'asperalm/fasp/resource_finder'
require 'asperalm/log'

# for file lists
#require 'tempfile'

module Asperalm
  module Fasp
    # Manages FASP based transfers based on local ascp command line
    class Manager
      # use "instance" class method
      include Singleton
      # transforms ABigWord into a_big_word
      def self.snake_case(str)
        str.
        gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
        gsub(/([a-z\d])([A-Z])/,'\1_\2').
        gsub(/([a-z\d])(usec)$/,'\1_\2').
        downcase
      end

      # user can also specify another location for ascp
      attr_accessor :ascp_path

      def initialize
        @ascp_path=Fasp::ResourceFinder.path(:ascp)
        @listeners=[]
      end

      # fields that shall be integer in JSON
      IntegerFields=['Rate','MinRate','Port','Priority','RateCap','MinRateCap','TCPPort','CreatePolicy','TimePolicy','DatagramSize','XoptFlags','VLinkVersion','PeerVLinkVersion','DSPipelineDepth','PeerDSPipelineDepth','ReadBlockSize','WriteBlockSize','ClusterNumNodes','ClusterNodeId','Size','Written','Loss','FileBytes','PreTransferBytes','TransferBytes','PMTU','Elapsedusec','ArgScansAttempted','ArgScansCompleted','PathScansAttempted','FileScansCompleted','TransfersAttempted','TransfersPassed','Delay']

      # event format
      Formats=[:text,:struct,:enhanced]

      # listener receives events
      def add_listener(listener,format=:struct)
        raise "unsupported format: #{format}" if !Formats.include?(format)
        @listeners.push({:listener=>listener,:format=>format})
        self
      end

      # translates legacy event into enhanced event
      def enhanced_event_format(event)
        return event.keys.inject({}) do |h,e|
          new_name=Manager.snake_case(e)
          value=event[e]
          value=value.to_i if IntegerFields.include?(e)
          h[new_name]=value
          h
        end
      end

      def notify_listeners(current_event_text,current_event_data)
        enhanced_event=nil
        @listeners.each do |listener|
          case listener[:format]
          when :text
            listener[:listener].event(current_event_text)
          when :struct
            listener[:listener].event(current_event_data)
          when :enhanced
            enhanced_event=enhanced_event_format(current_event_data) if enhanced_event.nil?
            listener[:listener].event(enhanced_event)
          else
            raise "unexpected format: #{listener[:format]}"
          end
        end
      end

      # This is the low level method to start FASP
      # currently, relies on command line arguments
      # start ascp with management port.
      # raises FaspError on error
      def start_transfer_with_args_env(ascp_params)
        raise Fasp::Error.new("no ascp path defined") if @ascp_path.nil?
        begin
          ascp_pid=nil
          ascp_arguments=ascp_params[:args].clone
          # open random local TCP port listening
          mgt_sock = TCPServer.new('127.0.0.1',0 )
          # add management port
          ascp_arguments.unshift('-M', mgt_sock.addr[1].to_s)
          # start ascp in sub process
          Log.log.info "execute: #{ascp_params[:env].map{|k,v| "#{k}=\"#{v}\""}.join(' ')} \"#{@ascp_path}\" \"#{ascp_arguments.join('" "')}\""
          ascp_pid = Process.spawn(ascp_params[:env],[@ascp_path,@ascp_path],*ascp_arguments)
          # in parent, wait for connection to socket max 3 seconds
          Log.log.debug "before accept for pid (#{ascp_pid})"
          ascp_mgt_io=nil
          Timeout.timeout( 3 ) do
            ascp_mgt_io = mgt_sock.accept
          end
          Log.log.debug "after accept (#{ascp_mgt_io})"

          # exact text for event, with \n
          current_event_text=''
          # parsed event (hash)
          current_event_data=nil

          # this is the last full status
          last_status_event=nil

          # read management port
          loop do
            # TODO: timeout here ?
            line = ascp_mgt_io.gets
            # nil when ascp process exits
            break if line.nil?
            current_event_text=current_event_text+line
            line.chomp!
            Log.log.debug "line=[#{line}]"
            case line
            when 'FASPMGR 2'
              # begin frame
              current_event_data = Hash.new
              current_event_text = ''
            when /^([^:]+): (.*)$/
              # payload
              current_event_data[$1] = $2
            when ''
              # end frame
              raise "unexpected empty line" if current_event_data.nil?
              notify_listeners(current_event_text,current_event_data)
              # TODO: check if this is always the last event
              if ['DONE','ERROR'].include?(current_event_data['Type']) then
                last_status_event = current_event_data
              end
            else
              raise "unexpected line:[#{line}]"
            end # case
          end # loop
          # check that last status was received before process exit
          raise "INTERNAL: nil last status" if last_status_event.nil?
          case last_status_event['Type']
          when 'DONE'
            return
          when 'ERROR'
            raise Fasp::Error.new(last_status_event['Description'],last_status_event['Code'].to_i)
          else
            raise "INTERNAL ERROR: unexpected last event"
          end
        rescue SystemCallError=> e
          # Process.spawn
          raise Fasp::Error.new(e.message)
        rescue Timeout::Error => e
          raise Fasp::Error.new('timeout waiting mgt port connect')
        rescue Interrupt => e
          raise Fasp::Error.new('transfer interrupted by user')
        ensure
          # ensure there is no ascp left running
          unless ascp_pid.nil?
            begin
              Process.kill('INT',ascp_pid)
            rescue
            end
            # avoid zombie
            Process.wait(ascp_pid)
            ascp_pid=nil
          end
        end
      end

      # start FASP transfer based on transfer spec (hash table)
      # note it returns upon completion
      def start_transfer(transfer_spec)
        start_transfer_with_args_env(Parameters.new(transfer_spec).compute_args)
        return nil
      end # start_transfer
    end # Manager
  end # Fasp
end # AsperaLm
