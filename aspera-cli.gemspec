# coding: utf-8
require_relative 'lib/aspera/cli/version'

Gem::Specification.new do |spec|
  # get location of this file (should be in project root)
  gemspec_file=File.expand_path(__FILE__)
  # expected extension of gemspec file
  GEMSPEC_EXT='.gemspec'
  raise "Error: this file extension must be '#{GEMSPEC_EXT}'" unless gemspec_file.end_with?(GEMSPEC_EXT)
  # the base name of this file shall be the gem name
  spec.name          = File.basename(gemspec_file,GEMSPEC_EXT).downcase
  spec.version       = Aspera::Cli::VERSION
  spec.authors       = ['Laurent Martin']
  spec.email         = ['laurent.martin.aspera@fr.ibm.com']
  spec.summary       = 'Command line tool for Aspera Server products: Aspera on Cloud, Faspex, Shares, Node, Console, Orchestrator, Transfer Server'
  spec.description   = 'A powerful CLI for IBM Aspera products'
  spec.homepage      = 'https://github.com/IBM/aspera-cli'
  spec.license       = 'Apache-2.0'
  spec.requirements << 'IBM Aspera ascp installed for the user'
  raise 'RubyGems 2.0 or newer is required' unless spec.respond_to?(:metadata)
  spec.metadata['allowed_push_host'] = 'https://rubygems.org' # push only to rubygems.org
  spec.metadata['homepage_uri']      = spec.homepage
  spec.metadata['source_code_uri']   = spec.homepage
  spec.metadata['changelog_uri']     = spec.homepage
  # assume this gemspec is in the root folder of project, and list git files from there
  Dir.chdir(File.dirname(gemspec_file)) do
    spec.files       =`git ls-files -z lib docs bin examples README.md`.split("\x0")
  end
  spec.bindir        = 'bin'
  spec.executables   = spec.files.grep(%r{^#{spec.bindir}}){|f|File.basename(f)}
  spec.require_paths = ['lib']
  spec.required_ruby_version = '> 2.3'
  spec.add_runtime_dependency('xml-simple', '~> 1.0')
  spec.add_runtime_dependency('jwt', '~> 2.0')
  spec.add_runtime_dependency('ruby-progressbar', '~> 1.0')
  spec.add_runtime_dependency('net-ssh', '~> 4.0')
  spec.add_runtime_dependency('mimemagic', '~> 0.3')
  spec.add_runtime_dependency('execjs', '~> 2.0')
  spec.add_runtime_dependency('terminal-table', '~> 1.8')
  spec.add_runtime_dependency('tty-spinner', '~> 0.9')
  spec.add_development_dependency('bundler', '~> 2.0')
  spec.add_development_dependency('rake', '~> 10.0')
  spec.add_development_dependency('rspec', '~> 3.0')
end
