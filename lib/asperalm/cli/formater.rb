module Asperalm
  module Cli
    class Formater
      def initialize(opt_mgr)
        @opt_mgr=opt_mgr
      end

      # main output method
      def display_message(level,message)
        case level
        when :info
          if @opt_mgr.get_option(:format,:mandatory).eql?(:table) and
          @opt_mgr.get_option(:display,:mandatory).eql?(:info)
            STDOUT.puts(message)
          end
        when :data
          STDOUT.puts(message) unless @opt_mgr.get_option(:display,:mandatory).eql?(:error)
        when :error
          STDERR.puts(message)
        else raise "bad case"
        end
      end

      def display_status(status)
        display_message(:info,status)
      end
    end
  end
end
