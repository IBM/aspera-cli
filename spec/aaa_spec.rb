# frozen_string_literal: true

require 'spec_helper'

require 'aspera/assert'
require 'aspera/uri_reader'
require 'aspera/coverage'
require 'aspera/environment'
require 'aspera/ascp/management'

describe 'Assert' do
  it 'works for list' do
    Aspera.assert_values(:bad, [:good])
    raise 'Shall not reach here'
  rescue Aspera::AssertError => e
    expect(e.message).to(start_with('assertion failed: expecting one of [:good], but have :bad'))
  end
end

describe 'UriReader' do
  it 'fails on bad uri' do
    Aspera::UriReader.read('unknown:///foo.bar')
    raise 'Shall not reach here'
  rescue Aspera::InternalError => e
    expect(e.message).to(include('unexpected value: "unknown"'))
  end
  it 'fails on bad file uri' do
    Aspera::UriReader.read_as_file('file:foo.bar')
    raise 'Shall not reach here'
  rescue RuntimeError => e
    expect(e.message).to(start_with('use format: file:///'))
  end
end

describe 'Environment' do
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
      'Elapsedusec'       => '10',
      'Encryption'        => 'Yes',
      'ExtraCreatePolicy' => 'none'
    }
    newevent = Aspera::Ascp::Management.enhanced_event_format(event)
    expect(newevent).to(eq({
      'bytes_cont'          => 1,
      'elapsed_usec'        => 10,
      'encryption'          => true,
      'extra_create_policy' => 'none'
    }))
  end
end
