# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Unit tests for Aspera::Cli::Http option handling — no server, no config file needed.

require_relative '../lib/aspera/cli/parser'
require_relative '../lib/aspera/cli/http'
require 'tmpdir'
require 'fileutils'

module Aspera
  module Cli
    RSpec.describe(Http) do
      let(:tmpdir) { Dir.mktmpdir('http_spec') }

      after { FileUtils.rm_rf(tmpdir) }

      # @return [String] path of a new folder containing one certificate file
      def cert_folder(name)
        folder = File.join(tmpdir, name)
        FileUtils.mkdir_p(folder)
        FileUtils.touch(File.join(folder, "#{name}.pem"))
        File.realpath(folder)
      end

      # @return [Http] http configuration bound to a parser with the given command line
      def build_http(argv)
        parser = Parser.new('test', argv)
        http = described_class.new
        described_class.declare_options(parser, target: http)
        parser.parse_options!
        http
      end

      describe 'option cert_stores' do
        it 'uses the given locations only' do
          folder = cert_folder('a')
          http = build_http(["--cert-stores=@json:[\"#{folder}\"]"])
          expect(http.trusted_cert_locations).to(eq([File.join(folder, 'a.pem')]))
        end

        it 'replaces previous locations' do
          http = described_class.new
          http.trusted_cert_locations = [cert_folder('a')]
          http.trusted_cert_locations = [cert_folder('b')]
          expect(http.trusted_cert_locations.map { |f| File.basename(f) }).to(eq(['b.pem']))
        end

        it 'uses system default when empty' do
          http = described_class.new
          default = http.trusted_cert_locations
          http.trusted_cert_locations = [cert_folder('a')]
          http.trusted_cert_locations = []
          expect(http.trusted_cert_locations).to(eq(default))
        end

        it 'adds system default with DEF' do
          http = described_class.new
          default = http.trusted_cert_locations
          folder = cert_folder('a')
          http.trusted_cert_locations = [folder, SpecialValues::DEF]
          expect(http.trusted_cert_locations).to(include(File.join(folder, 'a.pem')))
          expect(http.trusted_cert_locations).to(include(*default)) unless default.empty?
        end

        it 'raises for a missing location' do
          http = described_class.new
          expect { http.trusted_cert_locations = [File.join(tmpdir, 'missing')] }.to(raise_error(/No such file or folder/))
        end
      end

      describe 'option ignore_certificate' do
        it 'ignores certificate only for given URLs' do
          http = build_http(['--ignore-certificate=@json:["https://a.example.com:8443"]', '--warn-insecure=no'])
          expect(http.ignore_cert?('a.example.com', 8443)).to(be(true))
          expect(http.ignore_cert?('a.example.com', 443)).to(be(false))
          expect(http.ignore_cert?('b.example.com', 8443)).to(be(false))
        end

        it 'accepts a single URL' do
          http = build_http(['--ignore-certificate=https://a.example.com:8443', '--warn-insecure=no'])
          expect(http.ignore_cert?('a.example.com', 8443)).to(be(true))
        end

        it 'replaces previous URLs, and accepts empty list' do
          http = described_class.new
          http.ignore_cert_host_port = ['https://a.example.com']
          http.ignore_cert_host_port = ['https://b.example.com']
          expect(http.ignore_cert_host_port).to(eq([['b.example.com', 443]]))
          http.ignore_cert_host_port = []
          expect(http.ignore_cert_host_port).to(eq([]))
        end

        it 'rejects a non https URL' do
          http = described_class.new
          expect { http.ignore_cert_host_port = ['http://a.example.com'] }.to(raise_error(/Expecting https scheme/))
        end
      end

      describe 'option http_options' do
        around do |example|
          oauth = OAuth::Factory.instance.parameters
          saved_oauth = oauth.dup
          saved_sleep = Rest::Parameters.instance.retry_sleep
          example.run
        ensure
          oauth.replace(saved_oauth)
          Rest::Parameters.instance.retry_sleep = saved_sleep
        end

        it 'accepts durations as number of seconds or string' do
          http = build_http(['--http-options=@json:{"token_refresh_max_age":"12h","token_cache_max_age":86400,"retry_sleep":"2s","read_timeout":"1m 30s","open_timeout":"0.5"}'])
          expect(OAuth::Factory.instance.parameters).to(include(token_refresh_max_age: 43_200, token_cache_max_age: 86_400))
          expect(Rest::Parameters.instance.retry_sleep).to(eq(2))
          expect(http.http_options).to(eq('read_timeout' => 90, 'open_timeout' => 0.5))
        end

        it 'accepts a duration in dot notation' do
          build_http(['--http-options.token_refresh_max_age=1d'])
          expect(OAuth::Factory.instance.parameters[:token_refresh_max_age]).to(eq(86_400))
        end

        it 'rejects an invalid duration' do
          expect { build_http(['--http-options=@json:{"retry_sleep":"abc"}']) }.to(raise_error(BadArgument, /retry_sleep: Invalid duration: abc/))
        end

        it 'rejects an unknown SSL option as a command line error' do
          expect { build_http(['--http-options=@json:{"ssl_options":["NO_SUCH_OPTION"]}']) }.to(raise_error(BadArgument, /Unknown ssl_option: OP_NO_SUCH_OPTION/))
        end
      end

      describe 'option insecure' do
        it 'ignores certificate for any URL' do
          http = build_http(['--insecure=yes', '--warn-insecure=no'])
          expect(http.ignore_cert?('any.example.com', 443)).to(be(true))
        end
      end

      # Disabling or redirecting the validation of a server certificate lets a client intercept the server's connections (man-in-the-middle):
      # these options are available at security level `low` only.
      describe 'security level high' do
        before { Security.instance.options = {'level' => 'high'} }
        after  { Security.instance.reset }

        [
          '--insecure=yes',
          '--ignore-certificate=@json:["https://x"]',
          '--cert-stores=@json:["/tmp"]',
          '--http-proxy=http://proxy:8080',
          '--http-options=@json:{"ca_file":"/x"}',
          '--http-options=@json:{"verify_mode":"none"}',
          '--http-options=@json:{"ssl_options":["IGNORE_UNEXPECTED_EOF"]}'
        ].each do |option|
          it "refuses #{option}" do
            expect { build_http([option]) }.to(raise_error(BadArgument, /disabled by security level high/))
          end
        end
      end
    end
  end
end
