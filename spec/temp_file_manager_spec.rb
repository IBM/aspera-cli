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
end
