# frozen_string_literal: true

module Aspera
  # Holds the executable name, environment variables and command line arguments for a spawned process,
  # and the temporary files it uses (for example a file list), which must exist until it ends.
  ExecSpec = Struct.new(:exec, :env, :args, :temp_files, keyword_init: true) do
    def initialize(exec: nil, env: {}, args: [], temp_files: [], **) = super

    # @return [ExecSpec] deep copy with independent :args, :env and :temp_files
    def deep_clone
      self.class.new(exec: exec, env: env.dup, args: args.dup, temp_files: temp_files.dup)
    end
  end
end
