
DIR_TOP=../../
include $(DIR_TOP)common.mak
DIR_MKDOC=
VENV_DIR=$(DIR_TMP).venv_mkdocs/
VENV_FLAG=$(VENV_DIR)bin/activate
$(VENV_FLAG):
	mkdir -p $(VENV_DIR)
	python3 -m venv $(VENV_DIR)
	source $(VENV_DIR)bin/activate &&\
    python3 -m pip install -r requirements.txt
all:: $(VENV_FLAG)
	mkdir -p $(DIR_MKDOC)docs
	cp $(DIR_TOP)README.md $(DIR_MKDOC)docs/index.md
	source $(VENV_DIR)bin/activate &&\
	mkdocs serve
clean::
	rm -rf $(DIR_MKDOC)docs
	rm -rf $(VENV_DIR)
