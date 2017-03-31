# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'asperalm/version'

Gem::Specification.new do |spec|
  spec.name          = "asperalm"
  spec.version       = Asperalm::VERSION
  spec.authors       = ["Laurent Martin"]
  spec.email         = ["laurent@asperasoft.com"]
  spec.summary       = "Sample command line for Aspera Server products: Aspera Files, Faspex, Shares, Node, Console"
  spec.description   = "A sample CLI for Aspera products."
  spec.homepage      = "http://www.asperasoft.com"
  spec.license       = 'IPL-1.0'

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "https://rubygems.org"
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.add_runtime_dependency 'xml-simple', '~> 1.1', '>= 1.1.5'
  spec.add_runtime_dependency 'jwt', '~> 1.5', '>= 1.5.6'
  spec.add_runtime_dependency 'ruby-progressbar', '~> 1.0', '>= 1.0.0'
  spec.add_dependency('text-table', '~> 1.2.4')
  spec.add_development_dependency "bundler", "~> 1.14"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
