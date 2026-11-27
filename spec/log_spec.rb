# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require_relative '../lib/aspera/log'
require 'stringio'
require 'securerandom'
require 'base64'
require 'json'

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
      secret = SecureRandom.alphanumeric(12)
      described_class.dump(:obj, {'password' => secret})
      expect(output.string).not_to(include(secret))
    end

    it 'hides secrets by key name in the structure, without modifying it' do
      log.level = :debug
      secret = SecureRandom.alphanumeric(12)
      # An additional key is not known by the patterns applied to text
      key = "k#{SecureRandom.hex(4)}"
      Aspera::Secret::Hider.instance.add_secret_keys([key])
      data = {key => secret, 'list' => [Struct.new(:password).new(secret)]}
      %i[json ruby].each do |format|
        log.dump_format = format
        described_class.dump(:obj, data)
      end
      expect(output.string).not_to(include(secret))
      expect(data[key]).to(eq(secret))
      expect(data['list'].first.password).to(eq(secret))
    ensure
      Aspera::Secret::Hider.instance.instance_variable_get(:@additional_keys).delete(key)
    end

    it 'hides secrets by key name in a serialized structure in a string (e.g. raw HTTP body), whatever the dump format' do
      log.level = :trace1
      secret = SecureRandom.alphanumeric(12)
      body = JSON.generate({'access_token' => secret, 'token_type' => 'bearer'})
      %i[json ruby].each do |format|
        log.dump_format = format
        described_class.dump(:result_data_raw, body, level: :trace1)
      end
      expect(output.string).not_to(include(secret))
      expect(output.string).to(include('access_token', 'bearer'))
      expect(body).to(include(secret))
    end

    it 'shows the values of keys that are not secrets, e.g. token_type of a token response' do
      log.level = :debug
      secret = SecureRandom.alphanumeric(12)
      described_class.dump(:result_data, {'access_token' => secret, 'token_type' => 'bearer', 'expires_in' => 3600})
      expect(output.string).not_to(include(secret))
      expect(output.string).to(include('"access_token": "', '"token_type": "bearer"'))
    end

    it 'hides a structure encoded in base64 JSON with a secret in a URL query of a value, e.g. the context of a public link' do
      log.level = :debug
      context = Base64.strict_encode64(JSON.generate({'type' => 'external_upload_to_user', 'passcode' => SecureRandom.alphanumeric(12)}))
      data = {'access_url' => "https://host/aspera/faspex/public/send?context=#{context}"}
      described_class.dump(:result_data, data)
      expect(output.string).not_to(include(context.delete('=')))
      expect(output.string).to(include('"access_url": "https://host/aspera/faspex/public/send?context='))
      expect(data['access_url']).to(include(context))
    end

    it 'shows secrets when log_secrets is set' do
      log.level = :debug
      secret = SecureRandom.alphanumeric(12)
      Aspera::Secret::Hider.instance.log_secrets = true
      described_class.dump(:obj, {'password' => secret})
      expect(output.string).to(include(secret))
    ensure
      Aspera::Secret::Hider.instance.log_secrets = false
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

  describe 'status line' do
    let(:terminal) { StringIO.new.tap { |io| io.define_singleton_method(:tty?) { true } } }
    let(:status_line) { double('status_line') }

    around do |example|
      saved_stderr = $stderr
      $stderr = terminal
      example.run
    ensure
      $stderr = saved_stderr
      log.status_line = nil
    end

    it 'is suspended while a log line is written on a terminal' do
      log.logger_type = :stderr
      log.status_line = status_line
      expect(status_line).to(receive(:suspend)) do |&block|
        terminal.write('[cleared]')
        block.call
      end
      log.logger.warn('message')
      expect(terminal.string).to(match(/^\[cleared\].*message\n$/))
    end

    it 'is not suspended when output is not a terminal' do
      terminal.define_singleton_method(:tty?) { false }
      log.logger_type = :stderr
      log.status_line = status_line
      expect(status_line).not_to(receive(:suspend))
      log.logger.warn('message')
      expect(terminal.string).to(include('message'))
    end
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
