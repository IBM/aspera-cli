require 'asperalm/fasp/manager'
require 'asperalm/log'
require 'asperalm/on_cloud.rb'

module Asperalm
  module Fasp
    class Aoc < Manager
      def initialize(on_cloud_options)
        super()
        @api_oncloud=OnCloud.new(on_cloud_options)
        raise "UNDER WORK"
      end
    end
  end
end
