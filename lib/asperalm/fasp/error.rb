require 'asperalm/fasp/error_info'

module Asperalm
  module Fasp
    # error raised if transfer fails
    class Error < StandardError
      attr_reader :err_code
      def initialize(message,err_code=nil)
        super(message)
        @err_code = err_code
      end

      def info
        r=Fasp::ERROR_INFO[@err_code] || {r: false , c: 'UNKNOWN', m: 'unknown', a: 'unknown'}
        return r.merge({i: @err_code})
      end

      def retryable?; info[:r];end
    end
  end
end
