##################################
# Documentation

DIR_TOP=../
include $(DIR_TOP)common.make
# "make" shall be executed inside the folder containing this makefile
DIR_DOC=

# files generated to be included in README.md
INCL_USAGE=$(DIR_TMP)$(EXENAME)_usage.txt
INCL_COMMANDS=$(DIR_TMP)$(EXENAME)_commands.txt
INCL_ASESSION=$(DIR_TMP)asession_usage.txt
INCL_TRSPEC=$(DIR_DOC)transfer_spec.html
# env var used in README.erb.md
export EXENAME GEMSPEC INCL_USAGE INCL_COMMANDS INCL_ASESSION INCL_TRSPEC

TMPL_TEST_CONF=$(DIR_DOC)$(TEST_CONF_FILE_BASE)
TMPL_SECRETS=$(DIR_DOC)$(SECRETS_FILE_NAME)

MANUAL_BASE=$(DIR_DOC)Manual_$(EXENAME)_$(GEMVERSION)
MANUAL_PDF=$(MANUAL_BASE).pdf
MANUAL_HTML=$(MANUAL_BASE).html

# main target to build doc
all:: $(MANUAL_PDF) $(TMPL_SECRETS) $(TMPL_TEST_CONF)

doc: all

# generate template configuration files, remove own secrets
$(TMPL_SECRETS): $(SECRETS_FILE_PATH)
	sed 's/=.*/=_value_here_/' < $(SECRETS_FILE_PATH) > $(TMPL_SECRETS)
$(TMPL_TEST_CONF): $(TEST_CONF_FILE_PATH)
	ruby -e 'require "yaml";n={};c=YAML.load_file("$(TEST_CONF_FILE_PATH)").each{|k,v| n[k]=["config","default"].include?(k)?v:v.keys.inject({}){|m,i|m[i]="your value here";m}};File.write("$(TMPL_TEST_CONF)",n.to_yaml)'

$(MANUAL_PDF): $(DIR_TOP)README.md
	pandoc --number-sections --resource-path=. --toc -o $(MANUAL_HTML) $(DIR_TOP)README.md
	wkhtmltopdf toc $(MANUAL_HTML) $(MANUAL_PDF)

$(DIR_TOP)README.md: $(DIR_DOC)README.erb.md $(DIR_DOC)transfer_spec.html $(INCL_COMMANDS) $(INCL_USAGE) $(INCL_ASESSION)
	erb -T - --encoding UTF-8:UTF-8 $(DIR_DOC)README.erb.md > $(DIR_TOP)README.md

$(INCL_COMMANDS): $(DIR_TMP).exists $(TEST_MAKEFILE)
	sed -nEe 's/.*\$$\(EXE_MAN.?\)/$(EXENAME)/p' $(TEST_MAKEFILE) > $(DIR_TMP)usg1.txt
	sed -i.bak -Ee 's/\$$\((DIR_[^)]+)\)/\1\//g' $(DIR_TMP)usg1.txt
	sed -i.bak -Ee 's/\$$\(([^)]+)\)/\1/g' $(DIR_TMP)usg1.txt
	sed -i.bak -Ee 's/CF_([0-9A-Z_]*)/MY_\1/g' $(DIR_TMP)usg1.txt
	sed -i.bak -Ee 's/\$$(\$$)/\1/g' $(DIR_TMP)usg1.txt
	sed -i.bak -Ee 's/"'"'"'"\$${([a-z_]+)}"'"'"'"/"my_\1"/g' $(DIR_TMP)usg1.txt
	sed -i.bak -Ee 's/="\$${([a-z_]+)}"/="my_\1"/g' $(DIR_TMP)usg1.txt
	sed -i.bak -Ee 's/\$$@/xyz/g' $(DIR_TMP)usg1.txt
	sed -i.bak -Ee 's/"'"'"'"/"/g' $(DIR_TMP)usg1.txt
	sed -i.bak -Ee 's/"'"'"'/"/g' $(DIR_TMP)usg1.txt
	sed -i.bak -Ee 's/'"'"'"/"/g' $(DIR_TMP)usg1.txt
	sort -u < $(DIR_TMP)usg1.txt > $(INCL_COMMANDS)
# generated help of tools depends on all sources, so regenerate always
.PHONY: $(INCL_USAGE)
$(INCL_USAGE): $(DIR_TMP).exists
	$(EXETESTB) -Cnone -h 2> $(INCL_USAGE) || true
.PHONY: $(INCL_ASESSION)
$(INCL_ASESSION): $(DIR_TMP).exists
	$(DIR_BIN)/asession -h 2> $(INCL_ASESSION) || true
clean::
	rm -f $(MANUAL_PDF) $(MANUAL_HTML) $(INCL_COMMANDS) $(INCL_USAGE) $(INCL_ASESSION)

