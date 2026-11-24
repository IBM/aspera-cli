# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require_relative '../lib/aspera/ssl'

RSpec.describe(Aspera::SSL) do
  around do |example|
    saved = described_class.extra_options
    example.run
  ensure
    described_class.instance_variable_set(:@extra_options, saved)
  end

  describe '.option_list=' do
    it 'sets and clears options by name' do
      described_class.option_list = [0]
      described_class.option_list = ['IGNORE_UNEXPECTED_EOF']
      expect(described_class.extra_options).to(eq(OpenSSL::SSL::OP_IGNORE_UNEXPECTED_EOF))
      described_class.option_list = ['-IGNORE_UNEXPECTED_EOF']
      expect(described_class.extra_options).to(eq(0))
    end

    it 'raises a framework error for an unknown option' do
      expect { described_class.option_list = ['NO_SUCH_OPTION'] }.to(raise_error(Aspera::ParameterError, /Unknown ssl_option: OP_NO_SUCH_OPTION, use one of: /))
    end
  end
end
