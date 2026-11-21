# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

source 'https://rubygems.org'

# Gem's dependencies are in file <gem name>.gemspec
gemspec

# Platforms other than JRuby: `%i[ruby windows]`, C Ruby (`ruby`: Linux, macOS) and Windows (`windows`).
# Literal in each line, not in a variable: tools that read the Gemfile as text (GitHub dependency graph, Dependabot) skip a gem whose platforms is a variable

# Used for development
group :build do
  gem('rake', '~> 13.0')
end

# Used only for development
group :development do
  gem('debug', '~> 1.11', platforms: %i[ruby windows])
  gem('grpc-tools', '~> 1.67')
  gem('reek', '~> 6.6.0')
  gem('rspec', '~> 3.0')
  gem('rubocop', '~> 1.75')
  gem('rubocop-ast', '~> 1.4')
  gem('rubocop-performance', '~> 1.10', platforms: %i[ruby windows])
  gem('rubocop-shopify', '~> 3.1')
  gem('simplecov', '~> 1.3')
  gem('solargraph', '~> 0.48', platforms: %i[ruby windows])
  gem('ferrum', '~> 0.20.1', platforms: %i[ruby windows])
end

# Optional dependency gems for runtime that can cause problems (native part to compile) but seldom used
group :optional do
  gem('mcp', '~> 1.2')  # for ascli mcp server (MCP protocol support)
  gem('rack', '~> 3.0') # for ascli mcp server HTTP transport (required by mcp StreamableHTTPTransport)
  gem('grpc', '~> 1.71', platforms: %i[ruby windows]) # for Aspera Transfer Daemon
  gem('sqlite3', '~> 2.7', platforms: %i[ruby windows]) # for async DB
  gem('jdbc-sqlite3', '~> 3.46', platforms: :jruby) # for async DB
  gem('sequel', '~> 5.96', platforms: :jruby) # for async DB
  gem('bcrypt_pbkdf', '~> 1.1', platforms: %i[ruby windows]) # for passphrase-protected OpenSSH private keys (ed25519 is native in net-ssh 8)
  gem('syslog', '~> 0.3', platforms: %i[ruby windows]) # for logger=syslog
  gem('zxcvbn', '~> 1.0') # for better estimate of secret strength (faspex5 postprocessing secret_token)
  gem('keeper_secrets_manager', '~> 17.2') # for vault of type keeper (Keeper Secrets Manager)
end

# Special dependency gems for runtime that can cause problems (native part to compile) but required for some features
group :special do
  gem('rmagick', '~> 7.2', platforms: %i[ruby windows]) # for terminal view
end
