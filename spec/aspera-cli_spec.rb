# frozen_string_literal: true

require 'spec_helper'

# top folder of project
project_top_folder = File.dirname(File.dirname(File.realpath(__FILE__)))

require 'aspera/log'
# Aspera::Log.instance.level = :debug
# Aspera::Log.instance.logger_type = :stderr
require 'aspera/coverage'
require 'aspera/transfer/uri'
require 'aspera/cli/main'
require 'aspera/ascmd'
require 'aspera/assert'
require 'aspera/ssh'
require 'uri'
require 'openssl'

class LocalExecutor
  def execute(cmd, line)
    %Q(echo "#{line}"|#{cmd})
  end
end

ssh_url = URI.parse(RSpec.configuration.url)
# main folder relative to docroot and server executor
PATH_FOLDER_MAIN = '/'
demo_executor = Aspera::Ssh.new(ssh_url.host, RSpec.configuration.username, {password: RSpec.configuration.password, port: ssh_url.port, use_agent: false})

# to use a local executor, set PATH_FOLDER_MAIN to the pseudo docroot (local) folder
# PATH_FOLDER_MAIN='/pseudo/docroot'
# demo_executor=LocalExecutor.new
TEST_RUN_ID = rand(1000).to_s
PATH_FOLDER_TINY = File.join(PATH_FOLDER_MAIN, 'aspera-test-dir-tiny')
PATH_FOLDER_DEST = File.join(PATH_FOLDER_MAIN, 'Upload')
PATH_FOLDER_NEW = File.join(PATH_FOLDER_DEST, "new_folder-#{TEST_RUN_ID}")
PATH_FOLDER_RENAMED = File.join(PATH_FOLDER_DEST, "renamed_folder-#{TEST_RUN_ID}")
NAME_FILE1 = '200KB.1'
PATH_FILE_EXIST = File.join(PATH_FOLDER_TINY, NAME_FILE1)
PATH_FILE_COPY = File.join(PATH_FOLDER_DEST, "#{NAME_FILE1}.copy1-#{TEST_RUN_ID}")
PATH_FILE_RENAMED = File.join(PATH_FOLDER_DEST, "#{NAME_FILE1}.renamed-#{TEST_RUN_ID}")
PAC_FILE = "file:///#{project_top_folder}/tests/proxy.pac"
SAMPLE_FASPE_URI = 'faspe://user:pass@host:33001/path?' + {
  'cookie'      => 'foo',
  'token'       => 'foo',
  'sshfp'       => 'foo',
  'policy'      => 'foo',
  'httpport'    => 'foo',
  'targetrate'  => 'foo',
  'minrate'     => 'foo',
  'port'        => 'foo',
  'bwcap'       => 'foo',
  'enc'         => 'foo',
  'tags64'      => 'ImZvbyIK',
  'createpath'  => 'no',
  'fallback'    => 'no',
  'lockpolicy'  => 'no',
  'lockminrate' => 'yes',
  'auth'        => 'foo',
  'v'           => 'foo',
  'protect'     => 'foo'
}.to_a.map{ |a| a.join('=')}.join('&')
puts "Openssl version: #{OpenSSL::OPENSSL_VERSION}"

RSpec.describe(Aspera::Transfer::Uri) do
  it 'parses a FASP URL' do
    uri = Aspera::Transfer::Uri.new("#{SAMPLE_FASPE_URI}&bad=xx")
    ts = uri.transfer_spec
    expect(ts).to(be_a(Hash))
    expect(ts['token']).to(eq('foo'))
    expect(ts['sshfp']).to(eq('foo'))
    # expect(ts['protect']).to(eq(nil))
    #
  end
end

RSpec.describe(Aspera::InternalError) do
  it 'asserts unreachable line' do
    begin # rubocop:disable Style/RedundantBegin
      Aspera.error_unreachable_line
      raise 'Shall not reach here'
    rescue Aspera::InternalError => e
      expect(e.message).to(start_with('unreachable line reached'))
    end
  end
  it 'asserts unexpected value' do
    begin # rubocop:disable Style/RedundantBegin
      Aspera.error_unexpected_value(nil)
      raise 'Shall not reach here'
    rescue Aspera::InternalError => e
      expect(e.message).to(start_with('unexpected value'))
    end
  end
end

RSpec.describe(Aspera::Cli::Main) do
  it 'has a version number' do
    expect(Aspera::Cli::VERSION).not_to(be(nil))
  end
end

RSpec.describe(Aspera::ProxyAutoConfig) do
  it "get right proxy with #{PAC_FILE}" do
    expect(Aspera::ProxyAutoConfig.new(Aspera::UriReader.read(PAC_FILE)).find_proxy_for_url('http://eudemo.asperademo.com')).to(eq('PROXY proxy.example.com:8080'))
  end
end

RSpec.describe(Aspera::AsCmd) do
  ascmd = Aspera::AsCmd.new(demo_executor)
  #    ['du','/Users/xfer'],
  #    ['df','/'],
  #    ['df'],
  describe 'info' do
    it 'works' do
      res = ascmd.execute_single(:info, [])
      expect(res).to(be_a(Hash))
      expect(res[:lang]).to(eq('C'))
    end
  end
  describe 'ls' do
    it "works on folder #{PATH_FOLDER_TINY}" do
      res = ascmd.execute_single(:ls, [PATH_FOLDER_TINY])
      expect(res).to(be_a(Array))
      expect(res.first).to(be_a(Hash))
      expect(res.map{ |i| i[:name]}).to(include(NAME_FILE1))
    end
    it "works on file #{PATH_FILE_EXIST}" do
      res = ascmd.execute_single(:ls, [PATH_FILE_EXIST])
      expect(res).to(be_a(Array))
      expect(res.first).to(be_a(Hash))
      expect(res.map{ |i| i[:name]}).to(match_array([NAME_FILE1]))
    end
  end
  describe 'mkdir' do
    it "works on folder #{PATH_FOLDER_NEW}" do
      res = ascmd.execute_single(:mkdir, [PATH_FOLDER_NEW])
      expect(res).to(be(true))
    end
  end
  describe 'cp' do
    it "works on files #{PATH_FILE_EXIST} #{PATH_FILE_COPY}" do
      res = ascmd.execute_single(:cp, [PATH_FILE_EXIST, PATH_FILE_COPY])
      expect(res).to(be(true))
    end
    it 'fails if no such file' do
      begin # rubocop:disable Style/RedundantBegin
        ascmd.execute_single(:mv, ['/does_not_exist', PATH_FOLDER_NEW])
        raise 'Shall not reach here'
      rescue Aspera::AsCmd::Error => e
        expect(e.message).to(eq('ascmd: No such file or directory (2)'))
      end
    end
  end
  describe 'rename' do
    it "works on folder #{PATH_FOLDER_NEW} #{PATH_FOLDER_RENAMED}" do
      res = ascmd.execute_single(:mv, [PATH_FOLDER_NEW, PATH_FOLDER_RENAMED])
      expect(res).to(be(true))
    end
    it 'works on file' do
      res = ascmd.execute_single(:mv, [PATH_FILE_COPY, PATH_FILE_RENAMED])
      expect(res).to(be(true))
    end
    it 'fails if no such file' do
      begin # rubocop:disable Style/RedundantBegin
        ascmd.execute_single(:mv, ['/does_not_exist', PATH_FOLDER_NEW])
        raise 'Shall not reach here'
      rescue Aspera::AsCmd::Error => e
        expect(e.message).to(eq('ascmd: No such file or directory (2)'))
      end
    end
  end
  describe 'md5sum' do
    it 'works on file' do
      res = ascmd.execute_single(:md5sum, [PATH_FILE_EXIST])
      expect(res).to(be_a(Hash))
      expect(res[:md5sum]).to(be_a(String))
    end
    it 'fails if no such file' do
      begin # rubocop:disable Style/RedundantBegin
        ascmd.execute_single(:md5sum, ['/does_not_exist'])
        raise 'Shall not reach here'
      rescue Aspera::AsCmd::Error => e
        expect(e.message).to(eq('ascmd: No such file or directory (2)'))
      end
    end
  end
  describe 'delete' do
    it 'works on file' do
      res = ascmd.execute_single(:rm, [PATH_FILE_RENAMED])
      expect(res).to(be(true))
    end
    it 'works on folder' do
      res = ascmd.execute_single(:rm, [PATH_FOLDER_RENAMED])
      expect(res).to(be(true))
    end
    it 'fails if no such file' do
      begin # rubocop:disable Style/RedundantBegin
        ascmd.execute_single(:mv, ['/does_not_exist', PATH_FOLDER_NEW])
        raise 'Shall not reach here'
      rescue Aspera::AsCmd::Error => e
        expect(e.message).to(eq('ascmd: No such file or directory (2)'))
      end
    end
  end
  describe 'df' do
    it 'works alone' do
      res = ascmd.execute_single(:df, [])
      expect(res).to(be_a(Array))
      expect(res.first).to(be_a(Hash))
      expect(res.first[:fs]).to(be_a(String))
      expect(res.first[:total]).to(be_a(Integer))
    end
    it 'fails if no such file' do
      begin # rubocop:disable Style/RedundantBegin
        ascmd.execute_single(:mv, ['/does_not_exist', PATH_FOLDER_NEW])
        raise 'Shall not reach here'
      rescue Aspera::AsCmd::Error => e
        expect(e.message).to(eq('ascmd: No such file or directory (2)'))
      end
    end
  end
end
RSpec.describe(Aspera::Ssh) do
  it 'catches error' do
    Aspera::Ssh.disable_ecd_sha2_algorithms
    demo_executor.execute('foo')
  rescue RuntimeError => e
    expect(e.message).to(eq('foo: [Command not accepted: foo]'))
  end
end
