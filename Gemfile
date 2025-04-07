# frozen_string_literal: true

source 'https://rubygems.org'

# gem's dependencies are in file <gem name>.gemspec
gemspec

# optional dependency gems for runtime that can cause problems (native part to compile) but seldom used
group :optional do
  gem('grpc', '~> 1.65') # for transferSDK
  gem('mimemagic', '~> 0.4') # for preview
  gem('rmagick', '~> 5.5') # for terminal view
  gem('symmetric-encryption', '~> 4.6') # for file vault
  gem('bigdecimal', '~> 3.1.9') if RUBY_VERSION >= '3.4' # for symmetric-encryption ?
end

group :development do
  gem 'grpc-tools', '~> 1.67.0'
  gem 'rake', '~> 13.0'
  gem 'reek', '~> 6.1.0'
  gem 'rspec', '~> 3.0'
  gem 'rubocop', '~> 1.12'
  gem 'rubocop-ast', '~> 1.4'
  gem 'rubocop-performance', '~> 1.10' unless defined?(JRUBY_VERSION)
  gem 'rubocop-shopify', '~> 2.0'
  gem 'ruby-lsp', '~> 0.23' unless defined?(JRUBY_VERSION)
  gem 'simplecov', '~> 0.22'
  gem 'solargraph', '~> 0.48' unless defined?(JRUBY_VERSION)
end
