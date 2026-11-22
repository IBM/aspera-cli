# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Fake plugins for the specs of the registry of plugins and of the hooks of bundles.

require_relative '../lib/aspera/bundle_registry'
require_relative '../lib/aspera/cli/plugins/base'
require_relative '../lib/aspera/string_ext'
require 'fileutils'
require 'yaml'

# Plugins written by the examples, in temporary folders: names start with `spec_bundle_`
module BundleRegistrySpecHelper
  # @param folder   [String] Plugin folder
  # @param name     [String] Name of the single file plugin
  # @param body     [String] Code of the class
  # @return [String] Path of the file
  def write_single(folder, name, body: '')
    path = File.join(folder, "#{name}.rb")
    File.write(path, <<~RUBY)
      module Aspera
        module Cli
          module Plugins
            class #{name.snake_to_capital} < Base
              #{body}
            end
          end
        end
      end
    RUBY
    path
  end

  # @param folder   [String]      Plugin folder
  # @param name     [String]      Name of the bundle
  # @param manifest [Hash, String] Manifest, or its YAML text, merged in a valid one if Hash
  # @param code     [String, nil] Code at the top of `commands.rb`, `nil`: no `commands.rb`
  # @return [String] Folder of the bundle
  def write_bundle(folder, name, manifest: {}, code: '')
    bundle = File.join(folder, name)
    FileUtils.mkdir_p(bundle)
    manifest = {'name' => name, 'title' => "Product #{name}", 'commands' => true}.merge(manifest).to_yaml if manifest.is_a?(Hash)
    File.write(File.join(bundle, Aspera::BundleRegistry::MANIFEST), manifest)
    unless code.nil?
      File.write(File.join(bundle, 'commands.rb'), <<~RUBY)
        #{code}
        module Aspera
          module Plugins
            module #{name.snake_to_capital}
              class Commands < Aspera::Cli::Plugins::Base
              end
            end
          end
        end
      RUBY
    end
    bundle
  end

  # @param bundle [String] Folder of a bundle
  # @param file   [String] File relative to the folder of the bundle
  # @param body   [String] Code inside the module of the bundle `Aspera::Plugins::<Name>`
  # @param code   [String] Code at the top of the file
  # @return [String] Path of the file
  def write_bundle_file(bundle, file, body, code: '')
    path = File.join(bundle, file)
    File.write(path, <<~RUBY)
      #{code}
      module Aspera
        module Plugins
          module #{File.basename(bundle).snake_to_capital}
            #{body}
          end
        end
      end
    RUBY
    path
  end

  # Remove the constants defined by the plugins of the examples
  def remove_spec_constants
    [Aspera::Cli::Plugins, defined?(Aspera::Plugins) ? Aspera::Plugins : nil].compact.each do |namespace|
      namespace.constants.grep(/\ASpecBundle/).each { |constant| namespace.send(:remove_const, constant) }
    end
  end
end
