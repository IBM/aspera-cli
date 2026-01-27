# frozen_string_literal: true

require 'yaml'

module Aspera
  module Yaml
    # @param node [Psych::Nodes::Node] YAML node
    # @param parent_path [Array<String>] Path of parent keys
    # @param duplicate_keys [Array<Hash>] Accumulated duplicate keys
    # @return [Array<String>] List of duplicate keys with their paths and occurrences
    def find_duplicate_keys(node, parent_path = nil, duplicate_keys = nil)
      duplicate_keys ||= []
      parent_path ||= []
      return duplicate_keys unless node.respond_to?(:children)
      if node.is_a?(Psych::Nodes::Mapping)
        counts = Hash.new(0)
        key_nodes = Hash.new{ |h, k| h[k] = []}
        node.children.each_slice(2) do |key_node, value_node|
          if key_node&.value
            counts[key_node.value] += 1
            key_nodes[key_node.value] << key_node
            find_duplicate_keys(value_node, parent_path + [key_node.value], duplicate_keys)
          end
        end
        counts.each do |key_str, count|
          next if count <= 1
          path = (parent_path + [key_str]).join('.')
          occurrences = key_nodes[key_str].map{ |kn| kn.start_line ? kn.start_line + 1 : 'unknown'}.map(&:to_s).join(', ')
          duplicate_keys << "#{path}: #{occurrences}"
        end
      else
        node.children.to_a.each{ |child| find_duplicate_keys(child, parent_path, duplicate_keys)}
      end
      duplicate_keys
    end

    # Safely load YAML content, raising an error if duplicate keys are found
    # @param yaml [String] YAML content
    # @return [Object] Parsed YAML content
    # @raise [RuntimeError] If duplicate keys are found
    def safe_load(yaml)
      duplicate_keys = find_duplicate_keys(Psych.parse_stream(yaml))
      raise "Duplicate keys: #{duplicate_keys.join('; ')}" unless duplicate_keys.empty?
      YAML.safe_load(yaml)
    end

    module_function :find_duplicate_keys, :safe_load
  end
end
