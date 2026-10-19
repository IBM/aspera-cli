# frozen_string_literal: true

# Exit status of `ascli`, by category of error.

require 'aspera/cli/error'
require 'aspera/cli/info'
require 'aspera/rest/call_error'
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

      describe 'exit status of the process' do
        # @param args [Array<String>] arguments of `ascli`
        # @return [Integer] exit status, with a configuration folder of its own
        def exit_status(*args)
          source_root = File.expand_path('..', __dir__)
          Dir.mktmpdir do |home|
            cmd = [RbConfig.ruby, "-I#{source_root}/lib", File.join(source_root, 'bin', Info::CMD_NAME), *args, '--version-check-days=0']
            _, status = Open3.capture2e({'ASCLI_HOME' => home}, *cmd)
            status.exitstatus
          end
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
          ['config', 'echo', '@json:{"a":1}', '--format=nagios']                     => 3
        }.each do |args, code|
          it "exits with #{code} for: #{args.join(' ')}" do
            expect(exit_status(*args)).to(eq(code))
          end
        end
      end
    end
  end
end
