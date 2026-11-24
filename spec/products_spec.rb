# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require 'open3'
require 'rbconfig'
require 'tmpdir'

RSpec.describe('Aspera::Products') do
  it 'finds an installed product with its product info file, loading only its own file' do
    Dir.mktmpdir do |root|
      script = <<~RUBY
        require 'aspera/products'
        require 'fileutils'
        root = ARGV.first
        FileUtils.mkdir_p(File.join(root, 'bin'))
        FileUtils.touch(File.join(root, 'bin', Aspera::Environment.instance.exe_file('ascp')))
        File.write(File.join(root, Aspera::Products::INFO_META_FILE), '<product><name>Spec Product</name><version>1.2.3</version></product>')
        found = Aspera::Products.find([{expected: 'spec', app_root: root}]).first
        print found.values_at(:name, :version).join(' ')
      RUBY
      out, status = Open3.capture2e(RbConfig.ruby, '-I', File.expand_path('../lib', __dir__), '-e', script, root)
      expect(status.success?).to(be(true), out)
      expect(out).to(eq('Spec Product 1.2.3'))
    end
  end

  describe 'products of the scan' do
    {
      'cli_v3' => 'Aspera CLI (deprecated)',
      'hsts'   => 'IBM Aspera High-Speed Transfer Server',
      'drive'  => 'Aspera Drive (deprecated)'
    }.each do |file, app_name|
      it "has a class with its name and its locations: #{file}" do
        require "aspera/products/#{file}"
        klass = Aspera::Products.const_get(file.split('_').map(&:capitalize).join)
        expect(klass::APP_NAME).to(eq(app_name))
        klass.locations.each do |location|
          expect(location[:expected]).to(eq(app_name))
          expect(location[:app_root]).to(be_a(String))
        end
      end
    end

    it 'has Drive on macOS only' do
      require 'aspera/products/drive'
      expect(Aspera::Products::Drive.locations.empty?).to(eq(!Aspera::Environment.instance.os.eql?(Aspera::Environment::OS_MACOS)))
    end
  end
end
