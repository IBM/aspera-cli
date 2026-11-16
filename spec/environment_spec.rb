# frozen_string_literal: true

require_relative '../lib/aspera/environment'
require 'bundler/setup'
require 'tmpdir'
require 'securerandom'

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
    RbConfig::CONFIG['host_os'] = 'cosmo'
    Aspera::Environment.instance.initialize_fields
    expect(Aspera::Environment.instance.os).to(eq(Aspera::Environment::OS_LINUX))
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

  describe 'fix_ca_certificates' do
    let(:cert_vars) { [OpenSSL::X509::DEFAULT_CERT_FILE_ENV, OpenSSL::X509::DEFAULT_CERT_DIR_ENV] }

    around do |example|
      saved = cert_vars.to_h { |var| [var, ENV.delete(var)] }
      example.run
    ensure
      saved.each { |var, value| value.nil? ? ENV.delete(var) : ENV.store(var, value) }
    end

    before do
      skip('JRuby uses its own CA bundles') if defined?(JRUBY_VERSION)
      allow(File).to(receive(:exist?).and_call_original)
      allow(Dir).to(receive(:exist?).and_call_original)
    end

    def default_locations_exist(exist)
      allow(File).to(receive(:exist?).with(OpenSSL::X509::DEFAULT_CERT_FILE).and_return(exist))
      allow(Dir).to(receive(:exist?).with(OpenSSL::X509::DEFAULT_CERT_DIR).and_return(exist))
    end

    it 'uses system CA bundle when default locations do not exist' do
      Dir.mktmpdir do |tmpdir|
        bundle = File.join(tmpdir, 'ca-bundle.crt')
        File.write(bundle, '')
        stub_const('Aspera::Environment::CA_BUNDLE_FILES', [File.join(tmpdir, 'missing.crt'), bundle])
        default_locations_exist(false)
        expect(OpenSSL::SSL::SSLContext::DEFAULT_CERT_STORE).to(receive(:add_file).with(bundle))
        expect(Aspera::Environment.instance.fix_ca_certificates).to(eq(bundle))
        expect(ENV.fetch(OpenSSL::X509::DEFAULT_CERT_FILE_ENV)).to(eq(bundle))
      end
    end

    it 'keeps default locations when they exist' do
      default_locations_exist(true)
      expect(Aspera::Environment.instance.fix_ca_certificates).to(be_nil)
      expect(ENV).not_to(have_key(OpenSSL::X509::DEFAULT_CERT_FILE_ENV))
    end

    it 'keeps locations given by env var' do
      ENV[OpenSSL::X509::DEFAULT_CERT_DIR_ENV] = '/some/dir'
      default_locations_exist(false)
      expect(Aspera::Environment.instance.fix_ca_certificates).to(be_nil)
      expect(ENV).not_to(have_key(OpenSSL::X509::DEFAULT_CERT_FILE_ENV))
    end
  end

  describe '.terminal_supports_unicode?' do
    let(:env_vars) { Aspera::Environment::I18N_VARS + %w[WT_SESSION TERM_PROGRAM ConEmuANSI TERM] }

    around do |example|
      saved = env_vars.to_h { |var| [var, ENV.delete(var)] }
      example.run
    ensure
      saved.each { |var, value| value.nil? ? ENV.delete(var) : ENV.store(var, value) }
      described_class.unicode = nil
    end

    before do
      allow(described_class).to(receive(:terminal?).and_return(true))
      allow(Encoding).to(receive(:locale_charmap).and_return('US-ASCII'))
    end

    it 'is enabled when the locale charmap is UTF-8' do
      allow(Encoding).to(receive(:locale_charmap).and_return('UTF-8'))
      expect(described_class.terminal_supports_unicode?).to(be(true))
    end

    it 'is disabled when not a terminal' do
      allow(Encoding).to(receive(:locale_charmap).and_return('UTF-8'))
      allow(described_class).to(receive(:terminal?).and_return(false))
      expect(described_class.terminal_supports_unicode?).to(be(false))
    end

    it 'falls back to a locale variable for a locale not installed' do
      expect(described_class.terminal_supports_unicode?).to(be(false))
      ENV['LANG'] = 'en_US.utf8'
      expect(described_class.terminal_supports_unicode?).to(be(true))
    end

    it 'uses the locale variable with highest precedence' do
      ENV['LANG'] = 'en_US.UTF-8'
      ENV['LC_ALL'] = 'C'
      expect(described_class.terminal_supports_unicode?).to(be(false))
      ENV['LC_ALL'] = ''
      expect(described_class.terminal_supports_unicode?).to(be(true))
      ENV['LC_CTYPE'] = 'POSIX'
      expect(described_class.terminal_supports_unicode?).to(be(false))
    end

    it 'is overridden by option' do
      described_class.unicode = true
      allow(described_class).to(receive(:terminal?).and_return(false))
      expect(described_class.terminal_supports_unicode?).to(be(true))
    end

    it 'detects terminal hosts rendering Unicode on Windows, whatever the code page' do
      allow(Encoding).to(receive(:locale_charmap).and_return('CP437'))
      allow(described_class.instance).to(receive(:os).and_return(Aspera::Environment::OS_WINDOWS))
      expect(described_class.terminal_supports_unicode?).to(be(false))
      {'WT_SESSION' => 'f0e1d2c3', 'TERM_PROGRAM' => 'vscode', 'ConEmuANSI' => 'ON', 'TERM' => 'xterm-256color'}.each do |var, value|
        ENV[var] = value
        expect(described_class.terminal_supports_unicode?).to(be(true))
        ENV.delete(var)
      end
      ENV['TERM_PROGRAM'] = 'other'
      expect(described_class.terminal_supports_unicode?).to(be(false))
    end

    it 'ignores Windows terminal hosts on other OS' do
      allow(described_class.instance).to(receive(:os).and_return(Aspera::Environment::OS_LINUX))
      ENV['WT_SESSION'] = 'f0e1d2c3'
      ENV['TERM'] = 'xterm-256color'
      expect(described_class.terminal_supports_unicode?).to(be(false))
    end
  end

  describe '.char' do
    after { described_class.unicode = nil }

    it 'gives the Unicode character when Unicode is supported' do
      described_class.unicode = true
      expect(described_class.char('🔑')).to(eq('🔑'))
    end

    it 'gives the ASCII equivalent when Unicode is not supported' do
      described_class.unicode = false
      expect(described_class.char('🔑')).to(eq('***'))
      expect(described_class.char('→')).to(eq('->'))
    end

    it 'uses the given Unicode support' do
      described_class.unicode = false
      expect(described_class.char('…', unicode: true)).to(eq('…'))
    end

    it 'requires an ASCII equivalent' do
      expect { described_class.char('–') }.to(raise_error(Aspera::InternalError))
      expect(Aspera::Environment::UNICODE_TO_ASCII.values).to(all(be_ascii_only))
    end
  end

  describe '.write_file_restricted' do
    it 'creates the file with restricted access, not only after writing' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'secret')
        # Only the mode at creation is checked
        allow(described_class).to(receive(:restrict_file_access))
        secret = SecureRandom.alphanumeric(12)
        described_class.write_file_restricted(path) { secret }
        expect(File.read(path)).to(eq(secret))
        expect(File.stat(path).mode & 0o777).to(eq(0o600)) unless Gem.win_platform?
      end
    end
  end

  describe 'helpers' do
    it 'quotes for shell only when needed' do
      expect(described_class.shell_escape_pretty('a=b/c.d')).to(eq('a=b/c.d'))
      expect(described_class.shell_escape_pretty("it's a")).to(eq(%q('it'\''s a')))
    end

    it 'logs the command executed in debug' do
      messages = []
      allow(Aspera::Log.log).to(receive(:debug)) { |*_args, &block| messages.push(block&.call) }
      described_class.secure_execute('true', 'x y', env: {'V' => 'a b'})
      expect(messages).to(include("execute command: V='a b' true 'x y'"))
    end

    it 'restricts nothing on a path that does not exist, and warns on an error' do
      expect(described_class.restrict_file_access(File.join(Dir.tmpdir, SecureRandom.uuid))).to(be_nil)
      allow(Aspera::Log.log).to(receive(:warn))
      allow(File).to(receive(:chmod).and_raise(Errno::EPERM, 'denied'))
      described_class.restrict_file_access(Dir.tmpdir)
      expect(Aspera::Log.log).to(have_received(:warn).with(/denied/))
    end

    it 'has no terminal columns if size is unknown' do
      allow(described_class).to(receive(:terminal?).and_return(true))
      allow($stdout).to(receive(:winsize).and_raise(Errno::ENOTTY))
      expect(described_class.terminal_columns).to(be_nil)
    end

    it 'forces the C locale' do
      saved = described_class::I18N_VARS.to_h { |var| [var, ENV.fetch(var, nil)] }
      described_class.force_terminal_c
      expect(described_class::I18N_VARS.map { |var| ENV.fetch(var) }.uniq).to(eq(['C']))
    ensure
      saved&.each { |var, value| ENV[var] = value }
    end

    it 'uses the locale variables if the locale charmap is unknown' do
      allow(Encoding).to(receive(:locale_charmap).and_return('unknown-charmap'))
      allow(described_class.instance).to(receive(:os).and_return(Aspera::Environment::OS_LINUX))
      allow(ENV).to(receive(:values_at).with(*described_class::I18N_VARS).and_return([nil, 'C']))
      expect(described_class.unicode_environment?).to(be(false))
    end
  end

  describe 'opening URLs and files' do
    let(:env) { described_class.instance }
    let(:saved_vars) { %w[DISPLAY EDITOR HOME USERPROFILE] }

    around do |example|
      host_os = RbConfig::CONFIG['host_os']
      saved_env = ENV.to_h.slice(*saved_vars)
      example.run
    ensure
      RbConfig::CONFIG['host_os'] = host_os
      saved_vars.each { |var| ENV[var] = saved_env[var] }
      env.initialize_fields
    end

    # @param host_os [String]      value of RbConfig host_os
    # @param display [String, nil] value of DISPLAY
    def on_os(host_os, display: nil)
      RbConfig::CONFIG['host_os'] = host_os
      ENV['DISPLAY'] = display
      ENV.delete('EDITOR')
      env.initialize_fields
      allow(described_class).to(receive(:secure_execute))
    end

    it 'opens with the system command of the OS' do
      on_os('mswin')
      env.open_uri('https://example.com')
      expect(described_class).to(have_received(:secure_execute).with('start', 'explorer', '"https://example.com"'))
      env.open_editor('f.txt')
      expect(described_class).to(have_received(:secure_execute).with('notepad.exe', '"f.txt"'))
      on_os('linux', display: ':0')
      env.open_editor('f.txt')
      expect(described_class).to(have_received(:secure_execute).with('xdg-open', 'f.txt'))
      on_os('darwin')
      env.open_uri('https://example.com')
      expect(described_class).to(have_received(:secure_execute).with('open', 'https://example.com'))
    end

    it 'displays the URL without graphical display' do
      on_os('linux')
      expect(env.default_gui_mode).to(eq(:text))
      expect { env.open_uri('https://example.com') }.to(output(/please enter this URL in a browser/).to_stdout)
      expect { env.open_uri('file:///f') }.to(output(/USER ACTION: open this/).to_stdout)
    end

    it 'uses the browser command, and reports it if not found' do
      on_os('linux')
      env.browser_command = ['my-browser']
      allow(described_class).to(receive(:secure_execute).and_raise(Errno::ENOENT))
      expect { env.open_uri('https://example.com') }.to(raise_error(Aspera::ParameterError, /Browser command not found .*: my-browser/))
    ensure
      env.browser_command = nil
    end

    it 'sets HOME from USERPROFILE on Windows' do
      on_os('mswin')
      Dir.mktmpdir do |dir|
        ENV['USERPROFILE'] = dir
        env.fix_home
        expect(Dir.home).to(eq(dir))
      end
    end
  end
end
