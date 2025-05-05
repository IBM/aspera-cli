#!/usr/bin/env ruby
# frozen_string_literal: true

# Displays list of gems and versin, suitable for installation with `gem install`

require 'bundler'

gemfile = ARGV.shift or raise 'Missing argument: Gemfile'
groupname = ARGV.shift or raise 'Missing argument: group name'

# Load the definition from the Gemfile and Gemfile.lock
definition = Bundler::Definition.build(gemfile, "#{gemfile}.lock", nil)
# Gem names and version requirements in the selected group
line = definition.dependencies.filter_map do |dep|
  next unless dep.groups.include?(groupname.to_sym)
  "'#{dep.name}:#{dep.requirement}'"
end.join(' ')

print(line)
