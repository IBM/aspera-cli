# frozen_string_literal: true

# `config agents jobs list|status|cleanup` and the deprecated alias `config transfer ...`: same commands, no server needed.

require 'spec_helper'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'json'
require 'aspera/cli/info'

RSpec.describe('config agents jobs') do
  let(:source_root) { File.expand_path('..', __dir__) }

  def run_cli(*args)
    Dir.mktmpdir do |home|
      cmd = [RbConfig.ruby, "-I#{source_root}/lib", File.join(source_root, 'bin', Aspera::Cli::Info::CMD_NAME), *args, '--version-check-days=0']
      stdout, stderr, status = Open3.capture3({'ASCLI_HOME' => home}, *cmd)
      [stdout, stderr, status]
    end
  end

  it 'lists jobs, with no deprecation warning' do
    stdout, stderr, status = run_cli('config', 'agents', 'jobs', 'list', '--format=json')
    expect(status.exitstatus).to(eq(0), stderr)
    expect(JSON.parse(stdout)).to(eq([]))
    expect(stderr).not_to(include('deprecated'))
  end

  it 'refuses an unknown job' do
    _stdout, stderr, status = run_cli('config', 'agents', 'jobs', 'status', 'nojob')
    expect(status.exitstatus).not_to(eq(0))
    expect(stderr).to(include('Unknown job_id: nojob'))
  end

  describe 'deprecated config transfer' do
    it 'still lists jobs, with a deprecation warning' do
      stdout, stderr, status = run_cli('config', 'transfer', 'list', '--format=json')
      expect(status.exitstatus).to(eq(0), stderr)
      expect(JSON.parse(stdout)).to(eq([]))
      expect(stderr).to(include('Command config transfer is deprecated after'))
    end

    it 'runs the same commands' do
      _stdout, stderr, status = run_cli('config', 'transfer', 'status', 'nojob')
      expect(status.exitstatus).not_to(eq(0))
      expect(stderr).to(include('Unknown job_id: nojob'))
    end

    it 'shows deprecation in the list of commands' do
      stdout, stderr, status = run_cli('config', 'commands', 'config', '--format=json')
      expect(status.exitstatus).to(eq(0), stderr)
      rows = JSON.parse(stdout)
      expect(rows.find { |r| r['syntax'].start_with?('config transfer ') }['description']).to(include('deprecated after 4.28.0: use agents jobs'))
      expect(rows.map { |r| r['syntax'] }).to(include('config agents jobs list', 'config agents jobs status <job_id>', 'config agents jobs cleanup'))
    end
  end
end
