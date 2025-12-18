# frozen_string_literal: true

require 'bundler'
require 'yaml'
require 'aspera/log'
require 'aspera/rest'
require_relative 'paths'

# Log control
Aspera::Log.instance.level = :info
Aspera::Log.instance.level = ENV['RAKE_LOGLEVEL'].to_sym if ENV['RAKE_LOGLEVEL']
Aspera::RestParameters.instance.session_cb = lambda{ |http_session| http_session.set_debug_output(Aspera::LineLogger.new(:trace2)) if Aspera::Log.instance.logger.trace2?}

module BuildTools
  # @param gemfile [String] Path to gem file
  # @param group_name_sym [Symbol] Group name
  def gems_in_group(gemfile, group_name_sym)
    Bundler::Definition.build(gemfile, "#{gemfile}.lock", nil).dependencies.filter_map do |dep|
      next unless dep.groups.include?(group_name_sym)
      "#{dep.name}:#{dep.requirement.to_s.delete(' ')}"
    end
  end

  # Execute the command line (not in shell)
  def run(*args, **kwargs)
    args = args.first if args.length == 1 && args.first.is_a?(Array)
    args = args.map(&:to_s)
    puts(args.join(' '))
    background = kwargs.delete(:background)
    capture = kwargs.delete(:capture)
    if background
      Aspera::Environment.secure_spawn(exec: args.shift, args: args, **kwargs)
    elsif capture
      Aspera::Environment.secure_capture(exec: args.shift, args: args, **kwargs)
    else
      Aspera::Environment.secure_execute(exec: args.shift, args: args, **kwargs)
    end
  end

  def download_proto_file
    require 'aspera/ascp/installation'
    require 'aspera/cli/transfer_progress'
    tmp_proto_folder = ARGV.first
    Aspera::RestParameters.instance.progress_bar = Aspera::Cli::TransferProgress.new
    # Retrieve `transfer.proto` from the web
    Aspera::Ascp::Installation.instance.install_sdk(folder: tmp_proto_folder, backup: false, with_exe: false){ |name| name.end_with?('.proto') ? '/' : nil}
  end

  def yaml_list_duplicate_keys(node, parent_path = nil, duplicate_keys = nil)
    duplicate_keys ||= []
    parent_path ||= []
    if node.is_a?(Psych::Nodes::Mapping)
      # In a Mapping, every other child is the key node, the other is the value node.
      children = node.children.each_slice(2)
      duplicates = children.map{ |key_node, _| key_node}.group_by(&:value).select{ |_, nodes| nodes.size > 1}
      duplicates.each do |key, nodes|
        duplicate_keys << {
          key:         parent_path + [key],
          occurrences: nodes.map{ |occurrence| "line: #{occurrence.start_line + 1}"}
        }
      end
      children.each{ |key_node, value_node| yaml_list_duplicate_keys(value_node, parent_path + [key_node.value].compact, duplicate_keys)}
    else
      node.children.to_a.each{ |child| yaml_list_duplicate_keys(child, parent_path, duplicate_keys)}
    end
    duplicate_keys
  end

  def yaml_safe_load(yaml)
    duplicate_keys = yaml_list_duplicate_keys(Psych.parse_stream(yaml))
    raise "Duplicate keys: #{duplicate_keys}" unless duplicate_keys.empty?
    YAML.safe_load(yaml)
  end
  module_function :gems_in_group, :run, :download_proto_file, :yaml_safe_load, :yaml_list_duplicate_keys
end
