# frozen_string_literal: true

require 'bundler/setup'
require 'aspera/proxy_auto_config'
require 'aspera/uri_reader'

PAC_FILE = "file:///#{File.dirname(File.realpath(__FILE__), 2)}/tests/proxy.pac"

RSpec.describe(Aspera::ProxyAutoConfig) do
  it "get right proxy with #{PAC_FILE}" do
    expect(Aspera::ProxyAutoConfig.new(Aspera::UriReader.read(PAC_FILE)).find_proxy_for_url('http://eudemo.asperademo.com')).to(eq('PROXY proxy.example.com:8080'))
  end
end
