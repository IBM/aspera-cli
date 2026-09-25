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

  it 'builds php style query without modifying caller query' do
    query = Aspera::Rest.php_style({'a' => %w[1 2]})
    2.times { expect(Aspera::Rest.build_uri('https://localhost', query).query).to(eq('a[]=1&a[]=2')) }
    expect(query).to(eq({'a' => %w[1 2], x_array_php_style: true}))
  end

  it 'returns a copy of creation parameters' do
    api = Aspera::Rest.new(base_url: 'https://localhost', headers: {'X-A' => 'a'})
    api.params[:headers]['X-B'] = 'b'
    expect(api.headers).to(eq({'X-A' => 'a', 'User-Agent' => Aspera::RestParameters.instance.user_agent}))
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
  describe 'call' do
    # Start a local HTTP server with the given handlers: path => proc(req, res)
    def start_server(handlers)
      server = WEBrick::HTTPServer.new(Port: 0, BindAddress: '127.0.0.1', Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
      handlers.each { |path, handler| server.mount_proc(path, &handler) }
      @servers.push(server)
      @threads.push(Thread.new { server.start })
      "http://127.0.0.1:#{server.config[:Port]}"
    end

    # Handler: return JSON of request auth header and query
    echo = lambda do |req, res|
      res['Content-Type'] = 'application/json'
      res.body = JSON.generate({'authorization' => req['Authorization'], 'base' => req['X-Base'], 'query' => req.query_string})
    end

    # Handler: redirect to given location
    def redirect_to(location)
      lambda do |_req, res|
        res.status = 302
        res['Location'] = location
        # prevent WEBrick from making Location absolute
        res.instance_variable_set(:@request_uri, nil)
      end
    end

    before do
      @servers = []
      @threads = []
      @params = Aspera::RestParameters.instance
      @saved = %i[retry_max retry_sleep retry_on_error retry_on_timeout].to_h { |k| [k, @params.send(k)] }
      @params.retry_sleep = 0
    end

    after do
      @saved.each { |k, v| @params.send(:"#{k}=", v) }
      @servers.each(&:shutdown)
      @threads.each(&:join)
    end

    describe 'OAuth' do
      let(:oauth) { double('oauth') }

      before do
        @url = start_server('/api' => lambda do |req, res|
          res['Content-Type'] = 'application/json'
          res.status = req['Authorization'].eql?('Bearer new') ? 200 : 401
          res.body = '{}'
        end)
      end

      def api
        rest = Aspera::Rest.new(base_url: @url, auth: {type: :oauth2})
        rest.instance_variable_set(:@oauth, oauth)
        rest
      end

      it 'retries with refreshed token, even with retry_max=0' do
        @params.retry_max = 0
        allow(oauth).to(receive(:authorization).with(no_args).and_return('Bearer old'))
        allow(oauth).to(receive(:authorization).with(refresh: true).and_return('Bearer new'))
        expect(api.read('api')).to(eq({}))
      end

      it 'generates new token if refresh fails' do
        allow(oauth).to(receive(:authorization).with(no_args).and_return('Bearer old'))
        allow(oauth).to(receive(:authorization).with(refresh: true).and_raise(Aspera::RestCallError, 'refresh'))
        allow(oauth).to(receive(:authorization).with(cache: false).and_return('Bearer new'))
        expect(api.read('api')).to(eq({}))
      end

      it 'raises original error if no new token can be obtained' do
        allow(oauth).to(receive(:authorization).with(no_args).and_return('Bearer old'))
        allow(oauth).to(receive(:authorization).with(refresh: true).and_raise(Aspera::RestCallError, 'refresh'))
        allow(oauth).to(receive(:authorization).with(cache: false).and_raise(Aspera::RestCallError, 'generate'))
        expect { api.read('api') }.to(raise_error(Aspera::RestCallError) { |e| expect(e.response.code).to(eq('401')) })
      end

      it 'renews token only once' do
        allow(oauth).to(receive(:authorization).and_return('Bearer old'))
        expect { api.read('api') }.to(raise_error(Aspera::RestCallError))
        expect(oauth).to(have_received(:authorization).with(refresh: true).once)
      end
    end

    describe 'redirect' do
      before do
        @other = start_server('/echo' => echo)
        @url = start_server(
          '/echo'     => echo,
          '/relative' => redirect_to('/echo?r=1'),
          '/sub/dir'  => redirect_to('../echo'),
          '/same'     => redirect_to('/echo?r=2'),
          '/other'    => redirect_to("#{@other}/echo?r=3")
        )
      end

      def api(**kwargs)
        Aspera::Rest.new(base_url: @url, redirect_max: 1, headers: {'X-Base' => 'base'}, **kwargs)
      end

      it 'follows relative redirect on same port' do
        expect(api.read('relative')['query']).to(eq('r=1'))
      end

      it 'follows relative redirect without leading slash' do
        expect(api.read('sub/dir')['query']).to(be_nil)
      end

      it 'keeps credentials and base headers on same server' do
        result = api(auth: {type: :basic, username: 'u', password: 'p'}).read('same')
        expect(result).to(eq({'authorization' => Aspera::Rest.basic_authorization('u', 'p'), 'base' => 'base', 'query' => 'r=2'}))
      end

      it 'adds URL auth query to Location query on same server' do
        expect(api(auth: {type: :url, url_query: {'k' => 'v'}}).read('same', {'q' => '1'})['query']).to(eq('r=2&k=v'))
      end

      it 'does not forward credentials to another server' do
        result = api(auth: {type: :basic, username: 'u', password: 'p'}).read('other', nil, headers: {'Authorization' => 'Bearer x'})
        expect(result).to(eq({'authorization' => nil, 'base' => 'base', 'query' => 'r=3'}))
      end

      it 'does not forward URL auth query to another server' do
        expect(api(auth: {type: :url, url_query: {'k' => 'v'}}).read('other')['query']).to(eq('r=3'))
      end

      it 'follows redirect without retry, even if retry_on_error' do
        @params.retry_on_error = true
        @params.retry_max = 2
        rest = api
        allow(rest).to(receive(:retry_sleep).and_call_original)
        expect(rest.read('relative')['query']).to(eq('r=1'))
        expect(rest).not_to(have_received(:retry_sleep))
      end

      it 'does not modify headers of caller' do
        headers = {'X-Call' => 'c'}
        api.read('echo', nil, headers: headers)
        expect(headers).to(eq({'X-Call' => 'c'}))
      end

      it 'does not modify query of caller' do
        query = {'q' => '1'}
        api(auth: {type: :url, url_query: {'k' => 'v'}}).read('echo', query)
        expect(query).to(eq({'q' => '1'}))
      end
    end

    describe 'network error' do
      before do
        @url = start_server('/echo' => echo)
      end

      # First request fails with the given error, next ones are sent
      def fail_once(error)
        failed = false
        allow_any_instance_of(Net::HTTP).to(receive(:request).and_wrap_original do |original, *args, &block|
          unless failed
            failed = true
            raise error
          end
          original.call(*args, &block)
        end)
      end

      it 'retries connection timeout if retry_on_timeout' do
        @params.retry_on_timeout = true
        fail_once(Net::OpenTimeout)
        expect(Aspera::Rest.new(base_url: @url).read('echo')['query']).to(be_nil)
      end

      it 'does not retry connection timeout if not retry_on_timeout' do
        @params.retry_on_timeout = false
        fail_once(Net::OpenTimeout)
        expect { Aspera::Rest.new(base_url: @url).read('echo') }.to(raise_error(Net::OpenTimeout))
      end

      it 'retries connection reset if retry_on_error' do
        @params.retry_on_error = true
        fail_once(Errno::ECONNRESET)
        expect(Aspera::Rest.new(base_url: @url).read('echo')['query']).to(be_nil)
      end

      it 'does not retry connection reset if not retry_on_error' do
        @params.retry_on_error = false
        fail_once(Errno::ECONNRESET)
        expect { Aspera::Rest.new(base_url: @url).read('echo') }.to(raise_error(Errno::ECONNRESET))
      end

      it 'keeps php style query on retry' do
        @params.retry_on_error = true
        fail_once(Errno::ECONNRESET)
        query = Aspera::Rest.php_style({'a' => %w[1 2]})
        expect(Aspera::Rest.new(base_url: @url).read('echo', query)['query']).to(eq('a[]=1&a[]=2'))
      end

      it 'does not retry more than retry_max' do
        @params.retry_on_error = true
        @params.retry_max = 0
        fail_once(Errno::ECONNRESET)
        expect { Aspera::Rest.new(base_url: @url).read('echo') }.to(raise_error(Errno::ECONNRESET))
      end
    end
  end
end
