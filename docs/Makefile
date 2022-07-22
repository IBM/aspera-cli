##################################
# Documentation

DIR_TOP=../
include $(DIR_TOP)common.make
# "make" shall be executed inside the folder containing this makefile
DIR_DOC=

MANUAL_BASE=$(DIR_DOC)Manual_$(EXENAME)_$(GEMVERSION)
MANUAL_PDF=$(MANUAL_BASE).pdf
MANUAL_HTML=$(MANUAL_BASE).html

# main target to build doc
all:: $(MANUAL_PDF) $(TMPL_CONF_FILE_PATH)

doc: all

# generate template configuration file for tests, remove own secrets
$(TMPL_CONF_FILE_PATH): $(TEST_CONF_FILE_PATH)
	ruby -I . -I $(DIR_LIB). -r doc_tools -e generate_generic_conf $(TEST_CONF_FILE_PATH) > $@

$(MANUAL_PDF): $(DIR_TOP)README.md
	pandoc --number-sections --shift-heading-level-by=-1 --resource-path=. --toc -o $(MANUAL_HTML) $(DIR_TOP)README.md
	wkhtmltopdf toc $(MANUAL_HTML) $@

# regenerate always, as it depends on sources
.PHONY: $(DIR_TOP)README.md
$(DIR_TOP)README.md: $(DIR_DOC)README.erb.md $(DIR_DOC)doc_tools.rb
	ruby -I . -I $(DIR_LIB). -r doc_tools -e generate_doc $(DIR_DOC)README.erb.md $(EXETESTB) $(DIR_BIN)asession $(DIR_TST)Makefile $(GEMSPEC) > $@

clean::
	rm -f $(MANUAL_PDF) $(MANUAL_HTML)

##################################
# UML Diagram : requires tools: graphviz and gem xumlidot
# on mac: `gem install xumlidot pry` and `brew install graphviz`
uml: $(DIR_DOC)uml.png
$(DIR_DOC)uml.png:
	xumlidot --dot --no-composition $(DIR_LIB). > $(DIR_DOC)uml.dot
	dot -Tpng $(DIR_DOC)uml.dot > $(DIR_DOC)uml.png
	rm -f $(DIR_DOC)uml.dot
clean::
	rm -f $(DIR_DOC)uml.dot
