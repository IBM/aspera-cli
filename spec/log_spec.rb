# frozen_string_literal: true

require 'spec_helper'
require 'aspera/log'
require 'stringio'

RSpec.describe(Aspera::Log) do
  let(:log) { described_class.instance }

  # Log to a string, restore singleton state afterwards
  around do |example|
    saved = {logger: log.logger, type: log.logger_type, format: log.dump_format}
    begin
      example.run
    ensure
      log.instance_variable_set(:@logger, saved[:logger])
      log.instance_variable_set(:@logger_type, saved[:type])
      log.dump_format = saved[:format]
    end
  end

  let(:output) { StringIO.new }

  before do
    log.instance_variable_set(:@logger, Logger.new(output))
    log.formatter = ->(_s, _d, _p, m) { "#{m}\n" }
  end

  describe '.dump' do
    it 'does nothing when level is not enabled' do
      log.level = :info
      described_class.dump(:obj, {'a' => 1})
      expect(output.string).to(be_empty)
    end

    it 'dumps object or block result as JSON or Ruby' do
      log.level = :debug
      described_class.dump(:obj, {'a' => 1})
      expect(output.string).to(include('(json)Hash=', '"a": 1'))
      log.dump_format = :ruby
      described_class.dump(:blk) { [1] }
      expect(output.string).to(include('(ruby)Array=', '[1]'))
    end

    it 'rejects both object and block' do
      log.level = :debug
      expect { described_class.dump(:x, 1) { 2 } }.to(raise_error(Aspera::AssertError))
    end

    it 'falls back to Ruby format when JSON fails' do
      log.level = :debug
      described_class.dump(:nan, Float::NAN)
      expect(output.string).to(include('NaN'))
    end

    it 'hides secrets' do
      log.level = :debug
      described_class.dump(:obj, {'password' => 'my_secret'})
      expect(output.string).not_to(include('my_secret'))
    end
  end

  it 'captures stderr at debug level' do
    log.level = :debug
    described_class.capture_stderr { $stderr.print('from stderr') }
    expect(output.string).to(include('from stderr'))
  end

  describe '#formatter=' do
    it 'accepts formatter names' do
      log.formatter = 'standard'
      log.logger.warn('msg')
      expect(output.string).to(match(/WARN -- : msg/))
    end

    it 'rejects unknown formatters' do
      expect { log.formatter = 'nope' }.to(raise_error(Aspera::Error, /Unknown formatter/))
      expect { log.formatter = 1 }.to(raise_error(Aspera::Error, /must be a String/))
    end
  end

  it 'sets and reads level' do
    log.level = :trace1
    expect(log.level).to(eq(:trace1))
    expect { log.level = :bad }.to(raise_error(Aspera::AssertError))
  end

  it 'changes logger type keeping level' do
    log.level = :warn
    log.logger_type = :stdout
    expect(log.logger_type).to(eq(:stdout))
    expect(log.level).to(eq(:warn))
    expect { log.logger_type = :bad }.to(raise_error(Aspera::InternalError))
  end

  describe '.caller_method' do
    # Named class to get a meaningful caller
    module LogSpecOuter
      class Inner
        def run(logger) = logger.info('x')
      end
    end

    it 'returns class and method calling the logger' do
      logger = Logger.new(output, formatter: ->(_s, _d, _p, m) { "#{described_class.caller_method}:#{m}\n" })
      LogSpecOuter::Inner.new.run(logger)
      expect(output.string).to(match(/(LogSpecOuter::Inner\.)?run:x/))
    end

    it 'returns placeholder outside of logger' do
      expect(described_class.caller_method).to(eq('???'))
    end
  end
end
