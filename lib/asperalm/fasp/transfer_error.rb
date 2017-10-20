module Asperalm
  module Fasp
    # error raised if transfer fails
    class TransferError < StandardError
      attr_reader :err_code
      IS_MGR_ERROR=-1
      def initialize(message,err_code=IS_MGR_ERROR)
        super(message)
        @err_code = err_code
      end
    end
  end
end
