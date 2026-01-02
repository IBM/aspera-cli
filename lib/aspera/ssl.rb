# frozen_string_literal: true

require 'openssl'
require 'aspera/assert'
require 'aspera/log'

module Aspera
  # Give possibility to globally override SSL options
  module SSL
    @extra_options = 0
    class << self
      @extra_options = OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:options]
      attr_reader :extra_options

      def option_list=(v)
        Aspera.assert_type(v, Array){'ssl_options'}
        v.each do |opt|
          Aspera.assert_type(opt, String, Integer){'Expected String or Integer in ssl_options'}
          case opt
          when Integer
            @extra_options = opt
          when String
            name = "OP_#{opt.start_with?('-') ? opt[1..] : opt}".upcase
            raise Cli::BadArgument, "Unknown ssl_option: #{name}, use one of: #{OpenSSL::SSL.constants.grep(/^OP_/).map{ |c| c.to_s.sub(/^OP_/, '')}.join(', ')}" if !OpenSSL::SSL.const_defined?(name)
            if opt.start_with?('-')
              @extra_options &= ~OpenSSL::SSL.const_get(name)
            else
              @extra_options |= OpenSSL::SSL.const_get(name)
            end
          end
        end
      end
    end
    def set_params(params = {})
      super(params)
      self.options = Aspera::SSL.extra_options unless Aspera::SSL.extra_options.nil?
      self
    end
  end
end
OpenSSL::SSL::SSLContext.prepend(Aspera::SSL)
