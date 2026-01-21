# -*- encoding: utf-8 -*-
# stub: symmetric-encryption 4.6.0 ruby lib

Gem::Specification.new do |s|
  s.name = "symmetric-encryption".freeze
  s.version = "4.6.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Reid Morrison".freeze]
  s.date = "2022-11-06"
  s.executables = ["symmetric-encryption".freeze]
  s.files = ["bin/symmetric-encryption".freeze]
  s.homepage = "https://encryption.rocketjob.io".freeze
  s.licenses = ["Apache-2.0".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.3".freeze)
  s.rubygems_version = "3.3.7".freeze
  s.summary = "Encrypt ActiveRecord and Mongoid attributes, files and passwords in configuration files.".freeze

  s.installed_by_version = "4.0.3".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<coercible>.freeze, ["~> 1.0".freeze])
end
