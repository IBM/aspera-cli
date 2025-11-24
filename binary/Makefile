##################################
# Single executable
DIR_TOP=../

include $(DIR_TOP)common.mak

CLI_EXEC_PATH=$(DIR_TMP)$(CLI_NAME).$(GEM_VERSION).$(CLI_ARCH)
all:: $(CLI_EXEC_PATH)
.PHONY: single
$(CLI_EXEC_PATH):
	./build_exec.rb $(GEM_VERSION)
clean::
	rm -f $(CLI_EXEC_PATH) nohup.out
