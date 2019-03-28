# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'asperalm/cli/main'

Gem::Specification.new do |spec|
  spec.name          = 'asperalm'
  spec.version       = Asperalm::Cli::Main::gem_version
  spec.authors       = ['Laurent Martin']
  spec.email         = ['laurent.martin.aspera@fr.ibm.com']
  spec.summary       = 'gem and command line tool for Aspera Server products: Aspera Files, Faspex, Shares, Node, Console, Orchestrator, Server, ATS'
  spec.description   = 'A powerful transfer gem and CLI for IBM Aspera products.'
  spec.homepage      = 'http://www.asperasoft.com'
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
  spec.required_ruby_version = '~> 2.0'
  spec.add_runtime_dependency('xml-simple', '~> 1.1', '>= 1.1.5')
  spec.add_runtime_dependency('jwt', '~> 1.5', '>= 1.5.6')
  spec.add_runtime_dependency('ruby-progressbar', '~> 1.0', '>= 1.0.0')
  spec.add_runtime_dependency('net-ssh', '~> 4.0', '>= 4.0.0')
  spec.add_runtime_dependency('mimemagic', '~> 0.3', '>= 0.3')
  spec.add_runtime_dependency('execjs', '~> 2.0', '>= 2.0')
  spec.add_runtime_dependency('text-table', '~> 1.2', '>= 1.2.4')
  spec.add_development_dependency('bundler', '~> 1.0', '> 1.14')
  spec.add_development_dependency('rake', '~> 10.0', '> 10.0')
  spec.add_development_dependency('rspec', '~> 3.0', '> 3.0')
  spec.requirements << 'Aspera connect client installed for the user'
end
