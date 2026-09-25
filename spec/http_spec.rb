# frozen_string_literal: true

# Unit tests for Aspera::Cli::Http option handling — no server, no config file needed.

require 'tmpdir'
require 'fileutils'
require 'aspera/cli/parser'
require 'aspera/cli/http'

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
        described_class.declare_options(parser)
        http.bind_options(parser)
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
          expect(http.trusted_cert_locations).to(include(*default))
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

        it 'replaces previous URLs, and accepts nil' do
          http = described_class.new
          http.ignore_cert_host_port = ['https://a.example.com']
          http.ignore_cert_host_port = ['https://b.example.com']
          expect(http.ignore_cert_host_port).to(eq([['b.example.com', 443]]))
          http.ignore_cert_host_port = nil
          expect(http.ignore_cert_host_port).to(eq([]))
        end

        it 'rejects a non https URL' do
          http = described_class.new
          expect { http.ignore_cert_host_port = ['http://a.example.com'] }.to(raise_error(/Expecting https scheme/))
        end
      end

      describe 'option insecure' do
        it 'ignores certificate for any URL' do
          http = build_http(['--insecure=yes', '--warn-insecure=no'])
          expect(http.ignore_cert?('any.example.com', 443)).to(be(true))
        end
      end
    end
  end
end
