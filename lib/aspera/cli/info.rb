# frozen_string_literal: true
module Aspera
  module Cli
    # name of command line tool, also used as foldername where config is stored
    PROGRAM_NAME = 'ascli'
    # name of the containing gem, same as in <gem name>.gemspec
    GEM_NAME = 'aspera-cli'
    DOC_URL  = "https://www.rubydoc.info/gems/#{GEM_NAME}"
    GEM_URL  = "https://rubygems.org/gems/#{GEM_NAME}"
    SRC_URL  = 'https://github.com/IBM/aspera-cli'
    RUBY_CURRENT_MINIMUM_VERSION='2.4'
    # set this to warn in advance when minimum required ruby version will increase
    # for example currently minimum version is 2.4 in gemspec, but future minimum will be 2.5
    # set to currenmt minimum if there is no deprecation
    RUBY_FUTURE_MINIMUM_VERSION='2.5'
  end
end
