##################################
# Documentation

DIR_TOP=../
include $(DIR_TOP)common.make
# "make" shall be executed inside the folder containing this makefile
DIR_DOC=

# files generated to be included in README.md
INCL_USAGE=$(DIR_TMP)$(EXENAME)_usage.txt
INCL_ASESSION=$(DIR_TMP)asession_usage.txt

# env var used in README.erb.md
export EXENAME GEMSPEC TEST_MAKEFILE TEST_CONF_FILE_PATH INCL_USAGE INCL_ASESSION

MANUAL_BASE=$(DIR_DOC)Manual_$(EXENAME)_$(GEMVERSION)
MANUAL_PDF=$(MANUAL_BASE).pdf
MANUAL_HTML=$(MANUAL_BASE).html

# main target to build doc
all:: $(MANUAL_PDF) $(TMPL_CONF_FILE_PATH)

doc: all

# generate template configuration file for tests, remove own secrets
$(TMPL_CONF_FILE_PATH): $(TEST_CONF_FILE_PATH)
	ruby -I . -I $(DIR_LIB) -r doc_tools -e generic_secrets > $@

$(MANUAL_PDF): $(DIR_TOP)README.md
	pandoc --number-sections --shift-heading-level-by=-1 --resource-path=. --toc -o $(MANUAL_HTML) $(DIR_TOP)README.md
	wkhtmltopdf toc $(MANUAL_HTML) $@

$(DIR_TOP)README.md: $(DIR_DOC)README.erb.md $(INCL_USAGE) $(INCL_ASESSION)
	RUBYLIB=$(DIR_LIB) erb -T - -U --encoding UTF-8:UTF-8 $(DIR_DOC)README.erb.md > $@

# generated help of tools depends on all sources, so regenerate always
.PHONY: $(INCL_USAGE)
$(INCL_USAGE): $(DIR_TMP).exists
	-$(EXETESTB) -Cnone -h 2> $@
$(INCL_ASESSION): $(DIR_TMP).exists $(DIR_BIN)/asession
	-$(DIR_BIN)/asession -h 2> $@
clean::
	rm -f $(MANUAL_PDF) $(MANUAL_HTML) $(INCL_USAGE) $(INCL_ASESSION)

##################################
# UML Diagram : requires tools: graphviz and gem xumlidot
# on mac: `gem install xumlidot pry` and `brew install graphviz`
uml: $(DIR_DOC)uml.png
$(DIR_DOC)uml.png:
	xumlidot --dot --no-composition $(DIR_LIB) > $(DIR_DOC)uml.dot
	dot -Tpng $(DIR_DOC)uml.dot > $(DIR_DOC)uml.png
clean::
	rm -f $(DIR_DOC)uml.dot $(DIR_DOC)uml.png

