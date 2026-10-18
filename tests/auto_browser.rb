# frozen_string_literal: true

require 'uri'
require 'optparse'
require 'aspera/environment'
require 'aspera/rest'
require 'aspera/mime'
require_relative '../build/lib/paths'

# Automated browser script using Google Chrome (Ferrum) with HTTP fallback.
# Intercepts URLs opened by ascli (secrets, OAuth consent, etc.),
# renders the HTML/CSS in Chrome, fills the forms, and submits without human interaction.

# Preset of the test configuration file that holds the login credentials, see `select_login_preset` in test_helpers.rb
login_preset = nil
OptionParser.new do |opts|
  opts.banner = 'Usage: auto_browser.rb [--login-preset=<preset>] <url>'
  opts.on('--login-preset=PRESET', 'Preset with username and password for login pages') { |v| login_preset = v }
end.parse!

url_str = ARGV[0]
if url_str.nil? || url_str.empty?
  warn('Usage: auto_browser.rb [--login-preset=<preset>] <url>')
  exit(1)
end

uri = URI.parse(url_str)
test_secret = ENV['TEST_SECRET'] || 'my_secret_here'

# Check if Ferrum (Chrome automation) is available
ferrum_available = false
begin
  require 'ferrum'
  ferrum_available = true
rescue LoadError
  ferrum_available = false
end

# Helper to type text slowly character by character
# @param element [Ferrum::Node] DOM element
# @param text    [String] Text to type
# @param delay   [Float] Delay per character
def type_slowly(element, text, delay)
  element.focus
  if delay.positive?
    text.each_char do |char|
      element.type(char)
      sleep(delay)
    end
  else
    element.type(text)
  end
end

# Read one value of a preset using ascli itself: all extended values are evaluated by ascli
# (`@vault:`, `@file:`, `@extend:`, `@preset:`...), with the same home and config file as the tests.
# @param preset [String] Name of the preset in the test configuration file
# @param key    [String] Name of the value in the preset
# @return [String, nil] Evaluated value, or nil if not found
def preset_value(preset, key)
  stdout, _stderr, status = Aspera::Environment.secure_execute(
    File.join(Paths::BIN, 'ascli'), "--home=#{Paths::TMP / 'ascli_home'}", '--interactive=no', 'config', 'echo', "@preset:#{preset}.#{key}",
    mode:       :capture,
    exception:  false,
    stdin_data: ''
  )
  status.success? && !stdout.empty? ? stdout.chomp : nil
end

# Retrieve login credentials (evaluated once) from the preset given with option `--login-preset`.
# Values in the preset may be extended values, e.g. a reference to a vault.
# @param preset [String, nil] Name of the preset, or nil if the test did not select one
# @return [Hash] {:username => String, :password => String}, empty if no preset
def login_credentials(preset)
  @login_credentials ||=
    if preset.nil?
      {}
    else
      {username: preset_value(preset, 'username'), password: preset_value(preset, 'password')}.compact
    end
end

# Automate page with Google Chrome via Ferrum
# @param target_uri [URI] Target URL
# @param secret     [String] Secret value to fill
# @param login_preset [String, nil] Preset holding the login credentials
def automate_with_chrome(target_uri, secret, login_preset)
  headless = ENV['TEST_HEADLESS'].to_s.eql?('true')
  # Default visual delay: 0.5s pause between actions (configurable with TEST_DELAY)
  delay = ENV.fetch('TEST_DELAY', headless ? '0' : '0.5').to_f
  char_delay = delay.positive? ? [delay / 10.0, 0.05].max : 0.0

  browser = Ferrum::Browser.new(
    headless:        headless,
    slowmo:          delay.positive? ? 0.1 : 0.0,
    timeout:         15,
    process_timeout: 15,
    browser_options: {'no-sandbox' => nil, 'disable-gpu' => nil}
  )

  browser.goto(target_uri.to_s)
  sleep(delay) if delay.positive?

  case target_uri.path
  when %r{^/secret/}
    secret_input = browser.at_css('input[name="secret"]')
    raise "Secret input not found on page #{target_uri}" unless secret_input

    access_code_input = browser.at_css('input[name="access_code"]')
    if access_code_input
      type_slowly(access_code_input, ENV['MCP_AUTH_TOKEN'] || 'test-secret', char_delay)
      sleep(delay) if delay.positive?
    end

    type_slowly(secret_input, secret, char_delay)
    sleep(delay) if delay.positive?

    submit_btn = browser.at_css('button.allow, button[type="submit"]')
    submit_btn&.click
    # Pause on the confirmation screen so the user can see it
    sleep(delay.positive? ? delay * 2 : 0.3)
  when %r{^/oauth/authorize}
    access_input = browser.at_css('input[name="consent_secret"]')
    if access_input
      type_slowly(access_input, ENV['MCP_AUTH_TOKEN'] || 'test-secret', char_delay)
      sleep(delay) if delay.positive?
    end

    allow_btn = browser.at_css('button.allow, button[value="allow"], button[type="submit"]')
    allow_btn&.click
    sleep(delay.positive? ? delay * 2 : 0.3)
  else
    # External URL (e.g. SaaS OAuth login on api.ibmaspera.com):
    # Wait until redirected back to localhost/loopback callback server
    params = Aspera::Rest.query_to_h(target_uri.query || '')
    redirect_uri_str = params['redirect_uri']
    if redirect_uri_str
      redirect_port = URI.parse(redirect_uri_str).port
      max_wait = (ENV['TEST_LOGIN_TIMEOUT'] || '120').to_i
      start_time = Time.now
      w3id_clicked = false

      loop do
        break if browser.url.include?("localhost:#{redirect_port}") || browser.url.include?("127.0.0.1:#{redirect_port}")
        break if Time.now - start_time > max_wait

        # Automatically click "w3id (IBM)" button if present
        unless w3id_clicked
          w3id_btn = browser.xpath('//button[contains(translate(., "W", "w"), "w3id")] | //a[contains(translate(., "W", "w"), "w3id")] | //div[@role="button"][contains(translate(., "W", "w"), "w3id")] | //*[contains(text(), "w3id")]').first
          if w3id_btn
            sleep(delay) if delay.positive?
            w3id_btn.click
            w3id_clicked = true
            sleep(1)
          end
        end

        # Fill credentials from test configuration or vault if login fields are present
        creds = login_credentials(login_preset)
        if creds[:username]
          user_field = browser.at_css('input[type="email"], input[name="username"], input[name="userid"], input[id="username"], input[id="userid"]')
          if user_field && user_field.value.to_s.empty?
            type_slowly(user_field, creds[:username], char_delay)
            sleep(delay) if delay.positive?
            next_btn = browser.at_css('button#continue-button, button[type="submit"]')
            next_btn&.click
            sleep(1)
          end
        end

        if creds[:password]
          pass_field = browser.at_css('input[type="password"]')
          if pass_field && pass_field.value.to_s.empty?
            type_slowly(pass_field, creds[:password], char_delay)
            sleep(delay) if delay.positive?
            submit_btn = browser.at_css('button#signinbutton, button[type="submit"], input[type="submit"]')
            submit_btn&.click
            sleep(1)
          end
        end

        sleep(0.5)
      end
    end
  end
