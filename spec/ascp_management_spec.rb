# frozen_string_literal: true

# Unit tests for Aspera::Ascp::Management: management port messages of `ascp`.

require 'bundler/setup'
require 'aspera/ascp/management'

RSpec.describe(Aspera::Ascp::Management) do
  describe 'ERRORS' do
    it 'has contiguous codes' do
      expect(described_class::ERRORS.keys).to(eq((0..69).to_a))
    end

    it 'has retry-able errors like as_mgmt_err_is_retryable' do
      retryable = described_class::ERRORS.select { |_, info| info[:r] }.keys
      expect(retryable).to(eq([12, 13, 14, 15, 16, 17, 18, 23, 32, 33, 35, 36, 37, 39, 40, 44, 45, 47, 61, 69]))
    end
  end

  describe '.field_snake_to_native' do
    it 'reverses field_native_to_snake for all fields' do
      described_class.const_get(:PARAMETERS).each do |name|
        expect(described_class.field_snake_to_native(described_class.field_native_to_snake(name))).to(eq(name))
      end
    end

    it 'accepts symbols' do
      expect(described_class.field_snake_to_native(:min_rate)).to(eq('MinRate'))
    end

    it 'fails on unknown field' do
      expect { described_class.field_snake_to_native('foo_bar') }.to(raise_error(Aspera::AssertError, /No such field: foo_bar/))
    end
  end

  describe '.event_native_to_snake' do
    it 'converts names and types' do
      event = {
        'Bytescont'         => '1',
        'Elapsedusec'       => '10',
        'TransfersFailed'   => '2',
        'Code'              => '16',
        'Rate'              => '50%',
        'Encryption'        => 'Yes',
        'Stalled'           => 'No',
        'ExtraCreatePolicy' => 'none'
      }
      expect(described_class.event_native_to_snake(event)).to(eq({
        'bytes_cont'          => 1,
        'elapsed_usec'        => 10,
        'transfers_failed'    => 2,
        'code'                => 16,
        'rate'                => '50%',
        'encryption'          => true,
        'stalled'             => false,
        'extra_create_policy' => 'none'
      }))
    end
  end

  describe 'path escaping' do
    let(:path) { "/dir\nwith\rspecial\e/file" }
    let(:escaped) { "/dir\enwith\erspecial\e\e/file" }

    it 'escapes' do
      expect(described_class.escape_path(path)).to(eq(escaped))
    end

    it 'unescapes' do
      expect(described_class.unescape_path(escaped)).to(eq(path))
    end

    it 'keeps unknown escape sequences' do
      expect(described_class.unescape_path("a\exb")).to(eq("a\exb"))
    end
  end

  describe '.command_to_stream' do
    it 'builds frame with escaped paths' do
      expect(described_class.command_to_stream({'type' => 'START', 'source' => "/a\nb", 'destination' => '/c'}))
        .to(eq("FASPMGR 2\nType: START\nSource: /a\enb\nDestination: /c\n\n"))
    end

    it 'fails on line break in other values' do
      expect { described_class.command_to_stream({'type' => "START\nRate: 1"}) }.to(raise_error(Aspera::AssertError, /line break in value of Type/))
    end
  end

  describe '#process_line' do
    let(:processor) { described_class.new }

    it 'returns event at end of frame' do
      expect(processor.process_line('FASPMGR 2')).to(be_nil)
      expect(processor.process_line('Type: STOP')).to(be_nil)
      expect(processor.process_line("File: /a\enb")).to(be_nil)
      expect(processor.process_line('Description: ')).to(be_nil)
      expected = {'Type' => 'STOP', 'File' => "/a\nb", 'Description' => ''}
      expect(processor.process_line('')).to(eq(expected))
      expect(processor.last_event).to(eq(expected))
    end

    it 'removes only one space after colon' do
      processor.process_line('FASPMGR 2')
      processor.process_line('Type: STOP')
      processor.process_line('Description: error: details')
      processor.process_line('File:  leading space ')
      processor.process_line('Source:no space')
      processor.process_line('UserStr:')
      expect(processor.process_line('')).to(eq({
        'Type'        => 'STOP',
        'Description' => 'error: details',
        'File'        => ' leading space ',
        'Source'      => 'no space',
        'UserStr'     => ''
      }))
    end

    it 'discards incomplete event on new header' do
      expect(Aspera::Log.log).to(receive(:warn))
      processor.process_line('FASPMGR 2')
      processor.process_line('Type: STATS')
      processor.process_line('FASPMGR 2')
      processor.process_line('Type: DONE')
      expect(processor.process_line('')).to(eq({'Type' => 'DONE'}))
    end

    it 'fails on data without header' do
      expect { processor.process_line('Type: DONE') }.to(raise_error(Aspera::AssertError, /data without header/))
    end

    it 'fails on unexpected line' do
      expect { processor.process_line('garbage') }.to(raise_error(Aspera::InternalError, /unexpected value/))
    end
  end
end
