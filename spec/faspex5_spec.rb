# frozen_string_literal: true

# Unit tests for Aspera::Cli::Plugins::Faspex5 — no server needed.

require 'aspera/cli/context'
require 'aspera/cli/parser'
require 'aspera/cli/plugins/faspex5'
require 'aspera/web_server_simple'
require 'securerandom'

module Aspera
  module Cli
    module Plugins
      RSpec.describe(Faspex5) do
        # @param argv [Array<String>] command line
        # @param link_context [Hash, nil] context of public link, or nil
        # @return [Faspex5] plugin with an API double
        def plugin(argv, link_context)
          context = Context.new
          context.man_header = false
          context.options = Parser.new('test', argv)
          instance = described_class.new(context: context)
          api = Struct.new(:pub_link_context).new(link_context)
          instance.define_singleton_method(:api_v5) { api }
          instance
        end

        describe '#action_postprocessing' do
          before { allow(WebServerSimple).to(receive(:new).and_return(instance_double(WebServerSimple, mount: nil, start: nil))) }

          # @param parameters [Hash] parameters of command
          def postprocessing(parameters)
            plugin([], nil).send(:action_postprocessing, parameters: parameters)
          end

          it 'starts without protection on a local address' do
            expect(postprocessing({'url' => 'http://127.0.0.1:8080/processing'})).to(be_a(Result::Status))
          end

          it 'refuses to start without protection on a non-local address' do
            expect { postprocessing({'url' => 'http://0.0.0.0:8080/processing'}) }.to(raise_error(BadArgument, /secret_token or allowed_ips is required/))
            expect(WebServerSimple).not_to(have_received(:new))
          end

          it 'starts with secret_token on a non-local address' do
            expect(postprocessing({'url' => 'http://0.0.0.0:8080/processing', 'secret_token' => SecureRandom.hex(32)})).to(be_a(Result::Status))
          end

          it 'starts with allowed_ips on a non-local address' do
            expect(postprocessing({'url' => 'http://myhost:8080/processing', 'allowed_ips' => '10.89.0.0/24'})).to(be_a(Result::Status))
          end
        end

        describe '#action_gateway' do
          before { allow(WebServerSimple).to(receive(:new).and_return(instance_double(WebServerSimple, mount: nil, start: nil))) }

          # @param parameters [Hash] parameters of command
          def gateway(parameters)
            plugin([], nil).send(:action_gateway, parameters: parameters)
          end

          it 'starts without credentials on a local address' do
            expect(gateway({'url' => 'http://127.0.0.1:8080/aspera/faspex'})).to(be_a(Result::Status))
          end

          it 'refuses to start without credentials on a non-local address' do
            expect { gateway({'url' => 'http://0.0.0.0:8080/aspera/faspex'}) }.to(raise_error(BadArgument, /username and password is required/))
            expect(WebServerSimple).not_to(have_received(:new))
          end

          it 'starts with credentials on a non-local address' do
            expect(gateway({'url' => 'http://0.0.0.0:8080/aspera/faspex', 'username' => 'fx4', 'password' => SecureRandom.hex(32)})).to(be_a(Result::Status))
          end

          it 'refuses a weak password' do
            expect { gateway({'username' => 'fx4', 'password' => SecureRandom.alphanumeric(3)}) }.to(raise_error(ParameterError, /password_min_bits/))
            expect(WebServerSimple).not_to(have_received(:new))
          end
        end

        describe '#persistency_user_id' do
          it 'is the username without public link' do
            expect(plugin(['--username=john'], nil).send(:persistency_user_id)).to(eq('john'))
          end

          it 'is specific to each public link, without username' do
            passcode = SecureRandom.alphanumeric(12)
            first = plugin([], {'passcode' => passcode, 'package_id' => '12'}).send(:persistency_user_id)
            second = plugin([], {'passcode' => SecureRandom.alphanumeric(12), 'package_id' => '12'}).send(:persistency_user_id)
            expect(first).not_to(eq(second))
            expect(first).not_to(include(passcode))
          end
        end
      end
    end
  end
end
