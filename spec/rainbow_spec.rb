# frozen_string_literal: true

require 'spec_helper'
require 'aspera/rainbow'

RSpec.describe(Aspera::Colors) do
  describe '.detect' do
    let(:env_vars) { %w[NO_COLOR CLICOLOR CLICOLOR_FORCE TERM] }

    around do |example|
      saved = env_vars.to_h { |var| [var, ENV.delete(var)] }
      example.run
    ensure
      saved.each { |var, value| value.nil? ? ENV.delete(var) : ENV.store(var, value) }
    end

    def terminal(tty)
      allow($stdout).to(receive(:tty?).and_return(tty))
      allow($stderr).to(receive(:tty?).and_return(tty))
    end

    it 'is enabled when both stdout and stderr are terminals' do
      terminal(true)
      expect(described_class.detect).to(be(true))
      allow($stderr).to(receive(:tty?).and_return(false))
      expect(described_class.detect).to(be(false))
    end

    it 'is disabled when not a terminal' do
      terminal(false)
      expect(described_class.detect).to(be(false))
    end

    it 'is disabled for a dumb terminal' do
      terminal(true)
      ENV['TERM'] = 'dumb'
      expect(described_class.detect).to(be(false))
    end

    it 'is disabled by NO_COLOR, unless empty' do
      terminal(true)
      ENV['NO_COLOR'] = ''
      expect(described_class.detect).to(be(true))
      ENV['NO_COLOR'] = '1'
      expect(described_class.detect).to(be(false))
      ENV['CLICOLOR_FORCE'] = '1'
      expect(described_class.detect).to(be(false))
    end

    it 'is disabled by CLICOLOR=0' do
      terminal(true)
      ENV['CLICOLOR'] = '0'
      expect(described_class.detect).to(be(false))
      ENV['CLICOLOR'] = '1'
      expect(described_class.detect).to(be(true))
    end

    it 'is forced by CLICOLOR_FORCE, unless 0 or empty' do
      terminal(false)
      ENV['CLICOLOR'] = '0'
      ENV['TERM'] = 'dumb'
      ENV['CLICOLOR_FORCE'] = 'yes'
      expect(described_class.detect).to(be(true))
      ENV['CLICOLOR_FORCE'] = '0'
      expect(described_class.detect).to(be(false))
      ENV['CLICOLOR_FORCE'] = ''
      expect(described_class.detect).to(be(false))
    end
  end
end
