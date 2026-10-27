# frozen_string_literal: true

# Unit tests for Aspera::Ascp::SessionErrors: error codes of FASP sessions in `ascp` logs.

require 'bundler/setup'
require 'aspera/ascp/session_errors'

RSpec.describe(Aspera::Ascp::SessionErrors) do
  describe 'CODES' do
    it 'refers to existing errors of management port' do
      described_class::CODES.each do |code, (_, management, _, _)|
        expect(Aspera::Ascp::Management.error_by_mnemonic(management)).not_to(be_nil, "code #{code}: #{management}")
      end
    end

    it 'has categories with a hint, or other, all used' do
      expect(described_class::CODES.values.map { |row| row[2] }.uniq).to(match_array(described_class::CATEGORIES.keys + [described_class::OTHER]))
    end
  end

  describe '.category' do
    it 'gives category and hint of code' do
      expect(described_class.category(11)).to(eq('udp_setup'))
      expect(described_class.hint(described_class.category(11))).to(match(/UDP port/))
    end

    it 'gives other category without hint for unknown code' do
      expect(described_class.category(999)).to(eq(described_class::OTHER))
      expect(described_class.hint(described_class::OTHER)).to(be_nil)
    end
  end

  describe '.retryable' do
    it 'is retry-able as the error of management port' do
      expect(described_class.retryable(18)).to(be(true))
      expect(described_class.retryable(89)).to(be(false))
    end

    it 'is unknown for unknown code' do
      expect(described_class.retryable(999)).to(be_nil)
    end
  end
end
