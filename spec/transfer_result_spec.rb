# frozen_string_literal: true

require 'bundler/setup'
require 'aspera/transfer/result'

RSpec.describe(Aspera::Transfer::Result) do
  describe '.success' do
    it 'returns a Success instance' do
      expect(described_class.success).to(be_a(described_class::Success))
    end

    it 'has a meaningful to_s' do
      expect(described_class.success.to_s).to(eq('success'))
    end
  end

  describe '.error' do
    let(:exception){RuntimeError.new('something went wrong')}

    it 'returns an Error instance' do
      expect(described_class.error(exception)).to(be_a(described_class::Error))
    end

    it 'exposes the exception' do
      result = described_class.error(exception)
      expect(result.exception).to(be(exception))
    end

    it 'has a meaningful to_s' do
      expect(described_class.error(exception).to_s).to(include('something went wrong'))
    end
  end

  describe '.async' do
    it 'returns an Async instance' do
      expect(described_class.async(job_id: 'my-uuid')).to(be_a(described_class::Async))
    end

    it 'defaults status to running' do
      result = described_class.async(job_id: 'my-uuid')
      expect(result.status).to(eq('running'))
    end

    it 'exposes the job_id' do
      result = described_class.async(job_id: 'my-uuid')
      expect(result.job_id).to(eq('my-uuid'))
    end

    it 'to_h includes job_id and status' do
      result = described_class.async(job_id: 'my-uuid')
      expect(result.to_h).to(eq({'job_id' => 'my-uuid', 'status' => 'running'}))
    end

    it 'accepts a custom status' do
      result = described_class.async(job_id: 'x', status: 'queued')
      expect(result.status).to(eq('queued'))
    end
  end

  describe 'class hierarchy' do
    it 'Success is a subclass of Result' do
      expect(described_class::Success.ancestors).to(include(described_class))
    end

    it 'Error is a subclass of Result' do
      expect(described_class::Error.ancestors).to(include(described_class))
    end

    it 'Async is a subclass of Result' do
      expect(described_class::Async.ancestors).to(include(described_class))
    end
  end
end
