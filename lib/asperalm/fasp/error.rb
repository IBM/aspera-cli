module Asperalm
  module Fasp
    # error raised if transfer fails
    class Error < StandardError
      attr_reader :err_code
      def initialize(message,err_code=nil)
        super(message)
        @err_code = err_code
      end
    end
  end
end
