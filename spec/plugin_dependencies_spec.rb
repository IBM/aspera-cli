# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../build/lib/plugin_dependencies'

RSpec.describe(PluginDependencies) do
  let(:plugins_dir) { File.expand_path('../lib/aspera/plugins', __dir__) }
  let(:diagram) { File.expand_path("../docs/#{described_class::TAB}.drawio", __dir__) }

  # The diagram is generated, then committed: Graphviz is not needed to check it
  it 'shows the bundles and the dependencies of the manifests (else: rake doc:plugin_dependencies, then rake doc:diagrams)' do
    expected = described_class.graph(described_class.bundles(plugins_dir))
    expect(described_class.graph_of_drawio(File.read(diagram))).to(eq(expected))
  end

  it 'gives the kind of a bundle from its commands and its transfer agent' do
    kinds = described_class.bundles(plugins_dir).to_h { |bundle| [bundle[:name], bundle[:kind]] }
    expect(kinds.values_at('xfer', 'direct', 'node', 'aoc')).to(eq(%i[library agent both commands]))
  end

  it 'refuses a dependency on an unknown bundle' do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'one'))
      File.write(File.join(dir, 'one', 'plugin.yaml'), {'name' => 'one', 'title' => 'One', 'depends' => ['two']}.to_yaml)
      expect { described_class.bundles(dir) }.to(raise_error(RuntimeError, /one: unknown dependency two/))
    end
  end
end
