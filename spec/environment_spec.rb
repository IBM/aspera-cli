# frozen_string_literal: true

require 'bundler/setup'
require 'aspera/environment'
require 'aspera/ascp/management'

RSpec.describe(Aspera::Environment) do
  it 'works for OSes' do
    RbConfig::CONFIG['host_os'] = 'mswin'
    Aspera::Environment.instance.initialize_fields
    expect(Aspera::Environment.instance.os).to(eq(Aspera::Environment::OS_WINDOWS))
    expect(Aspera::Environment.instance.exe_file).to(eq('.exe'))
    expect(Aspera::Environment.instance.exe_file('ascp')).to(eq('ascp.exe'))
    RbConfig::CONFIG['host_os'] = 'darwin'
    Aspera::Environment.instance.initialize_fields
    expect(Aspera::Environment.instance.os).to(eq(Aspera::Environment::OS_MACOS))
    RbConfig::CONFIG['host_os'] = 'linux'
    Aspera::Environment.instance.initialize_fields
    expect(Aspera::Environment.instance.os).to(eq(Aspera::Environment::OS_LINUX))
    expect(Aspera::Environment.instance.exe_file).to(eq(nil))
    expect(Aspera::Environment.instance.exe_file('ascp')).to(eq('ascp'))
    RbConfig::CONFIG['host_os'] = 'aix'
    Aspera::Environment.instance.initialize_fields
    expect(Aspera::Environment.instance.os).to(eq(Aspera::Environment::OS_AIX))
  end

  it 'works for CPUs' do
    RbConfig::CONFIG['host_cpu'] = 'x86_64'
    Aspera::Environment.instance.initialize_fields
    expect(Aspera::Environment.instance.cpu).to(eq(Aspera::Environment::CPU_X86_64))
    RbConfig::CONFIG['host_cpu'] = 'powerpc'
    RbConfig::CONFIG['host_os'] = 'linux'
    Aspera::Environment.instance.initialize_fields
    expect(Aspera::Environment.instance.cpu).to(eq(Aspera::Environment::CPU_PPC64LE))
    RbConfig::CONFIG['host_os'] = 'aix'
    Aspera::Environment.instance.initialize_fields
    expect(Aspera::Environment.instance.cpu).to(eq(Aspera::Environment::CPU_PPC64))
    RbConfig::CONFIG['host_cpu'] = 's390'
    Aspera::Environment.instance.initialize_fields
    expect(Aspera::Environment.instance.cpu).to(eq(Aspera::Environment::CPU_S390))
    RbConfig::CONFIG['host_cpu'] = 'arm'
    Aspera::Environment.instance.initialize_fields
    expect(Aspera::Environment.instance.cpu).to(eq(Aspera::Environment::CPU_ARM64))
  end

  it 'works for event' do
    event = {
      'Bytescont'         => '1',
      'Elapsedusec'       => '10',
      'Encryption'        => 'Yes',
      'ExtraCreatePolicy' => 'none'
    }
    newevent = Aspera::Ascp::Management.event_native_to_snake(event)
    expect(newevent).to(eq({
      'bytes_cont'          => 1,
      'elapsed_usec'        => 10,
      'encryption'          => true,
      'extra_create_policy' => 'none'
    }))
  end
end