ensure
  browser&.quit
end

# Fallback HTTP submission using Aspera::Rest
# @param target_uri [URI] Target URL
# @param secret     [String] Secret value
def fallback_http(target_uri, secret)
  api = Aspera::Rest::Client.new(base_url: "#{target_uri.scheme}://#{target_uri.host}:#{target_uri.port}")
  subpath = target_uri.path.delete_prefix('/')

  case target_uri.path
  when %r{^/secret/}
    _html, get_res = api.read(subpath, ret: :both, exception: false)
    unless get_res.code == '200'
      warn("Error: Expected 200 from secret page, got #{get_res.code}")
      exit(1)
    end

    form_data = {'secret' => secret, 'decision' => 'submit'}
    post_res = api.create(subpath, form_data, content_type: Aspera::Mime::WWW, exception: false, ret: :resp)
    unless %w[200 302].include?(post_res.code)
      warn("Error: Unexpected response after secret submit: #{post_res.code}")
      exit(1)
    end
  when %r{^/oauth/authorize}
    params = Aspera::Rest.query_to_h(target_uri.query || '')
    _html, get_res = api.read(subpath, params, ret: :both, exception: false)
    unless get_res.code == '200'
      warn("Error: Expected 200 from consent page, got #{get_res.code}")
      exit(1)
    end

    consent_params = {
      'client_id'             => params['client_id'],
      'redirect_uri'          => params['redirect_uri'],
      'state'                 => params['state'],
      'code_challenge'        => params['code_challenge'],
      'code_challenge_method' => params['code_challenge_method'],
      'decision'              => 'allow',
      'consent_secret'        => ENV['MCP_AUTH_TOKEN'] || 'test-secret'
    }.compact

    post_res = api.create(subpath, consent_params, content_type: Aspera::Mime::WWW, exception: false, ret: :resp)
    unless %w[200 302].include?(post_res.code)
      warn("Error: Unexpected response after consent submit: #{post_res.code}")
      exit(1)
    end
  end
end

case uri.host
when '127.0.0.1', 'localhost', '::1'
  if ferrum_available
    begin
      automate_with_chrome(uri, test_secret, login_preset)
    rescue StandardError => e
      warn("Chrome automation failed (#{e.message}), falling back to HTTP")
      fallback_http(uri, test_secret)
    end
  else
    fallback_http(uri, test_secret)
  end
else
  # External/Remote OAuth login URL (e.g. Aspera on Cloud / Faspex 5)
  if ferrum_available
    automate_with_chrome(uri, test_secret, login_preset)
  elsif ENV['TEST_INTERACTIVE'].to_s.eql?('manual')
    case RbConfig::CONFIG['host_os']
    when /darwin|mac os/ then system('open', uri.to_s)
    when /linux/ then system('xdg-open', uri.to_s)
    when /mswin|msys|mingw|cygwin/ then system('start', 'explorer', uri.to_s)
    end
  else
    warn("Auto-browser: skipping external GUI browser for #{uri}")
  end
end
