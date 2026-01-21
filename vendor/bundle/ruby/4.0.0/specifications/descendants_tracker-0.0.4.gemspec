# -*- encoding: utf-8 -*-
# stub: descendants_tracker 0.0.4 ruby lib

Gem::Specification.new do |s|
  s.name = "descendants_tracker".freeze
  s.version = "0.0.4".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Dan Kubb".freeze, "Piotr Solnica".freeze, "Markus Schirp".freeze]
  s.date = "2014-03-27"
  s.description = "Module that adds descendant tracking to a class".freeze
  s.email = ["dan.kubb@gmail.com".freeze, "piotr.solnica@gmail.com".freeze, "mbj@schirp-dso.com".freeze]
  s.extra_rdoc_files = ["LICENSE".freeze, "README.md".freeze, "CONTRIBUTING.md".freeze, "TODO".freeze]
  s.files = ["CONTRIBUTING.md".freeze, "LICENSE".freeze, "README.md".freeze, "TODO".freeze]
  s.homepage = "https://github.com/dkubb/descendants_tracker".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "2.2.2".freeze
  s.summary = "Module that adds descendant tracking to a class".freeze

  s.installed_by_version = "4.0.3".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<thread_safe>.freeze, ["~> 0.3".freeze, ">= 0.3.1".freeze])
  s.add_development_dependency(%q<bundler>.freeze, ["~> 1.5".freeze, ">= 1.5.3".freeze])
end
