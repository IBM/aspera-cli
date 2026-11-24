# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require 'open3'
require 'rbconfig'
require 'tmpdir'

RSpec.describe('Aspera::Products::Other') do
  it 'finds an installed product with its product info file, loading only its own file' do
    Dir.mktmpdir do |root|
      script = <<~RUBY
        require 'aspera/products/other'
        require 'fileutils'
        root = ARGV.first
        FileUtils.mkdir_p(File.join(root, 'bin'))
        FileUtils.touch(File.join(root, 'bin', Aspera::Environment.instance.exe_file('ascp')))
        File.write(File.join(root, Aspera::Products::Other::INFO_META_FILE), '<product><name>Spec Product</name><version>1.2.3</version></product>')
        found = Aspera::Products::Other.find([{expected: 'spec', app_root: root}]).first
        print found.values_at(:name, :version).join(' ')
      RUBY
      out, status = Open3.capture2e(RbConfig.ruby, '-I', File.expand_path('../lib', __dir__), '-e', script, root)
      expect(status.success?).to(be(true), out)
      expect(out).to(eq('Spec Product 1.2.3'))
    end
  end
end
