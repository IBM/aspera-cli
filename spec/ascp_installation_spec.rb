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

  describe 'archive with links (GHSA-mjf3-ccfm-5rwp)' do
    # @param path    [String] Path of archive to create
    # @param entries [Array<Array>] `[:link, name, target]` or `[:file, name, content]`
    def write_tar_gz_entries(path, entries)
      File.open(path, 'wb') do |file|
        Zlib::GzipWriter.wrap(file) do |gz|
          Gem::Package::TarWriter.new(gz) do |tar|
            entries.each do |type, name, value|
              if type.eql?(:link)
                tar.add_symlink(name, value, 0o755)
              else
                tar.add_file_simple(name, 0o755, value.bytesize) { |io| io.write(value) }
              end
            end
          end
        end
      end
    end

    it 'does not write through a symlink to a file outside of the install folder' do
      Dir.mktmpdir do |dir|
        victim = File.join(dir, 'victim.sh')
        File.write(victim, 'SAFE')
        archive = File.join(dir, 'sdk.tar.gz')
        write_tar_gz_entries(archive, [[:link, 'pkg/bin/ascp', victim], [:file, 'pkg/lib/ascp', 'PWNED']])
        folder = File.join(dir, 'install')
        described_class.instance.download_sdk(folder: folder, url: Aspera::UriReader.file_url(archive), backup: false) { '/' }
        expect(File.read(victim)).to(eq('SAFE'))
        expect(File.symlink?(File.join(folder, 'ascp'))).to(be(false))
      end
    end

    it 'does not create a symlink to a sibling folder sharing the name prefix of the install folder' do
      Dir.mktmpdir do |dir|
        archive = File.join(dir, 'sdk.tar.gz')
        write_tar_gz_entries(archive, [[:link, 'pkg/bin/other', File.join(dir, 'install_evil', 'x')]])
        folder = File.join(dir, 'install')
        described_class.instance.download_sdk(folder: folder, url: Aspera::UriReader.file_url(archive), backup: false) { '/' }
        expect(File.symlink?(File.join(folder, 'other'))).to(be(false))
      end
    end

    it 'does not create a relative symlink leaving the install folder' do
      Dir.mktmpdir do |dir|
        archive = File.join(dir, 'sdk.tar.gz')
        write_tar_gz_entries(archive, [[:link, 'pkg/bin/up', '../../outside']])
        folder = File.join(dir, 'install')
        described_class.instance.download_sdk(folder: folder, url: Aspera::UriReader.file_url(archive), backup: false) { '/' }
        expect(File.symlink?(File.join(folder, 'up'))).to(be(false))
      end
    end

    it 'keeps a symlink inside the install folder' do
      Dir.mktmpdir do |dir|
        archive = File.join(dir, 'sdk.tar.gz')
        write_tar_gz_entries(archive, [[:file, 'pkg/bin/real', 'content'], [:link, 'pkg/bin/alias', 'real']])
        folder = File.join(dir, 'install')
        described_class.instance.download_sdk(folder: folder, url: Aspera::UriReader.file_url(archive), backup: false) { '/' }
        expect(File.read(File.join(folder, 'alias'))).to(eq('content'))
      end
    end
  end

  describe 'install_sdk with folder' do
    around do |example|
      previous = Aspera::Products::Transferd.instance_variable_get(:@sdk_dir)
      Aspera::Products::Transferd.sdk_directory = '/sdk/default'
      example.run
    ensure
      Aspera::Products::Transferd.instance_variable_set(:@sdk_dir, previous)
    end

    it 'installs in the given folder and sets back the SDK folder, also on error' do
      seen = nil
      allow(described_class.instance).to(receive(:download_sdk)) do |folder:, **|
        seen = [folder, Aspera::Products::Transferd.sdk_directory]
        raise 'stop'
      end
      expect { described_class.instance.install_sdk(folder: '/sdk/1.1.9') }.to(raise_error('stop'))
      expect(seen).to(eq(['/sdk/1.1.9', '/sdk/1.1.9']))
      expect(Aspera::Products::Transferd.sdk_directory).to(eq('/sdk/default'))
    end

    it 'installs in the SDK folder without folder' do
      seen = nil
      allow(described_class.instance).to(receive(:download_sdk)) do |folder:, **|
        seen = folder
        raise 'stop'
      end
      expect { described_class.instance.install_sdk }.to(raise_error('stop'))
      expect(seen).to(eq('/sdk/default'))
    end
  end
end
