# frozen_string_literal: true

require 'spec_helper'

# top folder of project
project_top_folder = File.dirname(File.dirname(File.realpath(__FILE__)))
gem_lib_folder = File.join(project_top_folder, 'lib')
$LOAD_PATH.unshift(gem_lib_folder)
require 'aspera/coverage'
require 'aspera/environment'
require 'aspera/ascp/management'

describe 'environment' do
  it 'works for OSes' do
    RbConfig::CONFIG['host_os'] = 'mswin'
    expect(Aspera::Environment.os).to(eq(Aspera::Environment::OS_WINDOWS))
    expect(Aspera::Environment.exe_file).to(eq('.exe'))
    RbConfig::CONFIG['host_os'] = 'darwin'
    expect(Aspera::Environment.os).to(eq(Aspera::Environment::OS_MACOS))
    RbConfig::CONFIG['host_os'] = 'linux'
    expect(Aspera::Environment.os).to(eq(Aspera::Environment::OS_LINUX))
    expect(Aspera::Environment.exe_file).to(eq(''))
    RbConfig::CONFIG['host_os'] = 'aix'
    expect(Aspera::Environment.os).to(eq(Aspera::Environment::OS_AIX))
  end
  it 'works for CPUs' do
    RbConfig::CONFIG['host_cpu'] = 'x86_64'
    expect(Aspera::Environment.cpu).to(eq(Aspera::Environment::CPU_X86_64))
    RbConfig::CONFIG['host_cpu'] = 'powerpc'
    RbConfig::CONFIG['host_os'] = 'linux'
    expect(Aspera::Environment.cpu).to(eq(Aspera::Environment::CPU_PPC64LE))
    RbConfig::CONFIG['host_os'] = 'aix'
    expect(Aspera::Environment.cpu).to(eq(Aspera::Environment::CPU_PPC64))
    RbConfig::CONFIG['host_cpu'] = 's390'
    expect(Aspera::Environment.cpu).to(eq(Aspera::Environment::CPU_S390))
    RbConfig::CONFIG['host_cpu'] = 'arm'
    expect(Aspera::Environment.cpu).to(eq(Aspera::Environment::CPU_ARM64))
  end
  it 'works for event' do
    event = {
      'Bytescont'         => '1',
      'Encryption'        => 'Yes',
      'ExtraCreatePolicy' => 'none'
    }
    newevent = Aspera::Ascp::Management.enhanced_event_format(event)
    expect(newevent).to(eq({
      'bytescont'           => 1,
      'encryption'          => true,
      'extra_create_policy' => 'none'
    }))
  end
end
