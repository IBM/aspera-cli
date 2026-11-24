# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative 'error_analyzer'

module Aspera
  module Rest
    # REST error handlers for the shapes of error of REST APIs (JSON paths), registered on require
    # Handlers of a specific API are registered by its bundle (`ErrorAnalyzer#add_handler`), when its code is loaded.
    # Faspex 4: both user_message and internal_message, and code 200
    # example: missing meta data on package creation
    ErrorAnalyzer.instance.add_simple_handler(name: 'Type 1: error:user_message', path: %w[error user_message], always: true)
    ErrorAnalyzer.instance.add_simple_handler(name: 'Type 2: error:description', path: %w[error description])
    ErrorAnalyzer.instance.add_simple_handler(name: 'Type 3: error:internal_message', path: %w[error internal_message])
    ErrorAnalyzer.instance.add_simple_handler(name: 'Type 5', path: ['error_description'])
    ErrorAnalyzer.instance.add_simple_handler(name: 'Type 6', path: ['message'])
    ErrorAnalyzer.instance.add_simple_handler(name: 'Type 6', path: ['failure'], always: true)
    # Message only, e.g. AoC Automation, OAuth (RFC 6749, with `error_description`)
    ErrorAnalyzer.instance.add_simple_handler(name: 'Type 4: error', path: ['error'])
    ErrorAnalyzer.instance.add_handler('Type 7: errors[]') do |type, context|
      next unless context[:data].is_a?(Hash) && context[:data]['errors'].is_a?(Hash)
      # special for Shares: false positive ? (update global transfer_settings)
      next if context[:data].key?('min_connect_version')
      context[:data]['errors'].each do |k, v|
        ErrorAnalyzer.add_error(context, type, "#{k}: #{v}")
      end
    end
    ErrorAnalyzer.instance.add_simple_handler(name: 'T9:IBM cloud IAM', path: ['errorMessage'])
    ErrorAnalyzer.instance.add_simple_handler(name: 'T10:faspex v4', path: ['user_message'])
  end
end
