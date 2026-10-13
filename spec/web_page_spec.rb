# frozen_string_literal: true

require 'aspera/web_page'
require 'webrick'

RSpec.describe(Aspera::WebPage) do
  describe '.secure_headers' do
    it 'sets HTML type, anti-framing, no-cache and same-origin referrer headers' do
      response = WEBrick::HTTPResponse.new(WEBrick::Config::HTTP)
      described_class.secure_headers(response)
      expect(response['Content-Type']).to(eq('text/html; charset=utf-8'))
      expect(response['X-Frame-Options']).to(eq('DENY'))
      expect(response['Content-Security-Policy']).to(eq("frame-ancestors 'none'"))
      expect(response['Cache-Control']).to(eq('no-store'))
      # not no-referrer: a form would be sent with Origin null
      expect(response['Referrer-Policy']).to(eq('same-origin'))
    end
  end
end
