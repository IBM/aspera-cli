# frozen_string_literal: true

require 'bundler'
require 'yaml'
require 'aspera/log'
require_relative 'paths'

# Log control
Aspera::Log.instance.level = ENV.key?('LOG_LEVEL') ? ENV['LOG_LEVEL'].to_sym : :info
# Aspera::RestParameters.instance.session_cb = lambda{ |http_session| http_session.set_debug_output(Aspera::LineLogger.new(:trace2)) if Aspera::Log.instance.logger.trace2?}

module BuildTools
  # @see Aspera::Log#logger
  def log(*args, **kwargs, &block)
    Aspera::Log.instance.logger(*args, **kwargs, &block)
  end

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
    Aspera::Environment.secure_execute(*args, **kwargs)
  end

  # @param tmp_proto_folder [String] Temporary folder to download the proto file into
  def download_proto_file(tmp_proto_folder)
    require 'aspera/ascp/installation'
    require 'aspera/cli/transfer_progress'
    Aspera::RestParameters.instance.progress_bar = Aspera::Cli::TransferProgress.new
    # Retrieve `transfer.proto` from the web
    Aspera::Ascp::Installation.instance.install_sdk(folder: tmp_proto_folder, backup: false, with_exe: false){ |name| name.end_with?('.proto') ? '/' : nil}
  end

  # @param node [Psych::Nodes::Stream]
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

  # Safely load YAML content, raising an error if duplicate keys are found
  # @param yaml [String] YAML content
  # @return [Object] Parsed YAML content
  # @raise [RuntimeError] If duplicate keys are found
  def yaml_safe_load(yaml)
    duplicate_keys = yaml_list_duplicate_keys(Psych.parse_stream(yaml))
    raise "Duplicate keys: #{duplicate_keys}" unless duplicate_keys.empty?
    YAML.safe_load(yaml)
  end
  module_function :gems_in_group, :run, :download_proto_file, :yaml_safe_load, :yaml_list_duplicate_keys
end
