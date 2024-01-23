# must be first target
all::

# configuration file used for tests, template is generated in "docs"
# this is the actual conf file, create your own from template located in "docs"
ifndef ASPERA_CLI_TEST_CONF_FILE
$(error ASPERA_CLI_TEST_CONF_FILE is not set. Refer to CONTRIBUTING.md.)
endif
DIR_PRIV=$(ASPERA_CLI_PRIVATE)/

# just the name of the command line tool as in bin folder
# (used for documentation and execution)
# must be same value as Aspera::Cli::PROGRAM_NAME
CLI_NAME=ascli

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
# remove ascli and asession from rvm bin folder, so that the one from dev is used
$(DIR_TOP).gems_checked: $(DIR_TOP)Gemfile
	cd $(DIR_TOP). && bundle config set --local with development
	cd $(DIR_TOP). && bundle install
	rm -f $$HOME/.rvm/*/*/bin/ascli
	rm -f $$HOME/.rvm/*/*/bin/asession
	touch $@
clean:: clean_gems_installed
clean_gems_installed:
	rm -f $(DIR_TOP).gems_checked $(DIR_TOP)Gemfile.lock
