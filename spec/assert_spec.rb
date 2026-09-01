# frozen_string_literal: true

require 'bundler/setup'
require 'aspera/assert'

RSpec.describe(Aspera::InternalError) do
  it 'asserts unreachable line' do
    expect do
      Aspera.error_unreachable_line
    end.to(raise_error(Aspera::InternalError, /^unreachable line reached/))
  end

  it 'asserts unexpected value' do
    expect do
      Aspera.error_unexpected_value(nil)
    end.to(raise_error(Aspera::InternalError, /^unexpected value/))
  end
end

RSpec.describe(Aspera::AssertError) do
  it 'works for list' do
    Aspera.assert_values(:bad, [:good])
    raise 'Shall not reach here'
  rescue Aspera::AssertError => e
    expect(e.message).to(start_with('assertion failed: expecting one of [:good], but have :bad'))
  end
end
