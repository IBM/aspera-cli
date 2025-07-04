##################################
# Documentation
# cspell:ignore wkhtmltopdf fvextra pandoc xumlidot tlmgr -Tpng

DIR_TOP=../
include $(DIR_TOP)common.mak
# "make" shall be executed inside the folder containing this makefile
DIR_DOC=
include $(DIR_DOC)pandoc/pandoc.mak

MANUAL_BASE=$(DIR_DOC)Manual
MANUAL_PDF=$(MANUAL_BASE).pdf
MANUAL_HTML=$(MANUAL_BASE).html
DOC_TOOL=ruby -I $(DIR_DOC). -I $(DIR_LIB). -r doc_tools -e
TMPL_CONF_FILE_PATH=$(DIR_DOC)test_env.conf
TSPEC_JSON_SCHEMA=$(DIR_DOC)spec.schema.json

# main target to build doc
all:: $(DIR_TOP).gems_checked $(TMPL_CONF_FILE_PATH) $(TSPEC_JSON_SCHEMA) $(MANUAL_HTML) $(MANUAL_PDF)

doc: all

# generate template configuration file for tests, remove own secrets
$(TMPL_CONF_FILE_PATH): $(DIR_DOC)doc_tools.rb
	$(DOC_TOOL) generate_generic_conf > $@
clean_doc::
	rm -f $(TMPL_CONF_FILE_PATH)

#wkhtmltopdf toc $(MANUAL_HTML) $@
# +pipe_tables
# Date in PDF header is either the last checked in date or today if file has been modified
# sudo tlmgr install fvextra
$(eval $(call markdown_to_pdf,$(DIR_TOP)README.md,$(MANUAL_PDF)))

$(TSPEC_JSON_SCHEMA): $(DIR_LIB)aspera/transfer/spec.schema.yaml
	$(CLI_PATH) config ascp schema --format=jsonpp --output=$@
clean_doc::
	rm -f $(TSPEC_JSON_SCHEMA)

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
DOC_FILES=$(DIR_DOC)README.erb.md $(CLI_PATH) $(DIR_BIN)asession $(DIR_TST)Makefile $(GEMSPEC) $(DIR_TOP)Gemfile
$(DIR_TOP)README.md: $(DOC_FILES) $(DIR_DOC)doc_tools.rb $(DIR_LIB)aspera/cli/info.rb $(DIR_LIB)aspera/cli/version.rb $(DIR_LIB)aspera/cli/manager.rb $(DIR_LIB)aspera/transfer/spec.schema.yaml $(GEMSPEC)
	$(DOC_TOOL) generate_doc $(DOC_FILES) > $@
	! grep '^#.*: [a-z]' README.erb.md

clean_doc::
	rm -f $(MANUAL_PDF) $(MANUAL_HTML) $(DIR_TOP)README.md

##################################
# UML Diagram : requires tools: graphviz and gem xumlidot
# on mac: `gem install xumlidot pry` and `brew install graphviz`
# to force another path: XUMLIDOT=.../xumlidot make -e uml
XUMLIDOT=xumlidot
DOT=dot
uml: $(DIR_DOC)uml.png
$(DIR_DOC)uml.png: $(DIR_TOP)common.mak check_tools
	$(XUMLIDOT) --dot --no-composition --usage $(DIR_LIB). > $(DIR_DOC)uml.dot
	$(DOT) -Tpng $(DIR_DOC)uml.dot > $(DIR_DOC)uml.png
	rm -f $(DIR_DOC)uml.dot
clean_doc::
	rm -f $(DIR_DOC)uml.dot
clean_uml: clean_doc
	rm -f $(DIR_DOC)uml.png
check_tools:
	$(XUMLIDOT) >/dev/null 2>&1;\
	if test $$? -eq 127;then echo "xumlidot not found, please install it with 'gem install xumlidot'";exit 1;fi
show_erb:
	sed -nEe 's/.*<%=([^>(.%]+).*/\1/p' < $(DIR_DOC)README.erb.md|sort -u
