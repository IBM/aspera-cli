# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# The specs of a bundle are in its folder: `lib/aspera/plugins/<name>/spec/**/*_spec.rb` (not shipped in the gem).
# RSpec only looks in `spec/`, so this file loads them: `bundle exec rspec` and `rake spec` run them with all others.
Dir.glob(File.join(__dir__, '../lib/aspera/plugins/*/spec/**/*_spec.rb')).sort.each { |file| require(File.expand_path(file)) }
