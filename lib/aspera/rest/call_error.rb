# frozen_string_literal: true

module Aspera
  module Rest
    # raised on error after REST call
    class CallError < StandardError
      def request
        @context[:request]
      end

      def response
        @context[:response]
      end

      def data
        @context[:data]
      end

      # @param context [Hash,String] with keys :messages, :request, :response, :data
      def initialize(context)
        context = {messages: [context]} if context.is_a?(String)
        @context = context
        super(@context[:messages].join("\n"))
      end
    end
  end
end
