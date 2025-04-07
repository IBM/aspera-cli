#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler'

gemfile = ARGV.shift or raise 'Missing argument: Gemfile'
groupname = ARGV.shift or raise 'Missing argument: group name'

# Load the definition from the Gemfile and Gemfile.lock
definition = Bundler::Definition.build(gemfile, "#{gemfile}.lock", nil)
# Filter specs in the optional group
optional_specs = definition.dependencies.select do |dep|
  dep.groups.include?(groupname.to_sym)
end

# Print gem names and version requirements
optional_specs.each do |dep|
  print "'#{dep.name}:#{dep.requirement}' "
  # (#{dep.requirement})"
end
