# -*- encoding: utf-8 -*-
# stub: vault 0.19.0 ruby lib

Gem::Specification.new do |s|
  s.name = "vault".freeze
  s.version = "0.19.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Seth Vargo".freeze]
  s.bindir = "exe".freeze
  s.date = "2025-12-04"
  s.description = "Vault is a Ruby API client for interacting with a Vault server.".freeze
  s.email = ["team-vault-devex@hashicorp.com".freeze]
  s.homepage = "https://github.com/hashicorp/vault-ruby".freeze
  s.licenses = ["MPL-2.0".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.1".freeze)
  s.rubygems_version = "3.5.16".freeze
  s.summary = "Vault is a Ruby API client for interacting with a Vault server.".freeze

  s.installed_by_version = "4.0.3".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<aws-sigv4>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<base64>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<connection_pool>.freeze, ["~> 2.4".freeze])
  s.add_runtime_dependency(%q<net-http-persistent>.freeze, ["~> 4.0".freeze, ">= 4.0.2".freeze])
  s.add_development_dependency(%q<bundler>.freeze, ["~> 2".freeze])
  s.add_development_dependency(%q<pry>.freeze, ["~> 0.13.1".freeze])
  s.add_development_dependency(%q<rake>.freeze, ["~> 12.0".freeze])
  s.add_development_dependency(%q<rspec>.freeze, ["~> 3.5".freeze])
  s.add_development_dependency(%q<yard>.freeze, ["~> 0.9.24".freeze])
  s.add_development_dependency(%q<webmock>.freeze, ["~> 3.8.3".freeze])
  s.add_development_dependency(%q<webrick>.freeze, ["~> 1.5".freeze])
end
