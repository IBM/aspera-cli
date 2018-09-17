require 'asperalm/fasp/manager/local'

module Asperalm
  module Fasp
    module Manager
      # implements a resumable policy on top of basic Local FaspManager
      class Resumer < Local
        private

        alias super_start_transfer start_transfer

        public

       end # Resumer
    end # Agent
  end # Fasp
end # Asperalm
