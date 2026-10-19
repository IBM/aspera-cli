# frozen_string_literal: true

require 'bundler/setup'
require 'tmpdir'
require 'securerandom'
require 'aspera/environment'

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
end
