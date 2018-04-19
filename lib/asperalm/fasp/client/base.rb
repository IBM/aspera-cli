module Asperalm
  module Fasp
    module Client
      # Base class for FASP transfer agents, provides api for listeners
      class Base
        # fields that shall be integer in JSON
        IntegerFields=['Bytescont','FaspFileArgIndex','StartByte','Rate','MinRate','Port','Priority','RateCap','MinRateCap','TCPPort','CreatePolicy','TimePolicy','DatagramSize','XoptFlags','VLinkVersion','PeerVLinkVersion','DSPipelineDepth','PeerDSPipelineDepth','ReadBlockSize','WriteBlockSize','ClusterNumNodes','ClusterNodeId','Size','Written','Loss','FileBytes','PreTransferBytes','TransferBytes','PMTU','Elapsedusec','ArgScansAttempted','ArgScansCompleted','PathScansAttempted','FileScansCompleted','TransfersAttempted','TransfersPassed','Delay']
        BooleanFields=['Encryption','Remote','RateLock','MinRateLock','PolicyLock','FilesEncrypt','FilesDecrypt','VLinkLocalEnabled','VLinkRemoteEnabled','MoveRange','Keepalive','TestLogin','UseProxy','Precalc','RTTAutocorrect']
        # event format
        Formats=[:text,:struct,:enhanced]

        # transforms ABigWord into a_big_word
        def self.snake_case(str)
          str.
          gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
          gsub(/([a-z\d])([A-Z])/,'\1_\2').
          gsub(/([a-z\d])(usec)$/,'\1_\2').
          downcase
        end
        
        # translates legacy event into enhanced (JSON) event
        def enhanced_event_format(event)
          return event.keys.inject({}) do |h,e|
            new_name=self.class.snake_case(e)
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

        # listener receives events
        def add_listener(listener,format=:struct)
          raise "unsupported format: #{format}" if !Formats.include?(format)
          # TODO: check that listener answers method "event" with one arg
          @listeners.push({:listener=>listener,:format=>format})
          self
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
      end
    end
  end
end
