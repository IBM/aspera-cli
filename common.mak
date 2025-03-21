# must be first target
all::

DIR_PRIV=$(ASPERA_CLI_PRIVATE)/

# just the name of the command line tool as in bin folder
# (used for documentation and execution)
CLI_NAME=$(shell ruby -I $(DIR_LIB) -e 'require "aspera/cli/info";puts Aspera::Cli::Info::CMD_NAME')
CLI_ARCH=$(shell ruby -I $(DIR_LIB) -e 'require "aspera/environment";puts Aspera::Environment.architecture')

# define common variables to be used in other Makefile
# required: DIR_TOP (can be empty if cwd)
DIR_BIN=$(DIR_TOP)bin/
DIR_LIB=$(DIR_TOP)lib/
DIR_TMP=$(DIR_TOP)tmp/
DIR_TST=$(DIR_TOP)tests/
DIR_DOC=$(DIR_TOP)docs/

# path to CLI for execution (not using PATH)
CLI_PATH=$(DIR_BIN)$(CLI_NAME)
# create Makefile file with macros GEM_NAME and GEM_VERSION
NAME_VERSION=$(DIR_TMP)name_version.mak
$(NAME_VERSION): $(DIR_TMP).exists $(DIR_LIB)aspera/cli/info.rb $(DIR_LIB)aspera/cli/version.rb
	sed -n "s/.*GEM_NAME = '\([^']*\)'.*/GEM_NAME=\1/p" $(DIR_LIB)aspera/cli/info.rb > $@
	sed -n "s/.*'\([^']*\)'.*/GEM_VERSION=\1/p" $(DIR_LIB)aspera/cli/version.rb >> $@
include $(NAME_VERSION)
GEMSPEC=$(DIR_TOP)$(GEM_NAME).gemspec
PATH_GEMFILE=$(DIR_TOP)$(GEM_NAME)-$(GEM_VERSION).gem
# override GEM_VERSION with beta version
BETA_VERSION_FILE=$(DIR_TMP)beta_version
MAKE_BETA=GEM_VERSION=$$(cat $(BETA_VERSION_FILE)) make -e
$(BETA_VERSION_FILE):
	echo $(GEM_VERSION).$$(date +%Y%m%d%H%M) > $(BETA_VERSION_FILE)
# gem file is generated in top folder
clean::
	rm -f $(NAME_VERSION)
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
