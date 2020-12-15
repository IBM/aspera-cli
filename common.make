# define common variables to be used in other Makefiles
# required: DIR_TOP (can be empty if cwd)
DIR_BIN=$(DIR_TOP)bin/
DIR_LIB=$(DIR_TOP)lib/
DIR_TMP=$(DIR_TOP)tmp/
DIR_PRIV=$(DIR_TOP)local/
DIR_TST=$(DIR_TOP)tests/
DIR_DOC=$(DIR_TOP)docs/

# makefile for integration tests, used for doc generation
TEST_MAKEFILE=$(DIR_TST)Makefile

# contains locations and credentials for test servers
SECRETS_FILE_NAME=secrets.make
SECRETS_FILE_PATH=$(DIR_PRIV)$(SECRETS_FILE_NAME)

# configuration file used for tests, create your own from template in "docs"
TEST_CONF_FILE_BASE=test_env.conf
TEST_CONF_FILE_PATH=$(DIR_PRIV)$(TEST_CONF_FILE_BASE)

# just the name of the command line tool as in bin folder
# (used for documentation and execution)
EXENAME=ascli

# how tool is called without argument
# use only if another config file is used
# else use EXE_MAN or EXE_NOMAN
EXETESTB=$(DIR_BIN)$(EXENAME)

GEMVERSION=$(shell $(EXETESTB) -Cnone --version)

all::

clean::
	rm -fr $(DIR_TMP)
	mkdir -p $(DIR_TMP)

$(DIR_TMP).exists:
	mkdir -p $(DIR_TMP)
	@touch $(DIR_TMP).exists
