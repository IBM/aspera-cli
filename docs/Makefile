##################################
# Documentation

DIR_TOP=../
include $(DIR_TOP)common.mak
# "make" shall be executed inside the folder containing this makefile
DIR_DOC=

MANUAL_BASE=$(DIR_DOC)Manual
MANUAL_PDF=$(MANUAL_BASE).pdf
MANUAL_HTML=$(MANUAL_BASE).html

# main target to build doc
all:: $(DIR_TOP).gems_checked $(MANUAL_PDF) $(MANUAL_HTML) $(TMPL_CONF_FILE_PATH)

doc: all

# generate template configuration file for tests, remove own secrets
$(TMPL_CONF_FILE_PATH): $(TEST_CONF_FILE_PATH)
	ruby -I . -I $(DIR_LIB). -r doc_tools -e generate_generic_conf $(TEST_CONF_FILE_PATH) > $@
delgen::
	rm -f $(TMPL_CONF_FILE_PATH)

#wkhtmltopdf toc $(MANUAL_HTML) $@
# +pipe_tables
# Date in PDF header is either the last checked in date or today if file has been modified
$(MANUAL_PDF): $(DIR_TOP)README.md $(DIR_TMP).exists
	set -x &&\
	if test -z "$$(git status --porcelain $(DIR_TOP)README.md)";then ref="-r $$(git log -1 --pretty="format:%cd" --date=unix $(DIR_TOP)README.md)";fi &&\
	date=$$(date $$ref '+%Y/%m/%d') &&\
	pandoc \
		--standalone \
		--from=gfm \
		--to=pdf \
		--pdf-engine=xelatex \
		--toc \
		--number-sections \
		--shift-heading-level-by=-1 \
		--resource-path=. \
		--variable=include-before:'\newpage' \
		--variable=documentclass:report \
		--variable=date:$$date \
		--variable=author:'Laurent MARTIN' \
		--variable=mainfont:Arial \
		--variable=urlcolor:blue \
		--variable=geometry:margin=15mm \
		-o $@ \
		$(DIR_TOP)README.md
$(MANUAL_HTML): $(DIR_TOP)README.md
	pandoc --number-sections --shift-heading-level-by=-1 --resource-path=. --toc -o $@ $(DIR_TOP)README.md

# regenerate always, as it depends on sources (when a new option is added for example). instead do: make delgen doc
#.PHONY: $(DIR_TOP)README.md
DOC_FILES=$(DIR_DOC)README.erb.md $(EXETESTB) $(DIR_BIN)asession $(DIR_TST)Makefile $(GEMSPEC)
$(DIR_TOP)README.md: $(DOC_FILES) $(DIR_DOC)doc_tools.rb $(DIR_LIB)aspera/cli/info.rb $(DIR_LIB)aspera/cli/version.rb $(DIR_LIB)aspera/cli/manager.rb $(GEMSPEC)
	ruby -I . -I $(DIR_LIB). -r doc_tools -e generate_doc $(DOC_FILES) > $@

delgen::
	rm -f $(MANUAL_PDF) $(MANUAL_HTML) $(DIR_TOP)README.md

##################################
# UML Diagram : requires tools: graphviz and gem xumlidot
# on mac: `gem install xumlidot pry` and `brew install graphviz`
uml: $(DIR_DOC)uml.png
$(DIR_DOC)uml.png: $(DIR_TOP)common.mak
	xumlidot --dot --no-composition --usage $(DIR_LIB). > $(DIR_DOC)uml.dot
	dot -Tpng $(DIR_DOC)uml.dot > $(DIR_DOC)uml.png
	rm -f $(DIR_DOC)uml.dot
delgen::
	rm -f $(DIR_DOC)uml.dot
