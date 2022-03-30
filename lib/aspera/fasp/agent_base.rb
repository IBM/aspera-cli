# frozen_string_literal: true

module Aspera
  module Fasp
    # Base class for FASP transfer agents
    # sub classes shall implement start_transfer and shutdown
    class AgentBase
      # fields description for JSON generation
      INTEGER_FIELDS = %w[Bytescont FaspFileArgIndex StartByte Rate MinRate Port Priority RateCap MinRateCap TCPPort CreatePolicy TimePolicy
                          DatagramSize XoptFlags VLinkVersion PeerVLinkVersion DSPipelineDepth PeerDSPipelineDepth ReadBlockSize WriteBlockSize
                          ClusterNumNodes ClusterNodeId Size Written Loss FileBytes PreTransferBytes TransferBytes PMTU Elapsedusec ArgScansAttempted
                          ArgScansCompleted PathScansAttempted FileScansCompleted TransfersAttempted TransfersPassed Delay].freeze
      BOOLEAN_FIELDS = %w[Encryption Remote RateLock MinRateLock PolicyLock FilesEncrypt FilesDecrypt VLinkLocalEnabled VLinkRemoteEnabled
                          MoveRange Keepalive TestLogin UseProxy Precalc RTTAutocorrect].freeze
      EXPECTED_METHODS = %i[text struct enhanced].freeze
      private_constant :INTEGER_FIELDS,:BOOLEAN_FIELDS,:EXPECTED_METHODS

      private

      # translates legacy event into enhanced (JSON) event
      def enhanced_event_format(event)
        return event.keys.each_with_object({}) do |e,h|
          # capital_to_snake_case
          new_name = e.
              gsub(/([a-z\d])([A-Z])/,'\1_\2').
              gsub(/([a-z\d])(usec)$/,'\1_\2').
              gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
              downcase
          value = event[e]
          value = value.to_i if INTEGER_FIELDS.include?(e)
          value = value.eql?('Yes') if BOOLEAN_FIELDS.include?(e)
          h[new_name] = value
        end
      end

      def initialize
        @listeners = []
      end

      def notify_listeners(current_event_text,current_event_data)
        Log.log.debug('send event to listeners')
        enhanced_event = nil
        @listeners.each do |listener|
          listener.event_text(current_event_text) if listener.respond_to?(:event_text)
          listener.event_struct(current_event_data) if listener.respond_to?(:event_struct)
          if listener.respond_to?(:event_enhanced)
            enhanced_event = enhanced_event_format(current_event_data) if enhanced_event.nil?
            listener.event_enhanced(enhanced_event)
          end
        end
      end # notify_listeners

      def notify_begin(id,size)
        notify_listeners('emulated',{LISTENER_SESSION_ID_B => id,'Type' => 'NOTIFICATION','PreTransferBytes' => size})
      end

      def notify_progress(id,size)
        notify_listeners('emulated',{LISTENER_SESSION_ID_B => id,'Type' => 'STATS','Bytescont' => size})
      end

      def notify_end(id)
        notify_listeners('emulated',{LISTENER_SESSION_ID_B => id,'Type' => 'DONE'})
      end

      public

      LISTENER_SESSION_ID_B = 'ListenerSessionId'
      LISTENER_SESSION_ID_S = 'listener_session_id'

      # listener receives events
      def add_listener(listener)
        raise "expect one of #{EXPECTED_METHODS}" if EXPECTED_METHODS.inject(0){|m,e|m += listener.respond_to?("event_#{e}") ? 1 : 0;m}.eql?(0)
        @listeners.push(listener)
        self
      end

      # This checks the validity of the value returned by wait_for_transfers_completion
      # it must be a list of :success or exception
      def self.validate_status_list(statuses)
        raise "internal error: bad statuses type: #{statuses.class}" unless statuses.is_a?(Array)
        raise "internal error: bad statuses content: #{statuses}" unless statuses.select{|i|!i.eql?(:success) && !i.is_a?(StandardError)}.empty?
      end

      # the following methods must be implemented by subclass:
      # start_transfer(transfer_spec,options) : start and wait for completion
      # wait_for_transfers_completion : wait for termination of all transfers, @return list of : :success or error message
      # optional: shutdown
    end
  end
end
