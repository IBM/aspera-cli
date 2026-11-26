# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require_relative '../lib/aspera/line_logger'
require 'logger'
require 'net/http'
require 'securerandom'
require 'stringio'
require 'webrick'

RSpec.describe(Aspera::LineLogger) do
  let(:log) { Aspera::Log.instance }
  let(:output) { StringIO.new }

  around do |example|
    saved_logger = log.logger
    log.instance_variable_set(:@logger, Logger.new(output))
    log.formatter = ->(_s, _d, _p, m) { "#{m}\n" }
    log.level = :trace2
    example.run
  ensure
    log.instance_variable_set(:@logger, saved_logger)
  end

  it 'hides in the debug output of Net::HTTP the values of cookies, and the code of a redirect URL' do
    # Values of secrets are generated, none in source
    cookies = %w[token refresh session].to_h { |k| [k, SecureRandom.alphanumeric(16)] }
    code = SecureRandom.alphanumeric(16)
    server = WEBrick::HTTPServer.new(Port: 0, BindAddress: '127.0.0.1', Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
    server.mount_proc('/login') do |_req, res|
      res.status = 302
      res['Location'] = "https://127.0.0.1/callback?code=#{code}&state=s1"
      res['Set-Cookie'] = "session_id=#{cookies['session']}; Path=/; HttpOnly"
    end
    thread = Thread.new { server.start }
    sleep(0.01) until server.status.eql?(:Running)
    http = Net::HTTP.new('127.0.0.1', server.config[:Port])
    http.set_debug_output(described_class.new(:trace2))
    response = http.request(Net::HTTP::Get.new('/login', 'Cookie' => "aoc.token=#{cookies['token']}; aoc.refresh=#{cookies['refresh']}; lang=en"))
    expect(response['Location']).to(include(code))
    [code, *cookies.values].each { |value| expect(output.string).not_to(include(value)) }
    expect(output.string).to(include('Cookie: aoc.token=', '; aoc.refresh=', '; lang=', 'Set-Cookie: session_id=', '; Path=/; HttpOnly', 'Location: https://127.0.0.1/callback?code=', '&state=s1'))
  ensure
    server&.shutdown
    thread&.join
  end
end
