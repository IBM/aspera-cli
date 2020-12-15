##################################
# Documentation

DIR_TOP=../
include $(DIR_TOP)common.make
DIR_DOC=

# files generated to be included in README.md
INCL_USAGE=$(DIR_TMP)$(EXENAME)_usage.txt
INCL_COMMANDS=$(DIR_TMP)$(EXENAME)_commands.txt
INCL_ASESSION=$(DIR_TMP)asession_usage.txt
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

$(DIR_TOP)README.md: $(DIR_DOC)README.erb.md $(INCL_COMMANDS) $(INCL_USAGE) $(INCL_ASESSION)
	DIR_DOC=$(DIR_DOC) COMMANDS=$(INCL_COMMANDS) USAGE=$(INCL_USAGE) ASESSION=$(INCL_ASESSION) VERSION=`$(EXETESTB) -Cnone --version` TOOLNAME=$(EXENAME) erb $(DIR_DOC)README.erb.md > $(DIR_TOP)README.md

$(INCL_COMMANDS): $(DIR_TMP).exists $(TEST_MAKEFILE)
	sed -nEe 's/.*\$$\(EXE_MAN.?\)/$(EXENAME)/p' $(TEST_MAKEFILE)|sed -E -e 's/(")(url|api_key|username|password|access_key_id|secret_access_key|pass)(":")[^"]*(")/\1\2\3my_\2_here\4/g;s/--(secret|url|password|username)=[^ ]*/--\1=my_\1_here/g;s/\$$\((DIR_[^)]+)\)/\1\//g;s/\$$\(([^)]+)\)/\1/g;s/"'"'"'"/"/g;s/CF_([0-9A-Z_]*)/my_\1/g;s/\$$(\$$'"'"')/\1/;s/\$$(\$$)/\1/g'|sort -u > $(INCL_COMMANDS)
# generated help of tools depends on all sources, so regenerate always
.PHONY: $(INCL_USAGE)
$(INCL_USAGE): $(DIR_TMP).exists
	$(EXETESTB) -Cnone -h 2> $(INCL_USAGE) || true
.PHONY: $(INCL_ASESSION)
$(INCL_ASESSION): $(DIR_TMP).exists
	$(DIR_BIN)/asession -h 2> $(INCL_ASESSION) || true
clean::
	rm -f $(MANUAL_PDF) $(MANUAL_HTML) $(INCL_COMMANDS) $(INCL_USAGE) $(INCL_ASESSION)

