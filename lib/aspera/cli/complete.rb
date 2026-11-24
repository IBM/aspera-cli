# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

module Aspera
  module Cli
    # Values proposed by shell completion for an option, an argument or a schema key (`complete:`, `x-cli-complete`),
    # when they are not a list of allowed values:
    # - `file`: local file or folder
    # - `folder`: local folder
    # - `destination_folder`: local folder, unless the command sends files (the destination is then remote)
    # - `preset`: name of option preset
    # - `preset_parameter`: parameter of the option preset given as first argument of the command
    # - `transfer_job`: identifier of an asynchronous transfer job
    module Complete
      KINDS = %i[file folder destination_folder preset preset_parameter transfer_job].freeze
      # Kinds that complete to a local path chosen by the client: an argument with one of these must declare `access:` (see `Argument`)
      LOCAL_PATH_KINDS = %i[file folder].freeze
    end
  end
end
