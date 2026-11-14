# frozen_string_literal: true

# Unit tests for Aspera::Cli::Security and its use by ExtendedValue — no server, no config file needed.

require_relative '../lib/aspera/cli/security'
require_relative '../lib/aspera/cli/extended_value'
require_relative '../lib/aspera/cli/preset_manager'
require_relative '../lib/aspera/cli/option_value'
require_relative '../lib/aspera/cli/command_spec'
require_relative '../lib/aspera/schema/registry'
require 'base64'
require 'fileutils'
require 'securerandom'
require 'tmpdir'

module Aspera
  module Cli
    RSpec.describe(Security) do
      subject(:security) { described_class.instance }

      # Temporary folder: on macOS, its real path differs (symbolic link /var -> /private/var)
      let(:folder) { Dir.mktmpdir }
      let(:allowed_folder) { File.join(folder, 'allowed').tap { |path| Dir.mkdir(path) } }
      let(:allowed_file) { File.join(allowed_folder, 'key.pem').tap { |path| File.write(path, 'in folder') } }
      let(:other_file) { File.join(folder, 'other.txt').tap { |path| File.write(path, 'other') } }

      after do
        security.reset
        FileUtils.rm_rf(folder)
      end

      def evaluate(value) = ExtendedValue.instance.evaluate(value, context: 'test')

      # Value that decodes to an extended value: inserted as is by @extend:, not evaluated again
      def extend_file(path) = "@extend:@base64:#{Base64.strict_encode64("@file:#{path}@")}@"

      describe 'level low (default)' do
        it 'allows all extended values' do
          ENV['ASCLI_TEST_SECURITY'] = 'value'
          expect(security.level).to(eq(:low))
          expect(evaluate("@file:#{other_file}")).to(eq('other'))
          expect(evaluate(extend_file(other_file))).to(eq("@file:#{other_file}@"))
          expect(evaluate('@ruby:1+1')).to(eq(2))
          expect(evaluate('@env:ASCLI_TEST_SECURITY')).to(eq('value'))
        ensure
          ENV.delete('ASCLI_TEST_SECURITY')
        end
      end

      describe 'level high' do
        before { security.options = {'level' => 'high'} }

        it 'refuses @ruby:, @file:, @uri: and @env:' do
          ['@ruby:1+1', "@file:#{other_file}", "@uri:file://#{other_file}", '@env:HOME'].each do |value|
            expect { evaluate(value) }.to(raise_error(BadArgument, /extended value is disabled by security level high/))
          end
        end

        it 'does not evaluate @file: in a value decoded by @extend:' do
          expect(evaluate(extend_file(other_file))).to(eq("@file:#{other_file}@"))
        end

        it 'refuses @file: in a preset written with an encoded value' do
          presets = PresetManager.new(config_file: File.join(folder, 'config.yaml'))
          presets.set_key('x', 'k', evaluate("@base64:#{Base64.strict_encode64("@file:#{other_file}")}"))
          expect { presets.by_name('x.k') }.to(raise_error(BadArgument, /@file: extended value is disabled by security level high/))
        end

        it 'allows other extended values' do
          expect(evaluate('@json:{"a":1}')).to(eq({'a' => 1}))
        end
      end

      describe 'level medium' do
        before { security.options = {'level' => 'medium', 'allowed_paths' => [allowed_folder, other_file]} }

        it 'reads files in allowed paths' do
          expect(evaluate("@file:#{allowed_file}")).to(eq('in folder'))
          expect(evaluate("@file:#{other_file}")).to(eq('other'))
        end

        it 'refuses files outside of allowed paths, also with .. or a symbolic link, and missing files' do
          outside = File.join(folder, 'outside.txt').tap { |path| File.write(path, 'outside') }
          link = File.join(allowed_folder, 'link').tap { |path| File.symlink(outside, path) }
          [outside, File.join(allowed_folder, '..', 'outside.txt'), link, File.join(allowed_folder, 'missing')].each do |path|
            expect { evaluate("@file:#{path}") }.to(raise_error(BadArgument, /no such file in security.allowed_paths/))
          end
        end

        it 'refuses @ruby:, @uri: and @env:' do
          ['@ruby:1+1', "@uri:file://#{allowed_file}", '@env:HOME'].each do |value|
            expect { evaluate(value) }.to(raise_error(BadArgument, /extended value is disabled by security level medium/))
          end
        end
      end

      # Secret read by @secret: on terminal
      describe 'secret processed by another extended value' do
        let(:secret) { SecureRandom.alphanumeric(12) }

        around do |example|
          saved = Environment.instance.url_method
          Environment.instance.url_method = :text
          example.run
        ensure
          Environment.instance.url_method = saved
        end

        before { allow($stdin).to(receive_messages(tty?: true, getpass: secret)) }

        it 'is allowed with level low' do
          expect(evaluate('@list:@secret:pw')).to(eq(secret[1..].split(secret[0])))
          expect(evaluate('@extend:<@secret:pw@>')).to(eq("<#{secret}>"))
        end

        %w[medium high].each do |level|
          it "is refused with level #{level}, also in @extend: (a short secret is hidden only as whole value)" do
            security.options = {'level' => level}
            expect { evaluate('@list:@secret:pw') }.to(raise_error(BadArgument, /@list: cannot process a secret at security level #{level}/))
            expect { evaluate('@json:@secret:pw') }.to(raise_error(BadArgument, /@json: cannot process a secret/))
            allow($stdin).to(receive_messages(tty?: true, getpass: SecureRandom.alphanumeric(6)))
            expect { evaluate('@extend:<@secret:pw@>') }.to(raise_error(BadArgument, /@extend: cannot process a secret/))
          end
        end

        it 'is allowed with level high as whole value, and other values can be processed' do
          security.options = {'level' => 'high'}
          expect(evaluate('@secret:pw')).to(eq(secret))
          expect(evaluate("@json:@base64:#{Base64.strict_encode64('{"a":1}')}")).to(eq({'a' => 1}))
          expect(evaluate('@extend:<@base64:YQ==@>')).to(eq('<a>'))
        end

        it 'gives how to use the secret, and where to set the level' do
          security.lock('in test', default: :high)
          expect { evaluate('@list:@secret:pw') }.to(raise_error(BadArgument, /give the secret as the whole value, or use level low \(option security when starting/))
        end
      end

      describe '#options=' do
        it 'refuses a missing allowed path' do
          expect { security.options = {'level' => 'medium', 'allowed_paths' => [File.join(folder, 'missing')]} }
            .to(raise_error(BadArgument, /no such file or folder/))
        end

        it 'refuses a sub-option marked `x-security` in the schema, however it is given' do
          option = OptionValue.new(option: :out, allowed: [Hash, String], schema: Schema::Registry::OUT_OPTIONS)
          security.lock('in MCP server mode', default: :high)
          expect { option.assign_value({'file' => '/tmp/x'}, source: :cmdline) }.to(raise_error(BadArgument, /option out.file: disabled by security level high/))
          expect { option.assign_value({'format' => 'json'}, source: :cmdline) }.not_to(raise_error)
          expect { option.check_security({file: '/tmp/x'}) }.to(raise_error(BadArgument, /out.file/))
          ui = OptionValue.new(option: :ui, allowed: [Hash, String], schema: Schema::Registry::UI_OPTIONS)
          expect { ui.assign_value({'command' => ['x']}, source: :preset) }.to(raise_error(BadArgument, /ui.command/))
          expect { ui.assign_value({'mode' => 'terminal'}, source: :preset) }.not_to(raise_error)
        end

        it 'does not restrict values set by the program or by the environment of the process' do
          security.lock('in MCP server mode', default: :high)
          %i[default code env].each { |source| expect { OptionValue.new(option: :home, security: :low).assign_value('/x', source: source) }.not_to(raise_error) }
          %i[cmdline preset plugin_preset].each { |source| expect { OptionValue.new(option: :home, security: :low).assign_value('/x', source: source) }.to(raise_error(BadArgument)) }
        end

        it 'refuses an unknown level' do
          expect { security.options = {'level' => 'none'} }.to(raise_error(BadArgument, /security.level: expecting one of/))
        end
      end

      describe '#lock' do
        it 'sets the level when not set by option' do
          security.lock('in test', default: :high)
          expect(security.level).to(eq(:high))
        end

        it 'keeps the level set by option' do
          security.options = {'level' => 'medium', 'allowed_paths' => [allowed_folder]}
          security.lock('in test', default: :high)
          expect(security.level).to(eq(:medium))
        end

        it 'refuses changes, but accepts the same value again (e.g. from a preset read for each command), or no value' do
          security.options = {'level' => 'medium', 'allowed_paths' => [allowed_folder]}
          security.lock('in test', default: :high)
          expect { security.options = {'level' => 'medium', 'allowed_paths' => [allowed_folder]} }.not_to(raise_error)
          expect { security.options = {} }.not_to(raise_error)
          [{'level' => 'low'}, {'level' => 'medium', 'allowed_paths' => [folder]}, {'level' => 'medium'}].each do |value|
            expect { security.options = value }.to(raise_error(BadArgument, /security cannot be changed in test/))
          end
          expect(security.level).to(eq(:medium))
        end
      end

      describe '#writable_path' do
        let(:writable_folder) { File.join(folder, 'writable').tap { |path| Dir.mkdir(path) } }

        before { security.lock('in MCP server mode', default: :high) }

        it 'allows any path at level low' do
          security.reset
          expect(security.writable_path(File.join(folder, 'any', 'file.rb'))).to(eq(File.join(folder, 'any', 'file.rb')))
        end

        it 'refuses all paths when none is writable' do
          expect { security.writable_path(File.join(folder, 'file.rb')) }.to(raise_error(BadArgument, /writing is refused by security level high/))
        end

        it 'allows files, existing or not, in writable paths, and refuses others, also with .. or a symbolic link' do
          security.reset
          security.options = {'level' => 'high', 'writable_paths' => [writable_folder]}
          expect(security.writable_path(File.join(writable_folder, 'sub', 'new.txt'))).to(eq(File.join(File.realpath(writable_folder), 'sub', 'new.txt')))
          expect { security.writable_path(File.join(writable_folder, '..', 'plugins', 'x.rb')) }.to(raise_error(BadArgument))
          expect { security.writable_path("#{writable_folder}-other/x") }.to(raise_error(BadArgument))
          link = File.join(writable_folder, 'link')
          File.symlink(folder, link)
          expect { security.writable_path(File.join(link, 'x.rb')) }.to(raise_error(BadArgument))
        end

        it 'cannot be changed when locked' do
          expect { security.options = {'writable_paths' => [writable_folder]} }.to(raise_error(BadArgument, /cannot be changed/))
        end
      end

      describe '#check_level' do
        it 'allows any feature without attribute, and `low` features at level low' do
          expect { security.check_level(nil, 'x') }.not_to(raise_error)
          expect { security.check_level(:low, 'x') }.not_to(raise_error)
          expect(security.allowed?(:high)).to(be(true))
        end

        it 'refuses features above their level, and tells how to allow them' do
          security.lock('in MCP server mode', default: :high)
          expect { security.check_level(:low, 'option notify_template') }.to(raise_error(BadArgument, /option notify_template: disabled by security level high: use level low/))
          expect { security.check_level(:medium, 'x') }.to(raise_error(BadArgument, /use level medium/))
          expect { security.check_level(:high, 'x') }.not_to(raise_error)
        end

        it 'allows `medium` features at level medium only up to medium' do
          security.lock('in MCP server mode', default: :medium)
          expect { security.check_level(:medium, 'x') }.not_to(raise_error)
          expect { security.check_level(:low, 'x') }.to(raise_error(BadArgument))
        end
      end

      describe 'attribute `security:`' do
        it 'refuses to set an option from command line or preset above its level, not from the program' do
          option = OptionValue.new(option: :notify_template, security: :low)
          security.lock('in MCP server mode', default: :high)
          expect { option.assign_value('<%= 1 %>', source: :cmdline) }.to(raise_error(BadArgument, /option notify_template: disabled by security level high/))
          expect { option.assign_value('<%= 1 %>', source: :preset) }.to(raise_error(BadArgument))
          expect { option.assign_value('<%= 1 %>', source: :default) }.not_to(raise_error)
          expect(option.value).to(eq('<%= 1 %>'))
        end

        it 'allows the option at level low' do
          option = OptionValue.new(option: :notify_template, security: :low)
          expect { option.assign_value('x', source: :cmdline) }.not_to(raise_error)
        end

        it 'refuses an unknown level' do
          expect { OptionValue.new(option: :x, security: :none) }.to(raise_error(Aspera::AssertError))
          expect { CommandSpec.new(id: :x, description: 'x', security: :none) }.to(raise_error(Aspera::AssertError))
        end

        it 'refuses a command above its level' do
          expect(Security.instance.allowed?(CommandSpec.new(id: :x, description: 'x', security: :low).security)).to(be(true))
          security.lock('in MCP server mode', default: :high)
          expect(security.allowed?(CommandSpec.new(id: :x, description: 'x', security: :low).security)).to(be(false))
        end
      end

      describe '#check_stored_value' do
        it 'accepts any value at level low' do
          expect { security.check_stored_value({'a' => ['@ruby:1']}, 'preset') }.not_to(raise_error)
        end

        it 'refuses at level high a value that holds a refused extended value, at any depth' do
          security.lock('in MCP server mode', default: :high)
          expect { security.check_stored_value('@val:@ruby:1+1', 'preset option p') }.to(raise_error(BadArgument, /cannot store @ruby:/))
          expect { security.check_stored_value({'a' => ['@env:HOME']}, 'preset') }.to(raise_error(BadArgument, /@env:/))
          expect { security.check_stored_value('@json:{"a":1}', 'preset') }.not_to(raise_error)
        end
      end

      describe 'error message' do
        it 'gives the level that allows a refused extended value, and where to set it' do
          security.options = {'level' => 'high'}
          expect { evaluate("@file:#{other_file}") }.to(raise_error(BadArgument, /use level medium with the file in security.allowed_paths \(option security\), or give the value itself/))
          expect { evaluate('@env:HOME') }.to(raise_error(BadArgument, /use level low \(option security\)/))
        end

        it 'says that a locked level is set when starting' do
          security.lock('in test', default: :high)
          expect { evaluate("@file:#{other_file}") }.to(raise_error(BadArgument, /option security when starting, as it cannot be changed in test/))
        end
      end
    end
  end
end
