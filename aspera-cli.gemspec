# coding: utf-8
require_relative 'lib/aspera/cli/version'

Gem::Specification.new do |spec|
  spec.name          = 'aspera-cli'
  spec.version       = Aspera::Cli::VERSION
  spec.authors       = ['Laurent Martin']
  spec.email         = ['laurent.martin.aspera@fr.ibm.com']
  spec.summary       = 'gem and command line tool for Aspera Server products: Aspera on Cloud, Faspex, Shares, Node, Console, Orchestrator, Transfer Server'
  spec.description   = 'A powerful transfer gem and CLI for IBM Aspera products.'
  spec.homepage      = 'https://ibm.com/aspera'
  spec.license       = 'Apache-2.0'

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  else
    raise 'RubyGems 2.0 or newer is required to protect against public gem pushes.'
  end

  spec.files         = `git ls-files -z lib docs bin examples`.split("\x0").push('README.md')
  spec.bindir        = 'bin'
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']
  spec.required_ruby_version = '> 2.0'
  spec.add_runtime_dependency('xml-simple', '~> 1.0')
  spec.add_runtime_dependency('jwt', '>= 1.5.6')
  spec.add_runtime_dependency('ruby-progressbar', '~> 1.0')
  spec.add_runtime_dependency('net-ssh', '>= 4.0')
  spec.add_runtime_dependency('mimemagic', '~> 0.3')
  spec.add_runtime_dependency('execjs', '~> 2.0')
  spec.add_runtime_dependency('terminal-table', '~> 1.8')
  spec.add_runtime_dependency('tty-spinner', '~> 0.9')
  spec.add_development_dependency('bundler', '>= 1.14')
  spec.add_development_dependency('rake', '>= 10.0')
  spec.add_development_dependency('rspec', '>= 3.0')
  spec.requirements << 'IBM Aspera ascp installed for the user'
end
