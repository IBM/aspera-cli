# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Exit status of `ascli`, by category of error.

require_relative '../lib/aspera/cli/error'
require_relative '../lib/aspera/cli/info'
require_relative '../lib/aspera/rest/call_error'
require 'net/http'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'securerandom'

module Aspera
  module Cli
    RSpec.describe(ExitCode) do
      describe '.for_call_error' do
        # @param code [String] HTTP status code
        # @param data [Object] parsed body of the response
        # @return [Rest::CallError] error of an API call
        def call_error(code, data = nil)
          response = Net::HTTPResponse::CODE_TO_OBJ.fetch(code).new('1.1', code, 'message')
          Rest::CallError.new({messages: ['failed'], response: response, data: data})
        end

        {
          '401' => ExitCode::AUTH,
          '403' => ExitCode::AUTH,
          '404' => ExitCode::NOT_FOUND,
          '400' => ExitCode::API,
          '500' => ExitCode::API
        }.each do |code, exit_code|
          it "maps HTTP #{code} to #{exit_code}" do
            expect(described_class.for_call_error(call_error(code))).to(eq(exit_code))
          end
        end

        it 'maps a refused OAuth grant to an authentication failure' do
          expect(described_class.for_call_error(call_error('400', {'error' => 'invalid_grant'}))).to(eq(ExitCode::AUTH))
        end

        it 'maps an error without HTTP response to an API error' do
          expect(described_class.for_call_error(Rest::CallError.new('JSON-RPC error'))).to(eq(ExitCode::API))
        end
      end

      describe '.add_error' do
        # Error class of the examples
        spec_error = Class.new(StandardError)

        around do |example|
          errors = described_class.instance_variable_get(:@errors).dup
          example.run
        ensure
          described_class.instance_variable_set(:@errors, errors)
        end

        it 'gives the label and exit code of an added error class, also for its subclasses' do
          expect(described_class.error_category(spec_error.new)).to(be_nil)
          described_class.add_error(spec_error, label: 'Spec', code: ExitCode::TRANSFER)
          expect(described_class.error_category(spec_error.new)).to(eq({label: 'Spec', code: ExitCode::TRANSFER}))
          expect(described_class.error_category(Class.new(spec_error).new)).to(eq({label: 'Spec', code: ExitCode::TRANSFER}))
          expect(described_class.error_category(StandardError.new)).to(be_nil)
        end

        it 'gives the most specific added class, in both orders of `add_error`' do
          child = Class.new(spec_error)
          described_class.add_error(spec_error, label: 'Parent', code: ExitCode::TRANSFER)
          described_class.add_error(child, label: 'Child', code: ExitCode::API)
          expect(described_class.error_category(child.new)).to(eq({label: 'Child', code: ExitCode::API}))
          described_class.instance_variable_set(:@errors, {})
          described_class.add_error(child, label: 'Child', code: ExitCode::API)
          described_class.add_error(spec_error, label: 'Parent', code: ExitCode::TRANSFER)
          expect(described_class.error_category(child.new)).to(eq({label: 'Child', code: ExitCode::API}))
          expect(described_class.error_category(spec_error.new)).to(eq({label: 'Parent', code: ExitCode::TRANSFER}))
        end

        it 'refuses a class that is not an error, or an unknown exit code' do
          expect { described_class.add_error(String, label: 'Spec', code: ExitCode::ERROR) }.to(raise_error(ArgumentError, /not an error class/))
          expect { described_class.add_error(spec_error, label: 'Spec', code: 42) }.to(raise_error(ArgumentError, /unknown exit code: 42/))
        end
      end

      describe 'exit status of the process' do
        # @param args [Array<String>] arguments of `ascli`
        # @return [Array(String, Integer)] output and exit status, with a configuration folder of its own
        def run_ascli(*args)
          source_root = File.expand_path('..', __dir__)
          Dir.mktmpdir do |home|
            cmd = [RbConfig.ruby, "-I#{source_root}/lib", File.join(source_root, 'bin', Info::CMD_NAME), *args, '--version-check-days=0']
            output, status = Open3.capture2e({'ASCLI_HOME' => home}, *cmd)
            [output, status.exitstatus]
          end
        end

        # @param args [Array<String>] arguments of `ascli`
        # @return [Integer] exit status
        def exit_status(*args) = run_ascli(*args).last

        # Label of the error: who is at fault. Only a bug, or an error not raised by the gem, gives its location in the code
        {
          'Aspera::AssertError'                 => ['Other(Aspera::AssertError)', ExitCode::ERROR, true],
          'Aspera::InternalError'               => ['Other(Aspera::InternalError)', ExitCode::ERROR, true],
          'RuntimeError'                        => ['Other(RuntimeError)', ExitCode::ERROR, true],
          'Aspera::Error'                       => ['Error', ExitCode::ERROR, false],
          'Aspera::ParameterError'              => ['Argument', ExitCode::USAGE, false],
          'Aspera::EntityNotFound'              => ['Identifier', ExitCode::NOT_FOUND, false],
          'Aspera::EnvironmentError'            => ['Environment', ExitCode::ERROR, false],
          'Aspera::AuthenticationError'         => ['Authentication', ExitCode::AUTH, false],
          'Aspera::Secret::Error'               => ['Vault', ExitCode::ERROR, false],
          'Aspera::Secret::NotFound'            => ['Identifier', ExitCode::NOT_FOUND, false],
          'Aspera::Secret::AuthenticationError' => ['Authentication', ExitCode::AUTH, false],
          'Aspera::Ssh::Error'                  => ['SSH', ExitCode::ERROR, false]
        }.each do |error_class, (label, code, location)|
          it "reports #{error_class} as #{label}, with exit status #{code}#{', and the location' if location}" do
            output, status = run_ascli('config', 'test', 'throw', error_class, 'failed')
            expect([output[/ERRR (\S+): failed/, 1], status, output.include?('Location: ')]).to(eq([label, code, location]))
          end
        end

        it 'refuses an element that is not a String in a list option, as an error of argument' do
          output, status = run_ascli('config', 'echo', 'hello', '--plugin-folder=@json:[1]')
          expect([output[/ERRR (.*)$/, 1], status]).to(eq(['Argument: Option plugin_folder: expecting all as String, but have [Integer]', ExitCode::USAGE]))
        end

        password = SecureRandom.alphanumeric(12)
        {
          %w[config echo hello]                                                      => ExitCode::SUCCESS,
          %w[config unknown_command]                                                 => ExitCode::USAGE,
          %w[config echo]                                                            => ExitCode::USAGE,
          %w[config echo one two]                                                    => ExitCode::USAGE,
          ['config', 'echo', 'hello', '--out.query=[?']                              => ExitCode::USAGE,
          %W[node info --url=http://127.0.0.1:1 --username=u --password=#{password}] => ExitCode::NETWORK,
          # Nagios reports the failure of the check as UNKNOWN
          ['config', 'echo', '@json:{"a":1}', '--format=nagios']                     => 3,
          # Category added by the bundle xfer
          %w[config test throw Aspera::Transfer::Error failed]                       => ExitCode::TRANSFER
        }.each do |args, code|
          it "exits with #{code} for: #{args.join(' ')}" do
            expect(exit_status(*args)).to(eq(code))
          end
        end
      end
    end
  end
end
