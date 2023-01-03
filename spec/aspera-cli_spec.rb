# frozen_string_literal: true

require 'spec_helper'

$LOAD_PATH.unshift(File.dirname(__FILE__) + '/../lib')
require 'aspera/cli/main'
require 'aspera/ascmd'
require 'aspera/ssh'
require 'aspera/log'
require 'uri'

#Aspera::Log.instance.level=:debug
#Aspera::Log.instance.logger_type=:stderr

class LocalExecutor
  def execute(cmd, line)
    %Q(echo "#{line}"|#{cmd})
  end
end

# check required env vars
params = {}
%i[url user pass].each do |p|
  env = "CF_HSTS_SSH_#{p.to_s.upcase}"
  params[p] = ENV[env]
  raise "missing env var: #{env}" unless params[p].is_a?(String)
end
ssh_url = URI.parse(params[:url])

# main folder relative to docroot and server executor
PATH_FOLDER_MAIN = '/'
demo_executor = Aspera::Ssh.new(ssh_url.host, params[:user], {password: params[:pass], port: ssh_url.port})

# to use a local executor, set PATH_FOLDER_MAIN to the main folder
#PATH_FOLDER_MAIN='/local/data'
#demo_executor=LocalExecutor.new
TEST_RUN_ID = rand(1000).to_s
PATH_FOLDER_TINY = File.join(PATH_FOLDER_MAIN, 'aspera-test-dir-tiny')
PATH_FOLDER_DEST = File.join(PATH_FOLDER_MAIN, 'Upload')
PATH_FOLDER_NEW = File.join(PATH_FOLDER_DEST, "newfolder-#{TEST_RUN_ID}")
PATH_FOLDER_RENAMED = File.join(PATH_FOLDER_DEST, "renamedfolder-#{TEST_RUN_ID}")
NAME_FILE1 = '200KB.1'
PATH_FILE_EXIST = File.join(PATH_FOLDER_TINY, NAME_FILE1)
PATH_FILE_COPY = File.join(PATH_FOLDER_DEST, NAME_FILE1 + ".copy1-#{TEST_RUN_ID}")
PATH_FILE_RENAMED = File.join(PATH_FOLDER_DEST, NAME_FILE1 + ".renamed-#{TEST_RUN_ID}")
PAC_FILE = 'file:///./examples/proxy.pac'

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
      res = ascmd.execute_single('info', [])
      expect(res).to(be_a(Hash))
      expect(res[:lang]).to(eq('C'))
    end
  end
  describe 'ls' do
    it "works on folder #{PATH_FOLDER_TINY}" do
      res = ascmd.execute_single('ls', [PATH_FOLDER_TINY])
      expect(res).to(be_a(Array))
      expect(res.first).to(be_a(Hash))
      expect(res.map{|i|i[:name]}).to(include(NAME_FILE1))
    end
    it "works on file #{PATH_FILE_EXIST}" do
      res = ascmd.execute_single('ls', [PATH_FILE_EXIST])
      expect(res).to(be_a(Array))
      expect(res.first).to(be_a(Hash))
      expect(res.map{|i|i[:name]}).to(match_array([NAME_FILE1]))
    end
  end
  describe 'mkdir' do
    it "works on folder #{PATH_FOLDER_NEW}" do
      res = ascmd.execute_single('mkdir', [PATH_FOLDER_NEW])
      expect(res).to(be(true))
    end
  end
  describe 'cp' do
    it "works on files #{PATH_FILE_EXIST} #{PATH_FILE_COPY}" do
      res = ascmd.execute_single('cp', [PATH_FILE_EXIST, PATH_FILE_COPY])
      expect(res).to(be(true))
    end
    it 'fails if no such file' do
      begin
        ascmd.execute_single('mv', ['/notexist', PATH_FOLDER_NEW])
        raise 'Shall not reach here'
      rescue Aspera::AsCmd::Error => e
        expect(e.message).to(eq('ascmd: (2) No such file or directory'))
      end
    end
  end
  describe 'rename' do
    it "works on folder #{PATH_FOLDER_NEW} #{PATH_FOLDER_RENAMED}" do
      res = ascmd.execute_single('mv', [PATH_FOLDER_NEW, PATH_FOLDER_RENAMED])
      expect(res).to(be(true))
    end
    it 'works on file' do
      res = ascmd.execute_single('mv', [PATH_FILE_COPY, PATH_FILE_RENAMED])
      expect(res).to(be(true))
    end
    it 'fails if no such file' do
      begin
        ascmd.execute_single('mv', ['/notexist', PATH_FOLDER_NEW])
        raise 'Shall not reach here'
      rescue Aspera::AsCmd::Error => e
        expect(e.message).to(eq('ascmd: (2) No such file or directory'))
      end
    end
  end
  describe 'md5sum' do
    it 'works on file' do
      res = ascmd.execute_single('md5sum', [PATH_FILE_EXIST])
      expect(res).to(be_a(Hash))
      expect(res[:md5sum]).to(be_a(String))
    end
    it 'fails if no such file' do
      begin
        ascmd.execute_single('md5sum', ['/notexist'])
        raise 'Shall not reach here'
      rescue Aspera::AsCmd::Error => e
        expect(e.message).to(eq('ascmd: (2) No such file or directory'))
      end
    end
  end
  describe 'delete' do
    it 'works on file' do
      res = ascmd.execute_single('rm', [PATH_FILE_RENAMED])
      expect(res).to(be(true))
    end
    it 'works on folder' do
      res = ascmd.execute_single('rm', [PATH_FOLDER_RENAMED])
      expect(res).to(be(true))
    end
    it 'fails if no such file' do
      begin
        ascmd.execute_single('mv', ['/notexist', PATH_FOLDER_NEW])
        raise 'Shall not reach here'
      rescue Aspera::AsCmd::Error => e
        expect(e.message).to(eq('ascmd: (2) No such file or directory'))
      end
    end
  end
  describe 'df' do
    it 'works alone' do
      res = ascmd.execute_single('df', [])
      expect(res).to(be_a(Array))
      expect(res.first).to(be_a(Hash))
      expect(res.first[:fs]).to(be_a(String))
      expect(res.first[:total]).to(be_a(Integer))
    end
    it 'fails if no such file' do
      begin
        ascmd.execute_single('mv', ['/notexist', PATH_FOLDER_NEW])
        raise 'Shall not reach here'
      rescue Aspera::AsCmd::Error => e
        expect(e.message).to(eq('ascmd: (2) No such file or directory'))
      end
    end
  end
end
