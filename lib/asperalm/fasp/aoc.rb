require 'asperalm/fasp/manager'
require 'asperalm/log'
require 'singleton'

module Asperalm
  module Fasp
    class Aoc < Manager
      include Singleton
      private
      def initialize
        super
      end
    end
  end
end
