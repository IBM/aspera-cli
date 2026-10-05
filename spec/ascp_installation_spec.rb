# frozen_string_literal: true

require 'bundler/setup'
require 'tmpdir'
require 'zlib'
require 'rubygems/package'
require 'zip'
require 'aspera/uri_reader'
require 'aspera/ascp/installation'

RSpec.describe(Aspera::Ascp::Installation) do
  # @param path [String] Path of archive to create, with a file in a sub folder, like the SDK
  def write_tar_gz(path)
    File.open(path, 'wb') do |file|
      Zlib::GzipWriter.wrap(file) do |gz|
        Gem::Package::TarWriter.new(gz) do |tar|
          tar.add_file_simple('sdk/bin/ascp', 0o755, 'ascp content'.bytesize) { |io| io.write('ascp content') }
        end
      end
    end
  end

  # @param path [String] Path of archive to create, with a file in a sub folder, like the SDK
  def write_zip(path)
    Zip::File.open(path, create: true) { |zip| zip.get_output_stream('sdk/bin/ascp') { |io| io.write('ascp content') } }
  end

  %w[tar.gz zip].each do |extension|
    it "extracts SDK from a local .#{extension} file" do
      Dir.mktmpdir do |dir|
        archive = File.join(dir, "sdk.#{extension}")
        extension.eql?('zip') ? write_zip(archive) : write_tar_gz(archive)
        folder = File.join(dir, 'install')
        described_class.instance.download_sdk(folder: folder, url: Aspera::UriReader.file_url(archive), backup: false) { '/' }
        expect(File.read(File.join(folder, 'ascp'))).to(eq('ascp content'))
      end
    end
  end
end
