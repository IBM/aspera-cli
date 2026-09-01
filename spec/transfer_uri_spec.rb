# frozen_string_literal: true

require 'bundler/setup'
require 'aspera/transfer/uri'
require 'uri'

SAMPLE_FASPE_URI = URI::Generic.build(
  scheme:   'faspe',
  userinfo: 'my_user_here:my_pass_here',
  host:     'host',
  port:     33_001,
  path:     '/path',
  query:    URI.encode_www_form(
    cookie:      'foo',
    token:       'foo',
    sshfp:       'foo',
    policy:      'foo',
    httpport:    'foo',
    targetrate:  'foo',
    minrate:     'foo',
    port:        'foo',
    bwcap:       'foo',
    enc:         'foo',
    tags64:      'ImZvbyIK',
    createpath:  'no',
    fallback:    'no',
    lockpolicy:  'no',
    lockminrate: 'yes',
    auth:        'foo',
    v:           'foo',
    protect:     'foo'
  )
).to_s.freeze

RSpec.describe(Aspera::Transfer::Uri) do
  it 'parses a FASP URL' do
    uri = Aspera::Transfer::Uri.new("#{SAMPLE_FASPE_URI}&bad=xx")
    ts = uri.transfer_spec
    expect(ts).to(be_a(Hash))
    expect(ts['token']).to(eq('foo'))
    expect(ts['sshfp']).to(eq('foo'))
  end
end
