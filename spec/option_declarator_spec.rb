# frozen_string_literal: true

require 'spec_helper'
require 'aspera/cli/option_declarator'
require 'aspera/cli/parser'

RSpec.describe(Aspera::Cli::OptionDeclarator) do
  let(:dummy_class) do
    Class.new do
      extend Aspera::Cli::OptionDeclarator

      option :opt_a, description: 'Option A', default: 'val_a'
      option :opt_b, description: 'Option B', allowed: %i[one two]
    end
  end

  describe '.option' do
    it 'registers option specs' do
      expect(dummy_class.option_specs.keys).to(contain_exactly(:opt_a, :opt_b))
      expect(dummy_class.option_specs[:opt_a].description).to(eq('Option A'))
      expect(dummy_class.option_specs[:opt_a].default).to(eq('val_a'))
      expect(dummy_class.option_specs[:opt_b].allowed).to(eq(%i[one two]))
    end

    it 'raises on duplicate option' do
      expect do
        dummy_class.option(:opt_a, description: 'Duplicate')
      end.to(raise_error(ArgumentError, /Duplicate option/))
    end
  end

  describe '.declare_options' do
    it 'declares options onto a parser' do
      parser = instance_double(Aspera::Cli::Parser)
      allow(parser).to(receive(:option_declared?).and_return(false))
      allow(parser).to(receive(:declare))

      dummy_class.declare_options(parser)

      expect(parser).to(have_received(:declare).with(:opt_a, hash_including(description: 'Option A', default: 'val_a')))
      expect(parser).to(have_received(:declare).with(:opt_b, hash_including(description: 'Option B', allowed: %i[one two])))
    end

    it 'skips already declared options' do
      parser = instance_double(Aspera::Cli::Parser)
      allow(parser).to(receive(:option_declared?).with(:opt_a).and_return(true))
      allow(parser).to(receive(:option_declared?).with(:opt_b).and_return(false))
      allow(parser).to(receive(:declare))

      dummy_class.declare_options(parser)

      expect(parser).not_to(have_received(:declare).with(:opt_a, any_args))
      expect(parser).to(have_received(:declare).with(:opt_b, hash_including(description: 'Option B')))
    end
  end
end
