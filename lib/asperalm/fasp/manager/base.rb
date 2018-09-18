module Asperalm
  module Fasp
    module Manager
      # Base class for FASP transfer agents
      class Base

        private

        # fields that shall be integer in JSON
        IntegerFields=['Bytescont','FaspFileArgIndex','StartByte','Rate','MinRate','Port','Priority','RateCap','MinRateCap','TCPPort','CreatePolicy','TimePolicy','DatagramSize','XoptFlags','VLinkVersion','PeerVLinkVersion','DSPipelineDepth','PeerDSPipelineDepth','ReadBlockSize','WriteBlockSize','ClusterNumNodes','ClusterNodeId','Size','Written','Loss','FileBytes','PreTransferBytes','TransferBytes','PMTU','Elapsedusec','ArgScansAttempted','ArgScansCompleted','PathScansAttempted','FileScansCompleted','TransfersAttempted','TransfersPassed','Delay']
        BooleanFields=['Encryption','Remote','RateLock','MinRateLock','PolicyLock','FilesEncrypt','FilesDecrypt','VLinkLocalEnabled','VLinkRemoteEnabled','MoveRange','Keepalive','TestLogin','UseProxy','Precalc','RTTAutocorrect']
        ExpectedMethod=[:text,:struct,:enhanced]

        # translates legacy event into enhanced (JSON) event
        def enhanced_event_format(event)
          return event.keys.inject({}) do |h,e|
            # capital_to_snake_case
            new_name=e.
            gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
            gsub(/([a-z\d])([A-Z])/,'\1_\2').
            gsub(/([a-z\d])(usec)$/,'\1_\2').
            downcase
            value=event[e]
            value=value.to_i if IntegerFields.include?(e)
            value=value.eql?('Yes') ? true : false if BooleanFields.include?(e)
            h[new_name]=value
            h
          end
        end

        def initialize
          @listeners=[]
        end

        def notify_listeners(current_event_text,current_event_data)
          Log.log.debug("send event to listeners")
          enhanced_event=nil
          @listeners.each do |listener|
            listener.send(:event_text,current_event_text) if listener.respond_to?(:event_text)
            listener.send(:event_struct,current_event_data) if listener.respond_to?(:event_struct)
            if listener.respond_to?(:event_enhanced)
              enhanced_event=enhanced_event_format(current_event_data) if enhanced_event.nil?
              listener.send(:event_enhanced,enhanced_event)
            end
          end
        end # notify_listeners

        public

        # listener receives events
        def add_listener(listener)
          raise "expect one of #{ExpectedMethod}" if ExpectedMethod.inject(0){|m,e|m+=listener.respond_to?("event_#{e}")?1:0;m}.eql?(0)
          @listeners.push(listener)
          self
        end

        # synchronous
        def start_transfer(transfer_spec)
          raise "virtual method"
        end

        def shutdown(wait_for_sessions=false)
          raise "virtual method"
        end
      end
    end
  end
end
