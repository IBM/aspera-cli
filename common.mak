# must be first target
all::

DIR_PRIV=$(ASPERA_CLI_PRIVATE)/

# define common variables to be used in other Makefile
# required: DIR_TOP (can be empty if cwd)
DIR_BIN=$(DIR_TOP)bin/
DIR_LIB=$(DIR_TOP)lib/
DIR_TMP=$(DIR_TOP)tmp/
DIR_TST=$(DIR_TOP)tests/
DIR_DOC=$(DIR_TOP)docs/

GEM_VERSION=$(shell ruby -I $(DIR_LIB) -e 'require "aspera/cli/version";print Aspera::Cli::VERSION')
GEM_NAME=$(shell ruby -I $(DIR_LIB) -e 'require "aspera/cli/info";print Aspera::Cli::Info::GEM_NAME')
DCK_REPO=$(shell ruby -I $(DIR_LIB) -e 'require "aspera/cli/info";print Aspera::Cli::Info::CONTAINER')
CLI_NAME=$(shell ruby -I $(DIR_LIB) -e 'require "aspera/cli/info";print Aspera::Cli::Info::CMD_NAME')
CLI_ARCH=$(shell ruby -I $(DIR_LIB) -e 'require "aspera/environment";print Aspera::Environment.architecture')

# path to CLI for execution (not using PATH)
CLI_PATH=$(DIR_BIN)$(CLI_NAME)
GEMSPEC=$(DIR_TOP)$(GEM_NAME).gemspec
# gem file is generated in top folder
PATH_GEMFILE=$(DIR_TOP)$(GEM_NAME)-$(GEM_VERSION).gem
GEM_VERS_BETA=$(GEM_VERSION).$(shell date +%Y%m%d%H%M)
$(DIR_TMP).exists:
	mkdir -p $(DIR_TMP)
	@touch $@
# Ensure required ruby gems are installed
# remove ascli and asession from riby gem bin folder, so that the one from dev is used
$(DIR_TOP).gems_checked: $(DIR_TOP)Gemfile
	gem install bundler
	cd $(DIR_TOP). && bundle config set --local with development && bundle install
	rm -f $$(gem env gemdir)/bin/as{cli,ession}
	touch $@
clean:: clean_gems_installed
clean_gems_installed:
	rm -f $(DIR_TOP).gems_checked $(DIR_TOP)Gemfile.lock
