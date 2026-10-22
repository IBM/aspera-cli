# frozen_string_literal: true

require 'bundler/setup'
require 'aspera/temp_file_manager'
require 'securerandom'
require 'tmpdir'

RSpec.describe(Aspera::TempFileManager) do
  let(:manager) { Aspera::TempFileManager.instance }

  around(:each) do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  after(:each) { manager.cleanup }

  it 'creates an empty file in folder' do
    path = manager.new_file_path_in_folder(File.join(@dir, 'sub'), prefix: 'test', suffix: 'list.txt')
    expect(File.file?(path)).to(be(true))
    expect(File.size(path)).to(eq(0))
    expect(File.dirname(path)).to(eq(File.join(@dir, 'sub')))
    expect(File.basename(path)).to(start_with('test-'))
    expect(File.basename(path)).to(end_with('-list.txt'))
  end

  it 'keeps file after garbage collection' do
    path = manager.new_file_path_in_folder(@dir)
    GC.start
    GC.start
    expect(File.file?(path)).to(be(true))
  end

  it 'creates unique files' do
    paths = Array.new(10) { manager.new_file_path_in_folder(@dir) }
    expect(paths.uniq.length).to(eq(10))
  end

  it 'deletes created files on cleanup' do
    path = manager.new_file_path_in_folder(@dir)
    manager.cleanup
    expect(File.exist?(path)).to(be(false))
  end

  it 'keeps a held file on cleanup, and deletes it when released' do
    path = manager.new_file_path_in_folder(@dir)
    manager.hold([path])
    manager.cleanup
    expect(File.file?(path)).to(be(true))
    manager.release([path])
    expect(File.exist?(path)).to(be(false))
  end

  it 'deletes a file held several times when the last holder releases it' do
    path = manager.new_file_path_in_folder(@dir)
    2.times { manager.hold([path]) }
    manager.release([path])
    manager.cleanup
    expect(File.file?(path)).to(be(true))
    manager.release([path])
    expect(File.exist?(path)).to(be(false))
  end

  it 'ignores files it did not create' do
    path = File.join(@dir, 'other.txt')
    File.write(path, 'x')
    manager.hold([path])
    manager.release([path])
    expect(File.file?(path)).to(be(true))
  end

  it 'deletes a released file once only' do
    path = manager.new_file_path_in_folder(@dir)
    manager.hold([path])
    manager.release([path])
    File.write(path, 'reused name')
    manager.release([path])
    manager.cleanup
    expect(File.file?(path)).to(be(true))
  end

  describe '#cleanup_expired' do
    let(:old_file) { File.join(@dir, 'old') }
    let(:new_file) { File.join(@dir, 'new') }

    around(:each) do |example|
      saved = [manager.expiry_sec, manager.cleanup_on_exit]
      File.write(old_file, '')
      File.utime(Time.now - (6 * 86_400), Time.now - (6 * 86_400), old_file)
      File.write(new_file, '')
      example.run
    ensure
      manager.expiry_sec, manager.cleanup_on_exit = saved
    end

    it 'deletes files older than 5 days by default' do
      manager.cleanup_expired(@dir)
      expect(File.exist?(old_file)).to(be(false))
      expect(File.file?(new_file)).to(be(true))
    end

    it 'keeps all files when expiry is nil' do
      manager.expiry_sec = nil
      manager.cleanup_expired(@dir)
      expect(File.file?(old_file)).to(be(true))
      expect(File.file?(new_file)).to(be(true))
    end

    it 'deletes all files when expiry is 0' do
      manager.expiry_sec = 0
      manager.cleanup_expired(@dir)
      expect(Dir.children(@dir)).to(be_empty)
    end

    it 'deletes old files even if files of this execution are kept' do
      manager.cleanup_on_exit = false
      manager.cleanup_expired(@dir)
      expect(File.exist?(old_file)).to(be(false))
    end

    it 'ignores a file deleted meanwhile by another execution' do
      allow(File).to(receive(:mtime).and_call_original)
      allow(File).to(receive(:mtime).with(old_file).and_raise(Errno::ENOENT))
      expect { manager.cleanup_expired(@dir) }.not_to(raise_error)
    end

    it 'refuses a negative expiry' do
      expect { manager.expiry_sec = -1 }.to(raise_error(Aspera::ParameterError))
    end
  end
end
