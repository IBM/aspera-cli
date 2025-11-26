# frozen_string_literal: true

require 'bundler'
class BuildTools
  class << self
    def gems_in_group(gemfile, group_name_symn)
      Bundler::Definition.build(gemfile, "#{gemfile}.lock", nil).dependencies.filter_map do |dep|
        next unless dep.groups.include?(group_name_symn)
        "#{dep.name}:#{dep.requirement.to_s.delete(' ')}"
      end
    end
  end
end

def run(*args)
  args = args.map(&:to_s)
  puts("Executing: #{args.join(' ')}")
  Aspera::Environment.secure_execute(exec: args.shift, args: args)
end
