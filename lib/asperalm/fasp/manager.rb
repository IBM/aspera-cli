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
require 'asperalm/fasp/transfer_listener'
require 'asperalm/fasp/transfer_error'
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

      Formats=[:text,:struct,:enhanced]

      #
      def add_listener(listener,format=:struct)
        raise "unsupported format: #{format}" if !Formats.include?(format)
        @listeners.push({:listener=>listener,:format=>format})
        self
      end

      # fields that shall be integer in JSON
      IntegerFields=['Rate','MinRate','Port','Priority','RateCap','MinRateCap','TCPPort','CreatePolicy','TimePolicy','DatagramSize','XoptFlags','VLinkVersion','PeerVLinkVersion','DSPipelineDepth','PeerDSPipelineDepth','ReadBlockSize','WriteBlockSize','ClusterNumNodes','ClusterNodeId','Size','Written','Loss','FileBytes','PreTransferBytes','TransferBytes','PMTU','Elapsedusec','ArgScansAttempted','ArgScansCompleted','PathScansAttempted','FileScansCompleted','TransfersAttempted','TransfersPassed','Delay']

      def enhanced_event_format(event)
        return event.keys.inject({}) do |h,e|
          new_name=Manager.snake_case(e)
          value=event[e]
          value=value.to_i if IntegerFields.include?(e)
          h[new_name]=value
          h
        end
      end

      # This is the low level method to start FASP
      # currently, relies on command line arguments
      # start ascp with management port.
      # raises FaspError on error
      def start_transfer_with_args_env(all_params)
        arguments=all_params[:args]
        raise "no ascp path defined" if @ascp_path.nil?
        # open random local TCP port listening
        mgt_sock = TCPServer.new('127.0.0.1',0 )
        mgt_port = mgt_sock.addr[1]
        Log.log.debug "Port=#{mgt_port}"
        # add management port
        arguments.unshift('-M', mgt_port.to_s)
        Log.log.info "execute #{all_params[:env].map{|k,v| "#{k}=\"#{v}\""}.join(' ')} \"#{@ascp_path}\" \"#{arguments.join('" "')}\""
        begin
          ascp_pid = Process.spawn(all_params[:env],[@ascp_path,@ascp_path],*arguments)
        rescue SystemCallError=> e
          raise TransferError.new(e.message)
        end
        # in parent, wait for connection, max 3 seconds
        Log.log.debug "before accept for pid (#{ascp_pid})"
        client=nil
        begin
          Timeout.timeout( 3 ) do
            client = mgt_sock.accept
          end
        rescue Timeout::Error => e
          Process.kill 'INT',ascp_pid
        end
        Log.log.debug "after accept (#{client})"

        if client.nil? then
          # avoid zombie
          Process.wait ascp_pid
          raise TransferError.new('timeout waiting mgt port connect')
        end

        # records for one message
        current_event_data=nil
        current_event_text=''

        # this is the last full status
        last_event=nil

        # read management port
        loop do
          begin
            # check process still present, else receive Errno::ESRCH
            Process.getpgid( ascp_pid )
          rescue RangeError => e; break
          rescue Errno::ESRCH => e; break
          rescue NotImplementedError; nil # TODO: can we do better on windows ?
          end
          # TODO: timeout here ?
          line = client.gets
          if line.nil? then
            break
          end
          current_event_text=current_event_text+line
          line.chomp!
          Log.log.debug "line=[#{line}]"
          if  line.empty? then
            # end frame
            if !current_event_data.nil? then
              if !@listeners.nil? then
                newformat=nil
                @listeners.each do |listener|
                  case listener[:format]
                  when :text
                    listener[:listener].event(current_event_text)
                  when :struct
                    listener[:listener].event(current_event_data)
                  when :enhanced
                    newformat=enhanced_event_format(current_event_data) if newformat.nil?
                    listener[:listener].event(newformat)
                  else
                    raise :ERROR
                  end
                end
              end
              if ['DONE','ERROR'].include?(current_event_data['Type']) then
                last_event = current_event_data
              end
            else
              Log.log.error "unexpected empty line"
            end
          elsif 'FASPMGR 2'.eql? line then
            # begin frame
            current_event_data = Hash.new
            current_event_text = ''
          elsif m=line.match('^([^:]+): (.*)$') then
            current_event_data[m[1]] = m[2]
          else
            Log.log.error "error parsing[#{line}]"
          end
        end

        # wait for sub process completion
        Process.wait(ascp_pid)

        raise "nil last status" if last_event.nil?

        if 'DONE'.eql?(last_event['Type']) then
          return
        else
          raise TransferError.new(last_event['Description'],last_event['Code'].to_i)
        end
      end

      # start FASP transfer based on transfer spec (hash table)
      def start_transfer(transfer_spec)
        start_transfer_with_args_env(Parameters.new(transfer_spec).compute_args)
        return nil
      end # start_transfer
    end # Manager
  end # Fasp
end # AsperaLm
