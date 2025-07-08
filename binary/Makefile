DIR_TOP=../

include $(DIR_TOP)common.mak

##################################
# Single executable
CLI_EXEC_NAME=$(CLI_NAME).$(GEM_VERSION).$(CLI_ARCH)
CLI_EXECUTABLE=$(DIR_TMP)$(CLI_EXEC_NAME)
EXE_BUILDER=./build_exec
all: $(CLI_EXECUTABLE)
.PHONY: single
$(CLI_EXECUTABLE):
	$(EXE_BUILDER) $(CLI_EXECUTABLE) $(CLI_PATH) $(GEM_NAME) $(GEM_VERSION) $(DIR_TMP)
	mv $(DIR_TMP)tebako-root/$(CLI_EXEC_NAME) $(CLI_EXECUTABLE)
clean::
	rm -f $(CLI_EXECUTABLE) nohup.out
