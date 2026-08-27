# frozen_string_literal: true

require 'aspera/cli/mailer'

module Aspera
  module Cli
    # Standalone email service wrapping the Mailer mixin.
    # Injected into Context as :mailer so that any component (TransferAgent,
    # plugins, …) can send emails without going through Plugins::Config.
    class MailerService
      include Mailer

      # @param options     [Options]  CLI options manager (provides :smtp, :notify_to, :notify_template)
      # @param main_folder [String]   application main folder (unused directly but kept for symmetry)
      def initialize(options, main_folder)
        @options     = options
        @main_folder = main_folder
      end

      # @return [Options]
      attr_reader :options
    end
  end
end
