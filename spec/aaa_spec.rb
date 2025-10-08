# frozen_string_literal: true

require 'spec_helper'

require 'aspera/assert'
require 'aspera/rest'
require 'aspera/uri_reader'
require 'aspera/coverage'
require 'aspera/environment'
require 'aspera/ascp/management'

RSpec.describe(Aspera::AssertError) do
  it 'works for list' do
    Aspera.assert_values(:bad, [:good])
    raise 'Shall not reach here'
  rescue Aspera::AssertError => e
    expect(e.message).to(start_with('assertion failed: expecting one of [:good], but have :bad'))
  end
end

RSpec.describe(Aspera::UriReader) do
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

RSpec.describe(Aspera::Environment) do
  it 'works for OSes' do
    RbConfig::CONFIG['host_os'] = 'mswin'
    Aspera::Environment.instance.initialize_fields
    expect(Aspera::Environment.instance.os).to(eq(Aspera::Environment::OS_WINDOWS))
    expect(Aspera::Environment.instance.executable_extension).to(eq('exe'))
    RbConfig::CONFIG['host_os'] = 'darwin'
    Aspera::Environment.instance.initialize_fields
    expect(Aspera::Environment.instance.os).to(eq(Aspera::Environment::OS_MACOS))
    RbConfig::CONFIG['host_os'] = 'linux'
    Aspera::Environment.instance.initialize_fields
    expect(Aspera::Environment.instance.os).to(eq(Aspera::Environment::OS_LINUX))
    expect(Aspera::Environment.instance.executable_extension).to(eq(nil))
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
    newevent = Aspera::Ascp::Management.enhanced_event_format(event)
    expect(newevent).to(eq({
      'bytes_cont'          => 1,
      'elapsed_usec'        => 10,
      'encryption'          => true,
      'extra_create_policy' => 'none'
    }))
  end
end

RSpec.describe(Aspera::Rest) do
  it 'build URI' do
    expect(Aspera::Rest.build_uri('https://locahost', 'q=e&p=1').to_s).to(eq('https://locahost?q=e&p=1'))
  end
  it 'parses php query' do
    expect(Aspera::Rest.query_to_h('q[]=1&q[]=2')).to(eq({'q'=>%w[1 2]}))
    expect(Aspera::Rest.query_to_h('q=1&q=2')).to(eq({'q'=>%w[1 2]}))
  end
end
