##################################
# Documentation
# cspell:ignore wkhtmltopdf fvextra pandoc xumlidot tlmgr -Tpng

DIR_TOP=../
include $(DIR_TOP)common.mak
# "make" shall be executed inside the folder containing this makefile
DIR_DOC=

MANUAL_BASE=$(DIR_DOC)Manual
MANUAL_PDF=$(MANUAL_BASE).pdf
MANUAL_HTML=$(MANUAL_BASE).html
DOC_TOOL=ruby -I $(DIR_DOC). -I $(DIR_LIB). -r doc_tools -e

# main target to build doc
all:: $(DIR_TOP).gems_checked $(TMPL_CONF_FILE_PATH) $(MANUAL_HTML) $(MANUAL_PDF)

doc: all

# generate template configuration file for tests, remove own secrets
$(TMPL_CONF_FILE_PATH): $(TEST_CONF_FILE_PATH) $(DIR_DOC)doc_tools.rb
	$(DOC_TOOL) generate_generic_conf $(TEST_CONF_FILE_PATH) > $@
clean_doc::
	rm -f $(TMPL_CONF_FILE_PATH)

#wkhtmltopdf toc $(MANUAL_HTML) $@
# +pipe_tables
# Date in PDF header is either the last checked in date or today if file has been modified
# sudo tlmgr install fvextra
$(MANUAL_PDF): $(DIR_TMP).exists $(DIR_TOP)README.md $(DIR_DOC)manual_pandoc_defaults.yaml $(DIR_DOC)manual_pandoc_metadata.yaml $(DIR_DOC)manual_include_in_header.tex $(DIR_DOC)manual_include_after_body.tex
	rm -f $@
	set -x &&\
		if test -z "$$(git status --porcelain $(DIR_TOP)README.md)";then ref="-r $$(git log -1 --pretty="format:%cd" --date=unix $(DIR_TOP)README.md)";fi &&\
		date=$$(date $$ref '+%Y/%m/%d') &&\
		RESOURCE_DIR=$(DIR_DOC). \
		pandoc \
			--defaults=$(DIR_DOC)manual_pandoc_defaults.yaml \
			--variable=date:$$date \
			--variable=subtitle:"$(CLI_NAME) $(GEM_VERSION)"\
			--output=$@\
			$(DIR_TOP)README.md

$(MANUAL_HTML): $(DIR_TOP)README.md
	pandoc \
		--toc \
		--number-sections \
		--shift-heading-level-by=-1 \
		--resource-path=$(DIR_DOC). \
		--output=$@ \
		$(DIR_TOP)README.md

# regenerate always, as it depends on sources (when a new option is added for example). instead do: make clean_doc doc
#.PHONY: $(DIR_TOP)README.md
DOC_FILES=$(DIR_DOC)README.erb.md $(CLI_PATH) $(DIR_BIN)asession $(DIR_TST)Makefile $(GEMSPEC)
$(DIR_TOP)README.md: $(DOC_FILES) $(DIR_DOC)doc_tools.rb $(DIR_LIB)aspera/cli/info.rb $(DIR_LIB)aspera/cli/version.rb $(DIR_LIB)aspera/cli/manager.rb $(DIR_LIB)aspera/fasp/parameters.yaml $(GEMSPEC)
	$(DOC_TOOL) generate_doc $(DOC_FILES) > $@
	! grep '^#.*: [a-z]' README.erb.md

clean_doc::
	rm -f $(MANUAL_PDF) $(MANUAL_HTML) $(DIR_TOP)README.md

##################################
# UML Diagram : requires tools: graphviz and gem xumlidot
# on mac: `gem install xumlidot pry` and `brew install graphviz`
uml: $(DIR_DOC)uml.png
$(DIR_DOC)uml.png: $(DIR_TOP)common.mak
	xumlidot --dot --no-composition --usage $(DIR_LIB). > $(DIR_DOC)uml.dot
	dot -Tpng $(DIR_DOC)uml.dot > $(DIR_DOC)uml.png
	rm -f $(DIR_DOC)uml.dot
clean_doc::
	rm -f $(DIR_DOC)uml.dot
