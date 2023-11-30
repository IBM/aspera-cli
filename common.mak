# must be first target
all::

# just the name of the command line tool as in bin folder
# (used for documentation and execution)
# must be same value as Aspera::Cli::PROGRAM_NAME
CLI_NAME=ascli

# define common variables to be used in other Makefile
# required: DIR_TOP (can be empty if cwd)
DIR_BIN=$(DIR_TOP)bin/
DIR_LIB=$(DIR_TOP)lib/
DIR_TMP=$(DIR_TOP)tmp/
DIR_PRIV=$(DIR_TOP)local/
DIR_TST=$(DIR_TOP)tests/
DIR_DOC=$(DIR_TOP)docs/

# configuration file used for tests, template is generated in "docs"
TEST_CONF_FILE_BASE=test_env.conf

# this is the actual conf file, create your own from template located in "docs"
TEST_CONF_FILE_PATH=$(DIR_PRIV)$(TEST_CONF_FILE_BASE)
TMPL_CONF_FILE_PATH=$(DIR_DOC)$(TEST_CONF_FILE_BASE)

# path to CLI for execution (not using PATH)
CLI_PATH=$(DIR_BIN)$(CLI_NAME)

GEMSPEC=$(DIR_TOP)$(GEM_NAME).gemspec

# create Makefile file with macros GEM_NAME and GEM_VERSION
NAME_VERSION=$(DIR_TMP)name_version.mak
$(NAME_VERSION): $(DIR_TMP).exists $(DIR_LIB)aspera/cli/info.rb $(DIR_LIB)aspera/cli/version.rb
	sed -n "s/.*GEM_NAME = '\([^']*\)'.*/GEM_NAME=\1/p" $(DIR_LIB)aspera/cli/info.rb > $@
	sed -n "s/.*'\([^']*\)'.*/GEM_VERSION=\1/p" $(DIR_LIB)aspera/cli/version.rb >> $@
include $(NAME_VERSION)
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
$(TEST_CONF_FILE_PATH):
	mkdir -p $(DIR_PRIV)
	cp $(TMPL_CONF_FILE_PATH) $(TEST_CONF_FILE_PATH)
	@echo "\033[0;32mAn empty configuration file is created:\n$$(realpath $(TEST_CONF_FILE_PATH))\nIt needs to be filled to run tests.\033[0;39m"
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
