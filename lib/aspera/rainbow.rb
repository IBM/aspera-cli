# frozen_string_literal: true

# Load Rainbow with terminal detection (tty, TERM=dumb, NO_COLOR, CLICOLOR, CLICOLOR_FORCE)
# and its String refinement.
# Each file using colors must still activate it with: using Rainbow
require 'rainbow'
require 'rainbow/refinement'

module Aspera
  # Detection of ANSI colors support, replaces the one of Rainbow
  # https://no-color.org
  # https://bixense.com/clicolors/
  module Colors
    class << self
      # @return [Boolean] true if ANSI colors shall be used, from environment and terminal
      def detect
        return false if env_set?('NO_COLOR')
        return true if env_set?('CLICOLOR_FORCE') && !ENV['CLICOLOR_FORCE'].eql?('0')
        return false if ENV['CLICOLOR'].eql?('0')
        $stdout.tty? && $stderr.tty? && !ENV['TERM'].eql?('dumb')
      end

      private

      # @return [Boolean] true if the env var is set and not empty
      def env_set?(name)
        !ENV.fetch(name, '').empty?
      end
    end
  end
end

Rainbow.enabled = Aspera::Colors.detect
