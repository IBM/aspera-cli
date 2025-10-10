# frozen_string_literal: true

source 'https://rubygems.org'

# gem's dependencies are in file <gem name>.gemspec
gemspec

# optional dependency gems for runtime that can cause problems (native part to compile) but seldom used
group :optional do
  gem('grpc', '~> 1.71') unless defined?(JRUBY_VERSION) # for Aspera Transfer Daemon
  gem('mimemagic', '~> 0.4') # for preview
  gem('rmagick', '~> 6.1') unless defined?(JRUBY_VERSION) # for terminal view
  # gem('rmagick4j', '~> 0.3') if defined?(JRUBY_VERSION) # for terminal view
  gem('symmetric-encryption', '~> 4.6') # for encrypted hash file secrets
  gem('bigdecimal', '~> 3.1') if RUBY_VERSION >= '3.4' # for symmetric-encryption ?
  gem('sqlite3', '~> 2.7') unless defined?(JRUBY_VERSION) # for async DB
  gem('jdbc-sqlite3', '~> 3.46') if defined?(JRUBY_VERSION) # for async DB
  gem('sequel', '~> 5.96') if defined?(JRUBY_VERSION) # for async DB
end

# Used only for development
group :development do
  gem 'debug', '~> 1.11' unless defined?(JRUBY_VERSION)
  gem 'grpc-tools', '~> 1.67'
  gem 'rake', '~> 13.0'
  gem 'reek', '~> 6.5.0'
  gem 'rspec', '~> 3.0'
  gem 'rubocop', '~> 1.75'
  gem 'rubocop-ast', '~> 1.4'
  gem 'rubocop-performance', '~> 1.10' unless defined?(JRUBY_VERSION)
  gem 'rubocop-shopify', '~> 2.0'
  gem 'ruby-lsp', '~> 0.23' unless defined?(JRUBY_VERSION)
  gem 'simplecov', '~> 0.22'
  gem 'solargraph', '~> 0.48' unless defined?(JRUBY_VERSION)
end
