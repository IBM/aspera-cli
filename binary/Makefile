DIR_TOP=../

include $(DIR_TOP)common.mak

##################################
# Single executable
CLI_EXEC_NAME=$(CLI_NAME).$(GEM_VERSION).$(CLI_ARCH)
CLI_EXECUTABLE=$(DIR_TMP)$(CLI_EXEC_NAME)
EXE_BUILDER=./build_exec
OPT_GEMS=$(shell $(DIR_DOC)get_group.rb $(DIR_TOP)Gemfile optional)
all:: $(CLI_EXECUTABLE)
.PHONY: single
$(CLI_EXECUTABLE):
	TMPDIR=$(DIR_TMP) $(EXE_BUILDER) $(CLI_EXECUTABLE) $(CLI_NAME) $(GEM_NAME):$(GEM_VERSION) $(OPT_GEMS)
	mv $(DIR_TMP)tebako-root/$(CLI_EXEC_NAME) $(CLI_EXECUTABLE)
clean::
	rm -f $(CLI_EXECUTABLE) nohup.out
