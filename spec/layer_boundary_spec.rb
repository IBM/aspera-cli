# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# cspell:words sexp symbeg

require_relative '../lib/aspera/assert'
require 'bundler/setup'
require 'ripper'
require 'yaml'
require 'tmpdir'
require 'fileutils'

# Checks the layers of docs/ARCHITECTURE.md, section "Plugin bundles", by path:
# - framework: everything not listed below, references only the framework
# - domain library: agent, ascp, products, sync, transfer; references the framework (except cli/) and the domain
# - bundle: plugins/<name>/; references framework, domain, itself and the bundles of its `depends`
# A reference is a require path, or a constant. Comments and strings are not references.
# Files with the comment `# Shim:` are exempt.
module LayerBoundary
  DOMAIN_FOLDERS = %w[agent ascp products sync transfer].freeze
  # plugin files of cli/plugins that are part of the framework
  FRAMEWORK_PLUGIN_FILES = %w[base basic_auth oauth factory config mcp].freeze
  FRAMEWORK_PLUGIN_CONSTANTS = %w[Base BasicAuth Oauth Factory Config Mcp].freeze
  # file of api/ -> bundle that will own it
  API_FILE_BUNDLE = {
    'alee'     => 'alee',
    'aoc'      => 'aoc',
    'ats'      => 'ats',
    'cos_node' => 'cos',
    'faspex'   => 'faspex5',
    'httpgw'   => 'httpgw',
    'node'     => 'node',
    'queries'  => 'aoc'
  }.freeze
  # constant of Api -> bundle that will own it
  API_CONSTANT_BUNDLE = {
    'Alee'       => 'alee',
    'AoC'        => 'aoc',
    'Ats'        => 'ats',
    'CosNode'    => 'cos',
    'Faspex'     => 'faspex5',
    'Httpgw'     => 'httpgw',
    'Node'       => 'node',
    'NodeFileId' => 'node'
  }.freeze
  DOMAIN_CONSTANTS = %w[Agent Transfer Ascp Sync Products].freeze
  # constants that a bundle shall not use without the Aspera:: prefix (shadowed by the bundle classes)
  SHADOWED_CONSTANTS = %w[Agent Transfer Api].freeze
  SHIM_MARKER = '# Shim:'
  # tokens that do not matter to find constant paths
  SKIPPED_TOKENS = %i[on_sp on_nl on_ignored_nl on_comment on_embdoc_beg on_embdoc on_embdoc_end].freeze

  CONSTANT_END_TOKENS = %i[on_const on_rparen on_rbracket].freeze
  DEFINITION_KEYWORDS = %w[class module].freeze

  class << self
    # @param name [String] Constant name, e.g. Faspex5
    # @return [String] Plugin name
    def snake(name)
      name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end

    # @param name [String] Plugin name, e.g. faspex5 or cos_node
    # @return [String] Constant name, e.g. Faspex5 or CosNode
    def capital(name)
      name.split('_').map(&:capitalize).join
    end

    # @return [Hash] Layer description {layer:, bundle:, cli:} of a path relative to lib/aspera, without extension
    def path_target(rel)
      parts = rel.split('/')
      if parts[0].eql?('plugins') && parts.length > 2
        {layer: :bundle, bundle: parts[1]}
      elsif DOMAIN_FOLDERS.include?(parts[0])
        {layer: :domain}
      elsif parts[0].eql?('cli') && parts[1].eql?('plugins') && parts.length > 2
        return {layer: :framework, cli: true} if FRAMEWORK_PLUGIN_FILES.include?(parts[2])
        {layer: :bundle, bundle: parts[2]}
      elsif parts[0].eql?('api') && parts.length > 1
        Aspera.error_unexpected_value(parts[1]) unless API_FILE_BUNDLE.key?(parts[1])
        {layer: :bundle, bundle: API_FILE_BUNDLE[parts[1]]}
      else
        {layer: :framework, cli: parts[0].eql?('cli')}
      end
    end

    # @return [Hash] Layer of a source file, by path (a plugin file of cli/plugins is framework until it moves)
    def source_layer(rel)
      parts = rel.split('/')
      return {layer: :bundle, bundle: parts[1]} if parts[0].eql?('plugins') && parts.length > 2
      return {layer: :domain} if DOMAIN_FOLDERS.include?(parts[0])
      {layer: :framework}
    end

    # @return [Array<String>] Bundles that the bundle depends on
    def depends(aspera_dir, bundle)
      manifest = File.join(aspera_dir, 'plugins', bundle, 'plugin.yaml')
      return [] unless File.exist?(manifest)
      Array(YAML.safe_load_file(manifest)['depends'])
    end

    # @return [Boolean] true if source may reference target
    def allowed?(aspera_dir, source, target)
      case source[:layer]
      when :framework
        target[:layer].eql?(:framework)
      when :domain
        target[:layer].eql?(:domain) || (target[:layer].eql?(:framework) && !target[:cli])
      when :bundle
        case target[:layer]
        when :framework, :domain then true
        when :bundle then target[:bundle].eql?(source[:bundle]) || depends(aspera_dir, source[:bundle]).include?(target[:bundle])
        else Aspera.error_unexpected_value(target[:layer])
        end
      else Aspera.error_unexpected_value(source[:layer])
      end
    end

    # @param chain [Array<String>] Constant path, without leading Aspera
    # @return [Array] [target, text] or nil if the constant is not of interest
    def constant_target(chain)
      cli = false
      if chain[0].eql?('Cli')
        cli = true
        chain = chain.drop(1)
      end
      case chain[0]
      when 'Plugins'
        return if chain.length < 2
        return [{layer: :framework, cli: true}, "Plugins::#{chain[1]}"] if FRAMEWORK_PLUGIN_CONSTANTS.include?(chain[1])
        [{layer: :bundle, bundle: snake(chain[1])}, "Plugins::#{chain[1]}"]
      when 'Api'
        return if chain.length < 2
        Aspera.error_unexpected_value(chain[1]) unless API_CONSTANT_BUNDLE.key?(chain[1])
        [{layer: :bundle, bundle: API_CONSTANT_BUNDLE[chain[1]]}, "Api::#{chain[1]}"]
      when 'TransferAgent'
        [{layer: :bundle, bundle: 'transfer'}, 'TransferAgent']
      when *DOMAIN_CONSTANTS
        [{layer: :domain}, chain.first(2).join('::')]
      else
        [{layer: :framework, cli: true}, "Cli::#{chain[0]}"] if cli && chain[0]
      end
    end

    # @return [Array<Hash>] Constant paths of the code: {chain:, top:}, comments, strings and definitions excluded
    def constant_paths(source)
      tokens = Ripper.lex(source).reject { |t| SKIPPED_TOKENS.include?(t[1]) }
      result = []
      index = 0
      while index < tokens.length
        type = tokens[index][1]
        value = tokens[index][2]
        previous = index.positive? ? tokens[index - 1] : nil
        top = false
        if type.eql?(:on_op) && value.eql?('::') && tokens[index + 1]&.at(1).eql?(:on_const) && !CONSTANT_END_TOKENS.include?(previous&.at(1))
          top = true
          index += 1
          type = :on_const
        end
        unless type.eql?(:on_const)
          index += 1
          next
        end
        chain = [tokens[index][2]]
        index += 1
        while tokens[index]&.at(2).eql?('::') && tokens[index + 1]&.at(1).eql?(:on_const)
          chain.push(tokens[index + 1][2])
          index += 2
        end
        definition = previous && DEFINITION_KEYWORDS.include?(previous[2]) && previous[1].eql?(:on_kw)
        symbol = previous&.at(1).eql?(:on_symbeg)
        method_call = previous&.at(1).eql?(:on_period)
        result.push({chain: chain, top: top}) unless definition || symbol || method_call
      end
      result
    end

    # @return [Array<String>] Violations of one file: "<kind> <reference>"
    def file_violations(aspera_dir, file)
      rel = file.delete_prefix("#{aspera_dir}/")
      source = File.read(file)
      return [] if source.include?(SHIM_MARKER)
      source_info = source_layer(rel)
      found = []
      # require paths
      source.each_line do |line|
        match = line.match(/^\s*(require|require_relative)\s*\(?\s*(['"])([^'"#]+)\2/)
        next unless match
        if match[1].eql?('require')
          next unless match[3].start_with?('aspera/')
          required = match[3].delete_prefix('aspera/')
        else
          absolute = File.expand_path(match[3], File.dirname(file))
          # not in lib/aspera: other library file
          next unless absolute.start_with?("#{File.expand_path(aspera_dir)}/")
          required = absolute.delete_prefix("#{File.expand_path(aspera_dir)}/")
        end
        required = required.delete_suffix('.rb')
        found.push(['require', required, path_target(required)])
      end
      # constants
      constant_paths(source).each do |path|
        chain = path[:chain]
        qualified = path[:top] || chain[0].eql?('Aspera')
        chain = chain.drop(1) if chain[0].eql?('Aspera')
        next if chain.empty?
        if source_info[:layer].eql?(:bundle) && !qualified && SHADOWED_CONSTANTS.include?(chain[0]) && chain.length > 1
          found.push(['unqualified', chain.first(2).join('::'), nil])
          next
        end
        target, text = constant_target(chain)
        found.push(['const', text, target]) if target
      end
      # no target: always a violation
      found.filter_map do |kind, text, target|
        "#{kind} #{text}" if target.nil? || !allowed?(aspera_dir, source_info, target)
      end.uniq.sort
    end

    # @return [Hash] File (relative to aspera_dir) -> sorted violations, for all the files
    def violations(aspera_dir)
      Dir.glob("#{aspera_dir}/**/*.rb").sort.each_with_object({}) do |file, result|
        rel = file.delete_prefix("#{aspera_dir}/")
        # development files of bundles
        next if rel.match?(%r{\Aplugins/[^/]+/spec/})
        list = file_violations(aspera_dir, file)
        result[rel] = list unless list.empty?
      end
    end

    # Check of path <-> constant for the files of bundles
    # @return [Array<String>] Problems: files that do not define Aspera::Plugins::<Name>::<Const>
    def path_constant_problems(aspera_dir)
      Dir.glob("#{aspera_dir}/plugins/*/**/*.rb").sort.filter_map do |file|
        rel = file.delete_prefix("#{aspera_dir}/")
        parts = rel.split('/')
        next if parts[2].eql?('spec')
        next if File.read(file).include?(SHIM_MARKER)
        bundle_module = "Aspera::Plugins::#{capital(parts[1])}"
        base = File.basename(file, '.rb')
        # the file of a folder of a role (commands/*.rb) defines constants inside the role
        expected = parts.length > 3 ? parts[2..-2].map { |p| capital(p) }.join('::') : nil
        defined = defined_constants(File.read(file))
        ok = defined.any? do |name|
          next false unless name.start_with?("#{bundle_module}::")
          segments = name.delete_prefix("#{bundle_module}::").split('::')
          if expected
            segments.first(expected.split('::').length).join('::').downcase.eql?(expected.downcase)
          else
            segments.first.downcase.eql?(base.delete('_'))
          end
        end
        "#{rel}: no definition of #{bundle_module}::#{capital(base)}" unless ok
      end
    end

    # @return [Array<String>] Full names of classes and modules defined in the source
    def defined_constants(source)
      names = []
      walk = lambda do |node, nesting|
        return unless node.is_a?(Array)
        if %i[module class].include?(node[0]) && node[1].is_a?(Array)
          name = const_name(node[1])
          full = name ? nesting + name.split('::') : nesting
          names.push(full.join('::')) if name
          walk.call(node[-1], full)
        else
          node.each { |child| walk.call(child, nesting) }
        end
      end
      walk.call(Ripper.sexp(source), [])
      names
    end

    # @return [String] Name of a constant node of Ripper.sexp, or nil
    def const_name(node)
      case node[0]
      when :const_ref, :var_ref then const_name(node[1])
      when :@const then node[1]
      when :const_path_ref then [const_name(node[1]), const_name(node[2])].compact.join('::')
      end
    end
  end
end

RSpec.describe(LayerBoundary) do
  let(:aspera_dir) { File.expand_path('../lib/aspera', __dir__) }
  let(:known_file) { File.join(__dir__, 'fixtures', 'layer_boundary_known.yaml') }
  let(:known) { YAML.safe_load_file(known_file) }

  # Create files in a temporary folder that mimics lib/aspera
  # @param files [Hash] relative path -> content
  def with_tree(files)
    Dir.mktmpdir do |dir|
      files.each do |rel, content|
        path = File.join(dir, rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end
      yield(dir)
    end
  end

  describe 'current code' do
    it 'has no violation outside of the known list, and no obsolete known violation' do
      actual = described_class.violations(aspera_dir)
      new_ones = actual.flat_map { |file, list| (list - known.fetch(file, [])).map { |v| "#{file}: #{v}" } }
      obsolete = known.flat_map { |file, list| (list - actual.fetch(file, [])).map { |v| "#{file}: #{v}" } }
      expect(new_ones).to(be_empty, "new violations of the layer rules:\n#{new_ones.join("\n")}")
      expect(obsolete).to(be_empty, "known violations that no longer exist, remove them from #{known_file}:\n#{obsolete.join("\n")}")
    end

    it 'has a sorted known list' do
      expect(known.keys).to(eq(known.keys.sort))
      known.each_value { |list| expect(list).to(eq(list.sort.uniq)) }
    end

    it 'has files of bundles consistent with their constants' do
      expect(described_class.path_constant_problems(aspera_dir)).to(be_empty)
    end
  end

  describe 'checker' do
    it 'ignores comments and strings' do
      with_tree('rest/a.rb' => <<~RUBY) do |dir|
        # Agent::Direct, Plugins::Node and require_relative '../cli/plugins/node'
        x = 'Transfer::Spec'
        y = "Agent::Base 1"
        z = <<~TEXT
          Products::Other
        TEXT
      RUBY
        expect(described_class.violations(dir)).to(eq({}))
      end
    end

    it 'detects framework referencing domain or bundle, by require and by constant' do
      with_tree(
        'rest/a.rb'                => "require_relative '../agent/base'\nAspera::Agent::Direct\nTransferAgent\n",
        'rest/b.rb'                => "require 'aspera/cli/plugins/node'\nCli::Plugins::Aoc\nApi::AoC\nrequire 'aspera/cli/plugins/base'\n",
        'rest/c.rb'                => "require 'json'\nrequire_relative '../cli/plugins/config'\nCli::Plugins::Base\nAspera::Rest\n",
        'cli/plugins/transfer.rb'  => ''
      ) do |dir|
        expect(described_class.violations(dir)).to(eq(
          'rest/a.rb' => ['const Agent::Direct', 'const TransferAgent', 'require agent/base'],
          'rest/b.rb' => ['const Api::AoC', 'const Plugins::Aoc', 'require cli/plugins/node']
        ))
      end
    end

    it 'detects domain referencing cli or bundle, and accepts framework and domain' do
      with_tree(
        'transfer/a.rb' => "require_relative '../log'\nrequire_relative '../ascp/installation'\nAspera::Agent::Base\nRest::Client\n",
        'agent/b.rb'    => "require_relative '../cli/formatter'\nCli::Error\nPlugins::Node\nCli::Plugins::Base\n"
      ) do |dir|
        expect(described_class.violations(dir)).to(eq(
          'agent/b.rb' => ['const Cli::Error', 'const Plugins::Base', 'const Plugins::Node', 'require cli/formatter'].sort
        ))
      end
    end

    it 'applies depends to bundles' do
      with_tree(
        'plugins/aoc/plugin.yaml'  => "name: aoc\ndepends:\n  - node\n",
        'plugins/aoc/commands.rb'  => "require_relative '../node/api'\nrequire_relative '../ats/api'\nrequire_relative '../../agent/base'\nrequire_relative '../../rest'\n",
        'plugins/aoc/spec/a_spec.rb' => "require_relative '../../ats/api'\n",
        'plugins/node/api.rb'      => "Aspera::Plugins::Aoc::Commands\nAspera::Plugins::Node::Api\n"
      ) do |dir|
        expect(described_class.violations(dir)).to(eq(
          'plugins/aoc/commands.rb' => ['require plugins/ats/api'],
          'plugins/node/api.rb'     => ['const Plugins::Aoc']
        ))
      end
    end

    it 'detects shadowed constants not qualified in bundles' do
      with_tree(
        'plugins/node/agent.rb' => <<~RUBY
          module Aspera
            module Plugins
              module Node
                class Agent < Aspera::Agent::Base
                  def run
                    Transfer::Spec.new
                    Agent::Factory.create
                    ::Transfer::Spec.new
                    Aspera::Transfer::Spec.new
                    Api.new
                  end
                end
              end
            end
          end
        RUBY
      ) do |dir|
        expect(described_class.violations(dir)).to(eq('plugins/node/agent.rb' => ['unqualified Agent::Factory', 'unqualified Transfer::Spec']))
      end
    end

    it 'exempts shims' do
      with_tree('api/node.rb' => "# Shim: moved to aspera/plugins/node/api\nrequire_relative '../plugins/node/api'\nPlugins::Node::Api\n") do |dir|
        expect(described_class.violations(dir)).to(eq({}))
      end
    end

    it 'rejects an unknown Api constant' do
      with_tree('rest/a.rb' => "Api::Unknown\n") do |dir|
        expect { described_class.violations(dir) }.to(raise_error(Aspera::InternalError, /unexpected value/))
      end
    end

    it 'checks path and constant of bundle files' do
      with_tree(
        'plugins/cos_node/api.rb'       => "module Aspera\n  module Plugins\n    module CosNode\n      class Api\n      end\n    end\n  end\nend\n",
        'plugins/cos_node/ascmd.rb'     => "module Aspera\n  module Plugins\n    module CosNode\n      class AsCmd\n      end\n    end\n  end\nend\n",
        'plugins/cos_node/emulator.rb'  => "module Aspera\n  module Plugins\n    module CosNode\n      class Other\n      end\n    end\n  end\nend\n",
        'plugins/cos_node/wrong.rb'     => "module Aspera\n  module Plugins\n    module Cos\n      class Wrong\n      end\n    end\n  end\nend\n",
        'plugins/cos_node/compact.rb'   => "class Aspera::Plugins::CosNode::Compact\nend\n",
        'plugins/cos_node/commands/x.rb' => "module Aspera\n  module Plugins\n    module CosNode\n      module Commands\n        class X\n        end\n      end\n    end\n  end\nend\n",
        'plugins/cos_node/spec/x_spec.rb' => "nothing\n"
      ) do |dir|
        expect(described_class.path_constant_problems(dir)).to(eq([
          'plugins/cos_node/emulator.rb: no definition of Aspera::Plugins::CosNode::Emulator',
          'plugins/cos_node/wrong.rb: no definition of Aspera::Plugins::CosNode::Wrong'
        ]))
      end
    end
  end
end
