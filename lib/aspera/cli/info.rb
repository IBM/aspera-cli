# frozen_string_literal: true

module Aspera
  module Cli
    module Info
      # name of command line tool, also used as foldername where config is stored
      CMD_NAME = 'ascli'
      # name of the containing gem, same as in <gem name>.gemspec
      GEM_NAME = 'aspera-cli'
      DOC_URL  = "https://www.rubydoc.info/gems/#{GEM_NAME}"
      GEM_URL  = "https://rubygems.org/gems/#{GEM_NAME}"
      SRC_URL  = 'https://github.com/IBM/aspera-cli'
      # set this to warn in advance when minimum required ruby version will increase
      # see also required_ruby_version in gemspec file
      RUBY_FUTURE_MINIMUM_VERSION = '3.1'
    end
  end
end
