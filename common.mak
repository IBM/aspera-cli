# must be first target
.PHONY: all clean
all::

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
CLI_ARCH=$(shell ruby -I $(DIR_LIB) -e 'require "aspera/environment";print Aspera::Environment.instance.architecture')

# path to CLI for execution (not using PATH)
CLI_PATH=$(DIR_BIN)$(CLI_NAME)
GEMSPEC=$(DIR_TOP)$(GEM_NAME).gemspec
# gem file is generated in top folder
PATH_GEMFILE=$(DIR_TOP)$(GEM_NAME)-$(GEM_VERSION).gem
GEM_VERS_BETA=$(GEM_VERSION).$(shell date +%Y%m%d%H%M)
$(DIR_TMP).exists:
	mkdir -p $(DIR_TMP)
	@touch $@
clean::
	rm -fr $(DIR_TMP)
.PHONY: ensure_gems_installed gem_check_signing_key clean_gems_installed
# Ensure required ruby gems are installed
ensure_gems_installed: $(DIR_TOP).gems_checked
$(DIR_TOP).gems_checked: $(DIR_TOP)Gemfile
	cd $(DIR_TOP). && make install_dev_gems
	touch $@
clean_gems_installed:
	rm -f $(DIR_TOP).gems_checked $(DIR_TOP)Gemfile.lock
# check that the signing key is present
gem_check_signing_key:
	@echo "Checking: SIGNING_KEY"
	@if test -z '$(SIGNING_KEY)';then echo 'Error: Missing env var SIGNING_KEY' 1>&2;exit 1;fi
	@if test ! -e '$(SIGNING_KEY)';then echo 'Error: No such file: $(SIGNING_KEY)' 1>&2;exit 1;fi
clean:: clean_gems_installed
version:
	@echo $(GEM_VERSION)
repo:
	@echo $(DCK_REPO)
