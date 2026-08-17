# frozen_string_literal: true

module Aspera
  # Holds the executable name, environment variables and command line arguments for a spawned process.
  ExecSpec = Struct.new(:exec, :env, :args, keyword_init: true) do
    def initialize(exec: nil, env: {}, args: [], **) = super

    # @return [ExecSpec] deep copy with independent :args and :env
    def deep_clone
      self.class.new(exec: exec, env: env.dup, args: args.dup)
    end
  end
end
