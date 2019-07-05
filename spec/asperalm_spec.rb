require 'spec_helper'

$LOAD_PATH.unshift(File.dirname(__FILE__)+"/../lib")
require 'asperalm/cli/main'
require 'asperalm/ascmd'
require 'asperalm/ssh'

#Asperalm::Log.level=:debug

class LocalExecutor
  def execute(cmd,line)
    `echo "#{line}"|#{cmd}`
  end
end

PATH_FOLDER_MAIN='/'
demo_executor=Asperalm::Ssh.new('eudemo.asperademo.com','asperaweb',{:password=>'demoaspera',:port=>33001})

#PATH_FOLDER_MAIN='/workspace/Rubytools/asperalm/local/PATH_FOLDER_MAIN'
#demo_executor=LocalExecutor.new

PATH_FOLDER_TINY=File.join(PATH_FOLDER_MAIN,'aspera-test-dir-tiny')
PATH_FOLDER_DEST=File.join(PATH_FOLDER_MAIN,'Upload')
PATH_FOLDER_NEW=File.join(PATH_FOLDER_DEST,'newfolder')
PATH_FOLDER_RENAMED=File.join(PATH_FOLDER_DEST,'renamedfolder')
NAME_FILE1='200KB.1'
PATH_FILE_EXIST=File.join(PATH_FOLDER_TINY,NAME_FILE1)
PATH_FILE_COPY=File.join(PATH_FOLDER_DEST,NAME_FILE1+'.copy1')
PATH_FILE_RENAMED=File.join(PATH_FOLDER_DEST,NAME_FILE1+'.renamed')

RSpec.describe Asperalm::Cli::Main do
  it "has a version number" do
    expect(Asperalm::Cli::Main.gem_version).not_to be(nil)
  end
end

RSpec.describe Asperalm::ProxyAutoConfig do
  it "get right proxy" do
    expect(Asperalm::ProxyAutoConfig.new(Asperalm::UriReader.read('file:///./examples/proxy.pac')).get_proxy('http://eudemo.asperademo.com')).to eq("PROXY proxy.example.com:8080")
  end
end

RSpec.describe Asperalm::AsCmd do
  ascmd=Asperalm::AsCmd.new(demo_executor)
  #    ['du','/Users/xfer'],
  #    ['df','/'],
  #    ['df'],
  describe "info" do
    it "works" do
      res=ascmd.execute_single('info',[])
      expect(res).to be_a(Hash)
      expect(res[:lang]).to eq("C")
    end
  end
  describe "ls" do
    it "works on folder" do
      res=ascmd.execute_single('ls',[PATH_FOLDER_TINY])
      expect(res).to be_a(Array)
      expect(res.first).to be_a(Hash)
      expect(res.map{|i|i[:name]}).to include(NAME_FILE1)
    end
    it "works on file" do
      res=ascmd.execute_single('ls',[PATH_FILE_EXIST])
      expect(res).to be_a(Array)
      expect(res.first).to be_a(Hash)
      expect(res.map{|i|i[:name]}).to match_array([NAME_FILE1])
    end
  end
  describe "mkdir" do
    it "works on folder" do
      res=ascmd.execute_single('mkdir',[PATH_FOLDER_NEW])
      expect(res).to be(true)
    end
  end
  describe "cp" do
    it "works on file" do
      res=ascmd.execute_single('cp',[PATH_FILE_EXIST,PATH_FILE_COPY])
      expect(res).to be(true)
    end
    it "fails if no such file" do
      res=nil
      begin
        res=ascmd.execute_single('mv',["/notexist",PATH_FOLDER_NEW])
        raise "Shall not reach here"
      rescue Asperalm::AsCmd::Error => e
        expect(e.message).to eq("ascmd: (2) No such file or directory")
      end
    end
  end
  describe "rename" do
    it "works on folder" do
      res=ascmd.execute_single('mv',[PATH_FOLDER_NEW,PATH_FOLDER_RENAMED])
      expect(res).to be(true)
    end
    it "works on file" do
      res=ascmd.execute_single('mv',[PATH_FILE_COPY,PATH_FILE_RENAMED])
      expect(res).to be(true)
    end
    it "fails if no such file" do
      res=nil
      begin
        res=ascmd.execute_single('mv',["/notexist",PATH_FOLDER_NEW])
        raise "Shall not reach here"
      rescue Asperalm::AsCmd::Error => e
        expect(e.message).to eq("ascmd: (2) No such file or directory")
      end
    end
  end
  describe "md5sum" do
    it "works on file" do
      res=ascmd.execute_single('md5sum',[PATH_FILE_EXIST])
      expect(res).to be_a(Hash)
      expect(res[:md5sum]).to be_a(String)
    end
    it "fails if no such file" do
      res=nil
      begin
        res=ascmd.execute_single('md5sum',["/notexist"])
        raise "Shall not reach here"
      rescue Asperalm::AsCmd::Error => e
        expect(e.message).to eq("ascmd: (2) No such file or directory")
      end
    end
  end
  describe "delete" do
    it "works on file" do
      res=ascmd.execute_single('rm',[PATH_FILE_RENAMED])
      expect(res).to be(true)
    end
    it "works on folder" do
      res=ascmd.execute_single('rm',[PATH_FOLDER_RENAMED])
      expect(res).to be(true)
    end
    it "fails if no such file" do
      res=nil
      begin
        res=ascmd.execute_single('mv',["/notexist",PATH_FOLDER_NEW])
        raise "Shall not reach here"
      rescue Asperalm::AsCmd::Error => e
        expect(e.message).to eq("ascmd: (2) No such file or directory")
      end
    end
  end
  describe "df" do
    it "works alone" do
      res=ascmd.execute_single('df',[])
      expect(res).to be_a(Array)
      expect(res.first).to be_a(Hash)
      expect(res.first[:fs]).to be_a(String)
      expect(res.first[:total]).to be_a(Integer)
    end
    it "fails if no such file" do
      res=nil
      begin
        res=ascmd.execute_single('mv',["/notexist",PATH_FOLDER_NEW])
        raise "Shall not reach here"
      rescue Asperalm::AsCmd::Error => e
        expect(e.message).to eq("ascmd: (2) No such file or directory")
      end
    end
  end
end
