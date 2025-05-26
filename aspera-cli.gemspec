# frozen_string_literal: true

require_relative 'lib/aspera/cli/version'
require_relative 'lib/aspera/cli/info'

# expected extension of gemspec file
GEMSPEC_EXT = '.gemspec'
Gem::Specification.new do |spec|
  # get location of this file (shall be in project root)
  gemspec_file = File.expand_path(__FILE__)
  raise "Error: this file extension must be '#{GEMSPEC_EXT}'" unless gemspec_file.end_with?(GEMSPEC_EXT)
  raise "This file shall be named: #{Aspera::Cli::Info::GEM_NAME}#{GEMSPEC_EXT}" unless
    Aspera::Cli::Info::GEM_NAME.eql?(File.basename(gemspec_file, GEMSPEC_EXT).downcase)
  # the base name of this file shall be the gem name
  spec.name          = Aspera::Cli::Info::GEM_NAME
  spec.version       = ENV.fetch('GEM_VERSION', Aspera::Cli::VERSION)
  spec.authors       = ['Laurent Martin']
  spec.email         = ['laurent.martin.aspera@fr.ibm.com']
  spec.summary       = 'Execute actions using command line on IBM Aspera Server products: ' \
    'Aspera on Cloud, Faspex, Shares, Node, Console, Orchestrator, High Speed Transfer Server'
  spec.description   = 'Command line interface for IBM Aspera products'
  spec.homepage      = Aspera::Cli::Info::SRC_URL
  spec.license       = 'Apache-2.0'
  spec.requirements << 'Read the manual for any requirement'
  raise 'RubyGems 2.0 or newer is required' unless spec.respond_to?(:metadata)
  spec.metadata['allowed_push_host'] = 'https://rubygems.org' # push only to rubygems.org
  spec.metadata['homepage_uri']      = spec.homepage
  spec.metadata['source_code_uri']   = File.join(spec.homepage, 'tree/main/lib/aspera')
  spec.metadata['changelog_uri']     = File.join(spec.homepage, 'CHANGELOG.md')
  spec.metadata['rubygems_uri']      = Aspera::Cli::Info::GEM_URL
  spec.metadata['documentation_uri'] = Aspera::Cli::Info::DOC_URL
  spec.require_paths = ['lib']
  spec.bindir        = 'bin'
  # list git files from specified location in root folder of project (this gemspec is in project root folder)
  spec.files = Dir.chdir(File.dirname(gemspec_file)){%x(git ls-files -z lib bin examples *.md).split("\x0")}
  # specify executable names: must be after lines defining: spec.bindir and spec.files
  spec.executables = spec.files.grep(/^#{spec.bindir}/){ |f| File.basename(f)}
  spec.cert_chain  = ['certs/aspera-cli-public-cert.pem']
  if ENV.key?('SIGNING_KEY')
    spec.signing_key = File.expand_path(ENV.fetch('SIGNING_KEY'))
    raise "Missing SIGNING_KEY: #{spec.signing_key}" unless File.exist?(spec.signing_key)
  end
  # see also Aspera::Cli::Info::RUBY_FUTURE_MINIMUM_VERSION
  spec.required_ruby_version = '>= 3.1'
  spec.add_dependency('blankslate', '~> 3.1')
  spec.add_dependency('csv', '~> 3.0')
  spec.add_dependency('execjs', '~> 2.0')
  spec.add_dependency('jwt', '~> 2.0')
  spec.add_dependency('mime-types', '~> 3.5')
  spec.add_dependency('net-smtp', '~> 0.3') if defined?(JRUBY_VERSION)
  spec.add_dependency('net-ssh', '~> 7.3')
  spec.add_dependency('rainbow', '~> 3.0')
  spec.add_dependency('ruby-progressbar', '~> 1.0')
  spec.add_dependency('rubyzip', '~> 2.0')
  spec.add_dependency('terminal-table', '~> 3.0.2')
  spec.add_dependency('tty-spinner', '~> 0.9')
  spec.add_dependency('vault', '~> 0.18')
  spec.add_dependency('webrick', '~> 1.7')
  spec.add_dependency('websocket', '~> 1.2')
  spec.add_dependency('word_wrap', '~> 1.0')
  spec.add_dependency('xml-simple', '~> 1.0')
end
