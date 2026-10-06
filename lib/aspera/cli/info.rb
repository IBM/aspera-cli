# frozen_string_literal: true

module Aspera
  module Cli
    module Info
      # Name of command line tool, also used as foldername where config is stored
      CMD_NAME = 'ascli'
      # Name of the containing gem, same as in <gem name>.gemspec
      GEM_NAME = 'aspera-cli'
      DOC_URL  = 'https://ibm.biz/ascli-doc'
      RUBYDOC_URL = "https://www.rubydoc.info/gems/#{GEM_NAME}"
      GEM_URL  = "https://rubygems.org/gems/#{GEM_NAME}"
      SRC_URL  = 'https://github.com/IBM/aspera-cli'
      CONTAINER = 'docker.io/martinlaurent/ascli'
      # Set this to warn in advance when minimum required ruby version will increase
      # See also required_ruby_version in gemspec file
      RUBY_FUTURE_MINIMUM_VERSION = '3.2'
      # Version with which this version of CLI was tested
      SDK_VERSION = '1.1.9'
      # Ruby version with which this version of CLI was tested, packaged in container image and portable packages
      RUBY_TESTED_VERSION = '4.0.7'
      # Suffix of the RubyInstaller release of `RUBY_TESTED_VERSION`, packaged in the Windows zip
      # (release tag: `RubyInstaller-<Ruby version><suffix>`)
      # https://github.com/oneclick/rubyinstaller2/releases
      WINDOWS_RUBY_INSTALLER_EXT = '-1'
    end
  end
end
