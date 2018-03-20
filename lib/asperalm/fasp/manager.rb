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
require 'asperalm/fasp/installation'
require 'asperalm/log'
require 'asperalm/open_application'

module Asperalm
  module Fasp
    ACCESS_KEY_TRANSFER_USER='xfer'
    # Manages FASP based transfers based on local ascp process
    class Manager
      # use "instance" class method
      include Singleton
      # listener receives events
      def add_listener(listener,format=:struct)
        raise "unsupported format: #{format}" if !Formats.include?(format)
        # TODO: check that listener answers method "event" with one arg
        @listeners.push({:listener=>listener,:format=>format})
        self
      end

      # start FASP transfer based on transfer spec (hash table)
      # note that it returns upon completion only (blocking)
      # if the user wants to run in background, just spawn a thread
      # listener methods are called in context of calling thread
      def start_transfer(transfer_spec)
        Log.log.debug("ts=#{transfer_spec}")
        # suse bypass keys when authentication is token
        if transfer_spec['authentication'].eql?("token")
          # add Aspera private keys for web access, token based authorization
          transfer_spec['EX_ssh_key_paths'] = [ Installation.instance.path(:ssh_bypass_key_dsa), Installation.instance.path(:ssh_bypass_key_rsa) ]
          transfer_spec['drowssap_etomer'.reverse] = "%08x-%04x-%04x-%04x-%04x%08x" % "t1(\xBF;\xF3E\xB5\xAB\x14F\x02\xC6\x7F)P".unpack("NnnnnN")
        end
        # add fallback cert and key
        if ['1','force'].include?(transfer_spec['http_fallback'])
          transfer_spec['EX_fallback_key']=Installation.instance.path(:fallback_key)
          transfer_spec['EX_fallback_cert']=Installation.instance.path(:fallback_cert)
        end
        start_transfer_with_args_env(Parameters.new(transfer_spec).compute_args)
        return nil
      end # start_transfer

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

      private

      # transforms ABigWord into a_big_word
      def self.snake_case(str)
        str.
        gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
        gsub(/([a-z\d])([A-Z])/,'\1_\2').
        gsub(/([a-z\d])(usec)$/,'\1_\2').
        downcase
      end

      def initialize
        @listeners=[]
        @sessions={}
      end

      # fields that shall be integer in JSON
      IntegerFields=['Bytescont','FaspFileArgIndex','StartByte','Rate','MinRate','Port','Priority','RateCap','MinRateCap','TCPPort','CreatePolicy','TimePolicy','DatagramSize','XoptFlags','VLinkVersion','PeerVLinkVersion','DSPipelineDepth','PeerDSPipelineDepth','ReadBlockSize','WriteBlockSize','ClusterNumNodes','ClusterNodeId','Size','Written','Loss','FileBytes','PreTransferBytes','TransferBytes','PMTU','Elapsedusec','ArgScansAttempted','ArgScansCompleted','PathScansAttempted','FileScansCompleted','TransfersAttempted','TransfersPassed','Delay']
      BooleanFields=['Encryption','Remote','RateLock','MinRateLock','PolicyLock','FilesEncrypt','FilesDecrypt','VLinkLocalEnabled','VLinkRemoteEnabled','MoveRange','Keepalive','TestLogin','UseProxy','Precalc','RTTAutocorrect']
      # event format
      Formats=[:text,:struct,:enhanced]

      # translates legacy event into enhanced (JSON) event
      def enhanced_event_format(event)
        return event.keys.inject({}) do |h,e|
          new_name=Manager.snake_case(e)
          value=event[e]
          value=value.to_i if IntegerFields.include?(e)
          value=value.eql?('Yes') ? true : false if BooleanFields.include?(e)
          h[new_name]=value
          h
        end
      end

      # This is the low level method to start FASP
      # currently, relies on command line arguments
      # start ascp with management port.
      # raises FaspError on error
      # @param a hash containing :args and :env
      def start_transfer_with_args_env(ascp_params)
        Log.log.debug("ascp_params=#{ascp_params.inspect}")
        ascp_path=File.join(Fasp::Installation.instance.path(:bin_folder),ascp_params[:ascp_bin])+OpenApplication.executable_extension
        raise Fasp::Error.new("no such file: #{ascp_path}") unless File.exist?(ascp_path)
        begin
          ascp_pid=nil
          ascp_arguments=ascp_params[:args].clone
          # open random local TCP port listening
          mgt_sock = TCPServer.new('127.0.0.1',0 )
          # add management port
          ascp_arguments.unshift('-M', mgt_sock.addr[1].to_s)
          # start ascp in sub process
          Log.log.debug "execute: #{ascp_params[:env].map{|k,v| "#{k}=\"#{v}\""}.join(' ')} \"#{ascp_path}\" \"#{ascp_arguments.join('" "')}\""
          ascp_pid = Process.spawn(ascp_params[:env],[ascp_path,ascp_path],*ascp_arguments)
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

    end # Manager
  end # Fasp
end # AsperaLm
