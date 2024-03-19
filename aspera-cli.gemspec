# frozen_string_literal: true

require_relative 'lib/aspera/cli/version'
require_relative 'lib/aspera/cli/info'

# expected extension of gemspec file
GEMSPEC_EXT = '.gemspec'
Gem::Specification.new do |spec|
  # get location of this file (shall be in project root)
  gemspec_file = File.expand_path(__FILE__)
  raise "Error: this file extension must be '#{GEMSPEC_EXT}'" unless gemspec_file.end_with?(GEMSPEC_EXT)
  raise "This file shall be named: #{Aspera::Cli::GEM_NAME}#{GEMSPEC_EXT}" unless
    Aspera::Cli::GEM_NAME.eql?(File.basename(gemspec_file, GEMSPEC_EXT).downcase)
  # the base name of this file shall be the gem name
  spec.name          = Aspera::Cli::GEM_NAME
  spec.version       = ENV.fetch('GEM_VERSION', Aspera::Cli::VERSION)
  spec.authors       = ['Laurent Martin']
  spec.email         = ['laurent.martin.aspera@fr.ibm.com']
  spec.summary       = 'Execute actions using command line on IBM Aspera Server products: ' \
    'Aspera on Cloud, Faspex, Shares, Node, Console, Orchestrator, High Speed Transfer Server'
  spec.description   = 'Command line interface for IBM Aspera products'
  spec.homepage      = Aspera::Cli::SRC_URL
  spec.license       = 'Apache-2.0'
  spec.requirements << 'Read the manual for any requirement'
  raise 'RubyGems 2.0 or newer is required' unless spec.respond_to?(:metadata)
  spec.metadata['allowed_push_host'] = 'https://rubygems.org' # push only to rubygems.org
  spec.metadata['homepage_uri']      = spec.homepage
  spec.metadata['source_code_uri']   = File.join(spec.homepage, 'tree/main/lib/aspera')
  spec.metadata['changelog_uri']     = File.join(spec.homepage, 'CHANGELOG.md')
  spec.metadata['rubygems_uri']      = Aspera::Cli::GEM_URL
  spec.metadata['documentation_uri'] = Aspera::Cli::DOC_URL
  spec.require_paths = ['lib']
  spec.bindir        = 'bin'
  # list git files from specified location in root folder of project (this gemspec is in project root folder)
  spec.files = Dir.chdir(File.dirname(gemspec_file)){%x(git ls-files -z lib bin examples *.md).split("\x0")}
  # specify executable names: must be after lines defining: spec.bindir and spec.files
  spec.executables = spec.files.grep(/^#{spec.bindir}/){|f|File.basename(f)}
  spec.cert_chain  = ['certs/aspera-cli-public-cert.pem']
  spec.signing_key = File.expand_path(ENV.fetch('SIGNING_KEY')) if ENV.key?('SIGNING_KEY')
  # see also Aspera::Cli::RUBY_CURRENT_MINIMUM_VERSION
  spec.required_ruby_version = '>= 2.6'
  # dependency gems for runtime
  spec.add_runtime_dependency('base64', '~> 0.2.0')
  spec.add_runtime_dependency('bigdecimal', '~> 3.1', '>= 3.1.6')
  spec.add_runtime_dependency('blankslate', '~> 3.1')
  spec.add_runtime_dependency('csv', '~> 3.0')
  spec.add_runtime_dependency('execjs', '~> 2.0')
  spec.add_runtime_dependency('jwt', '~> 2.0')
  # spec.add_runtime_dependency('net-smtp', '~> 0.3') # it's part of base ruby
  spec.add_runtime_dependency('mime-types', '~> 3.5')
  spec.add_runtime_dependency('net-ssh', '~> 7.0')
  spec.add_runtime_dependency('rainbow', '~> 3.0')
  spec.add_runtime_dependency('ruby-progressbar', '~> 1.0')
  spec.add_runtime_dependency('rubyzip', '~> 2.0')
  spec.add_runtime_dependency('symmetric-encryption', '~> 4.6')
  spec.add_runtime_dependency('terminal-table', '~> 3.0.2')
  spec.add_runtime_dependency('tty-spinner', '~> 0.9')
  spec.add_runtime_dependency('webrick', '~> 1.7')
  spec.add_runtime_dependency('websocket', '~> 1.2')
  spec.add_runtime_dependency('xml-simple', '~> 1.0')
  # optional dependency gems for runtime that can cause problems (native part to compile) but seldom used
  # spec.add_development_dependency('grpc', '~> 1.0') # for transferSDK
  # spec.add_development_dependency('mimemagic', '~> 0.3') # for preview
  # spec.add_development_dependency('rmagick', '~> 5.3') # for terminal view
  # development gems
  # spec.add_development_dependency('bundler', '~> 2.4')
  spec.add_development_dependency('rake', '~> 13.0')
  spec.add_development_dependency('reek', '~> 6.1.0')
  spec.add_development_dependency('rspec', '~> 3.0')
  spec.add_development_dependency('rubocop', '~> 1.12')
  spec.add_development_dependency('rubocop-ast', '~> 1.4')
  spec.add_development_dependency('rubocop-performance', '~> 1.10')
  spec.add_development_dependency('rubocop-shopify', '~> 2.0')
  spec.add_development_dependency('simplecov', '~> 0.22')
  spec.add_development_dependency('solargraph', '~> 0.50')
end
