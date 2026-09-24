# frozen_string_literal: true

require 'bundler/setup'
require 'aspera/rest'
require 'webrick'
require 'tmpdir'
require 'pathname'
require 'stringio'

RSpec.describe(Aspera::Rest) do
  it 'build URI' do
    expect(Aspera::Rest.build_uri('https://locahost', 'q=e&p=1').to_s).to(eq('https://locahost?q=e&p=1'))
  end

  it 'parses php query' do
    expect(Aspera::Rest.query_to_h('q[]=1&q[]=2')).to(eq({'q' => %w[1 2]}))
    expect(Aspera::Rest.query_to_h('q=1&q=2')).to(eq({'q' => %w[1 2]}))
  end

  it 'parses header' do
    expect(Aspera::Rest.parse_header('application/json; charset=utf-8; version="1.0"')).to(eq({type: 'application/json', parameters: {charset: 'utf-8', version: '1.0'}}))
  end

  describe 'save_to' do
    # Large enough to be received in several fragments
    content = Random.new(42).bytes(1024 * 1024)
    header_filename = 'from_header.bin'

    before(:all) do
      @server = WEBrick::HTTPServer.new(Port: 0, BindAddress: '127.0.0.1', Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
      @server.mount_proc('/data') do |_req, res|
        res['Content-Type'] = 'application/octet-stream'
        res.body = content
      end
      @server.mount_proc('/disposition') do |_req, res|
        res['Content-Type'] = 'application/octet-stream'
        res['Content-Disposition'] = %Q(attachment; filename="#{header_filename}")
        res.body = content
      end
      @thread = Thread.new { @server.start }
      @api = Aspera::Rest.new(base_url: "http://127.0.0.1:#{@server.config[:Port]}")
    end

    after(:all) do
      @server.shutdown
      @thread.join
    end

    around(:each) do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        example.run
      end
    end

    it 'saves to file path as String' do
      target = File.join(@dir, 'file.bin')
      @api.read('data', save_to: target)
      expect(File.binread(target)).to(eq(content))
    end

    it 'saves to file path as Pathname' do
      target = Pathname.new(@dir) / 'file.bin'
      @api.read('data', save_to: target)
      expect(target.binread).to(eq(content))
    end

    it 'saves to stream' do
      io = StringIO.new(String.new(encoding: Encoding::BINARY))
      @api.read('data', save_to: io)
      expect(io.string).to(eq(content))
    end

    it 'uses file name from Content-Disposition for file path' do
      @api.read('disposition', save_to: File.join(@dir, 'file.bin'))
      expect(File.exist?(File.join(@dir, 'file.bin'))).to(be(false))
      expect(File.binread(File.join(@dir, header_filename))).to(eq(content))
    end

    it 'ignores Content-Disposition for stream' do
      io = StringIO.new(String.new(encoding: Encoding::BINARY))
      @api.read('disposition', save_to: io)
      expect(io.string).to(eq(content))
      expect(Dir.children(@dir)).to(be_empty)
    end

    it 'rejects unsupported type' do
      expect { @api.read('data', save_to: 42) }.to(raise_error(Aspera::AssertError, /save_to: unsupported type Integer/))
    end
  end
end
