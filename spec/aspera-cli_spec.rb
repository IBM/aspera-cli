# frozen_string_literal: true

require 'rspec'
require 'integration_helper'
require 'aspera/log'
# Aspera::Log.instance.level = :debug
# Aspera::Log.instance.logger_type = :stderr
require 'aspera/coverage'
require 'aspera/ascmd'
require 'aspera/ssh'
require 'uri'
require 'openssl'

ssh_url = URI.parse(RSpec.configuration.url)
# main folder relative to docroot and server executor
PATH_FOLDER_MAIN = '/'
ssh_options = {
  password:  RSpec.configuration.password,
  port:      ssh_url.port,
  use_agent: false
}
if defined?(JRUBY_VERSION)
  # :nocov:
  ssh_options.merge!({
    host_key:   %w[rsa-sha2-512 rsa-sha2-256],
    kex:        %w[curve25519-sha256 diffie-hellman-group14-sha256],
    encryption: %w[aes256-ctr aes192-ctr aes128-ctr]
  })
  # :nocov:
end
demo_executor = Aspera::Ssh.new(ssh_url.host, RSpec.configuration.username, **ssh_options)

TEST_RUN_ID = rand(1000).to_s
PATH_FOLDER_TINY = File.join(PATH_FOLDER_MAIN, 'aspera-test-dir-tiny')
PATH_FOLDER_DEST = File.join(PATH_FOLDER_MAIN, 'Upload')
PATH_FOLDER_NEW = File.join(PATH_FOLDER_DEST, "new_folder-#{TEST_RUN_ID}")
PATH_FOLDER_RENAMED = File.join(PATH_FOLDER_DEST, "renamed_folder-#{TEST_RUN_ID}")
NAME_FILE1 = '200KB.1'
PATH_FILE_EXIST = File.join(PATH_FOLDER_TINY, NAME_FILE1)
PATH_FILE_COPY = File.join(PATH_FOLDER_DEST, "#{NAME_FILE1}.copy1-#{TEST_RUN_ID}")
PATH_FILE_RENAMED = File.join(PATH_FOLDER_DEST, "#{NAME_FILE1}.renamed-#{TEST_RUN_ID}")
puts "Openssl version: #{OpenSSL::OPENSSL_VERSION}"

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
    it 'fails if no such folder' do
      expect do
        ascmd.execute_single(:cp, ['/does_not_exist', PATH_FOLDER_NEW])
      end.to(raise_error(Aspera::AsCmd::Error, 'ascmd: No such file or directory (2)'))
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
      expect do
        ascmd.execute_single(:mv, ['/does_not_exist', PATH_FOLDER_NEW])
      end.to(raise_error(Aspera::AsCmd::Error, 'ascmd: No such file or directory (2)'))
    end
  end
  describe 'md5sum' do
    it 'works on file' do
      res = ascmd.execute_single(:md5sum, [PATH_FILE_EXIST])
      expect(res).to(be_a(Hash))
      expect(res[:md5sum]).to(be_a(String))
    end
    it 'fails if no such file' do
      expect do
        ascmd.execute_single(:md5sum, ['/does_not_exist'])
      end.to(raise_error(Aspera::AsCmd::Error, 'ascmd: No such file or directory (2)'))
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
      expect do
        ascmd.execute_single(:mv, ['/does_not_exist', PATH_FOLDER_NEW])
      end.to(raise_error(Aspera::AsCmd::Error, 'ascmd: No such file or directory (2)'))
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
      expect do
        ascmd.execute_single(:mv, ['/does_not_exist', PATH_FOLDER_NEW])
      end.to(raise_error(Aspera::AsCmd::Error, 'ascmd: No such file or directory (2)'))
    end
  end
end

RSpec.describe(Aspera::Ssh) do
  it 'catches aspshell error in exception' do
    Aspera::Ssh.disable_ecd_sha2_algorithms
    expect do
      demo_executor.execute('foo', exception: true)
    end.to(raise_error(Aspera::Ssh::Error, /Command not accepted: foo/))
  end
end

RSpec.describe(Aspera::AssertError) do
  it 'works for list' do
    Aspera.assert_values(:bad, [:good])
    raise 'Shall not reach here'
  rescue Aspera::AssertError => e
    expect(e.message).to(start_with('assertion failed: expecting one of [:good], but have :bad'))
  end
end
