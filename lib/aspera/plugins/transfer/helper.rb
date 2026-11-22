# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

module Aspera
  module Plugins
    module Transfer
      # Included by the commands of the bundles that transfer files (manifest: `depends: - transfer`):
      # the transfer agent is the service `transfer` of this bundle.
      # Single-file plugins use `Cli::Plugins::Base#transfer`.
      module Helper
        # @return [TransferAgent] Service `transfer` of the context of the plugin: created once, on first use
        # @raise [Cli::Error] If the bundle `transfer` is unavailable
        def transfer = context.service(:transfer)
      end
    end
  end
end
