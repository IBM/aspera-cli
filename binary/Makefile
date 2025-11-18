##################################
# Single executable
DIR_TOP=../

include $(DIR_TOP)common.mak

EXE_BUILDER=./build_exec
CLI_EXEC_NAME=$(CLI_NAME).$(GEM_VERSION).$(CLI_ARCH)
CLI_EXEC_PATH=$(DIR_TMP)$(CLI_EXEC_NAME)
OPT_GEMS=$(shell $(DOC_TOOL) gems_in_group $(DIR_TOP)Gemfile optional)
all:: $(CLI_EXEC_PATH)
.PHONY: single
$(CLI_EXEC_PATH):
	$(EXE_BUILDER) $(CLI_EXEC_PATH) $(CLI_NAME) $(GEM_NAME):$(GEM_VERSION) $(OPT_GEMS)
clean::
	rm -f $(CLI_EXEC_PATH) nohup.out
