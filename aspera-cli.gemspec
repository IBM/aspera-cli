require_relative 'lib/aspera/cli/version'

# expected extension of gemspec file
GEMSPEC_EXT='.gemspec'.freeze
Gem::Specification.new do |spec|
  # get location of this file (shall be in project root)
  gemspec_file=File.expand_path(__FILE__)
  raise "Error: this file extension must be '#{GEMSPEC_EXT}'" unless gemspec_file.end_with?(GEMSPEC_EXT)
  # the base name of this file shall be the gem name
  spec.name          = File.basename(gemspec_file,GEMSPEC_EXT).downcase
  spec.version       = Aspera::Cli::VERSION
  spec.authors       = ['Laurent Martin']
  spec.email         = ['laurent.martin.aspera@fr.ibm.com']
  spec.summary       = 'Execute actions using command line on IBM Aspera Server products: Aspera on Cloud, Faspex, Shares, Node, Console, Orchestrator, Transfer Server'
  spec.description   = 'Command line interface for IBM Aspera products'
  spec.homepage      = 'https://github.com/IBM/aspera-cli'
  spec.license       = 'Apache-2.0'
  spec.requirements << 'Read the manual for any requirement'
  raise 'RubyGems 2.0 or newer is required' unless spec.respond_to?(:metadata)
  spec.metadata['allowed_push_host'] = 'https://rubygems.org' # push only to rubygems.org
  spec.metadata['homepage_uri']      = spec.homepage
  spec.metadata['source_code_uri']   = spec.homepage
  spec.metadata['changelog_uri']     = spec.homepage
  spec.metadata['rubygems_uri']      = "https://rubygems.org/gems/#{spec.name}"
  spec.metadata['documentation_uri'] = "https://www.rubydoc.info/gems/#{spec.name}"
  spec.require_paths = ['lib']
  spec.bindir        = 'bin'
  # list git files from specified location in root folder of project (this gemspec is in project root folder)
  spec.files=Dir.chdir(File.dirname(gemspec_file)){%x(git ls-files -z lib bin examples README.md docs/*.conf).split("\x0")}
  # remove specific files from list
  spec.files.reject!{|f|['transfer_spec.erb.rb'].include?(File.basename(f))}
  spec.executables = spec.files.grep(%r{^#{spec.bindir}}){|f|File.basename(f)} # must be after spec.bindir and spec.files
  spec.required_ruby_version = '> 2.4'
  spec.add_runtime_dependency('execjs', '~> 2.0')
  spec.add_runtime_dependency('grpc', '~> 1.0')
  spec.add_runtime_dependency('jwt', '~> 2.0')
  spec.add_runtime_dependency('mimemagic', '~> 0.3')
  spec.add_runtime_dependency('net-ssh', '~> 6.0')
  spec.add_runtime_dependency('ruby-progressbar', '~> 1.0')
  spec.add_runtime_dependency('rubyzip', '~> 2.0')
  spec.add_runtime_dependency('security', '~> 0.0')
  spec.add_runtime_dependency('terminal-table', '~> 1.8')
  spec.add_runtime_dependency('tty-spinner', '~> 0.9')
  spec.add_runtime_dependency('webrick', '~> 1.7')
  spec.add_runtime_dependency('websocket', '~> 1.2')
  spec.add_runtime_dependency('websocket-client-simple', '~> 0.3')
  spec.add_runtime_dependency('xml-simple', '~> 1.0')
  spec.add_development_dependency('bundler', '~> 2.0')
  spec.add_development_dependency('rake', '~> 13.0')
  spec.add_development_dependency('rspec', '~> 3.0')
  spec.add_development_dependency('rubocop', '~> 1.0')
end
