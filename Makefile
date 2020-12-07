# This makefile expects being run with bash or zsh shell

# DIR_TOP: main folder of this project
# use "." automatic detection does not work, in this case "make" with main folder as current working directory
DIR_TOP=$(shell dirname "$(realpath $(firstword $(MAKEFILE_LIST)))")
DIR_BIN=$(DIR_TOP)/bin
DIR_LIB=$(DIR_TOP)/lib
DIR_TMP=$(DIR_TOP)/tmp
DIR_DOC=$(DIR_TOP)/docs
DIR_PRIV=$(DIR_TOP)/local

# just the name of the command line tool (used for documentation and execution)
EXENAME=ascli
# how tool is called, dont use directly in makefile, use EXE_MAN or EXE_NOMAN
EXETESTB=$(DIR_BIN)/$(EXENAME)
# this config file contains credentials of platforms used for tests
# "EXE_MAN" is used to generate sample commands in documentation
EXE_MAN=$(EXETESTB) --warnings --config-file=$(DIR_PRIV)/test.ascli.conf
# invoked like this: do not go to manual samples
EXE_NOMAN=$(EXE_MAN)

GEMNAME=aspera-cli
GEMVERSION=$(shell $(EXE_NOMAN) --version)
PATH_GEMFILE=$(DIR_TOP)/$(GEMNAME)-$(GEMVERSION).gem

GIT_TAG_VERSION_PREFIX='v_'
GIT_TAG_CURRENT=$(GIT_TAG_VERSION_PREFIX)$(GEMVERSION)

# flag files for integration tests generated here
T=$(DIR_TOP)/t

# defazult download folder for Connect Client
DIR_CONNECT_DOWNLOAD=$(HOME)/Desktop

LATEST_TAG=$(shell git describe --tags --abbrev=0)

# files generated to be included in README.md
INCL_USAGE=$(DIR_TMP)/$(EXENAME)_usage.txt
INCL_COMMANDS=$(DIR_TMP)/$(EXENAME)_commands.txt
INCL_ASESSION=$(DIR_TMP)/asession_usage.txt

PKG_TEST_TITLE=$(shell date)

# contains secrets
include $(DIR_PRIV)/secrets.make

all:: gem

clean::
	rm -f $(GEMNAME)-*.gem *.log token.* preview.png aspera_bypass_*.pem sample_file.txt
	rm -f README.pdf README.html $(INCL_COMMANDS) $(INCL_USAGE) $(INCL_ASESSION) $(TEST_CONFIG)
	rm -fr tmp_* contents $(T) "PKG - "*
	rm -f 200KB* *AsperaConnect-ML* sample.conf* .DS_Store 10M.dat
	mkdir $(T)
	gem uninstall -a -x $(GEMNAME)
cleanupgems:
	gem uninstall -a -x $(gem list|cut -f 1 -d' '|egrep -v 'rdoc|psych|rake|openssl|json|io-console|bigdecimal')

changes:
	@echo "Changes since $(LATEST_TAG)"
	git log $(LATEST_TAG)..HEAD --oneline
diff: changes


##################################
# Documentation

doc: README.pdf docs/secrets.make docs/test.ascli.conf

# generate template configuration files, remove own secrets
docs/secrets.make: $(DIR_PRIV)/secrets.make
	sed 's/=.*/=_value_here_/' < $(DIR_PRIV)/secrets.make > docs/secrets.make
docs/test.ascli.conf: $(DIR_PRIV)/test.ascli.conf
	ruby -e 'require "yaml";n={};c=YAML.load_file("$(DIR_PRIV)/test.ascli.conf").each{|k,v| n[k]=["config","default"].include?(k)?v:v.keys.inject({}){|m,i|m[i]="your value here";m}};File.write("docs/test.ascli.conf",n.to_yaml)'

README.pdf: README.md
	pandoc --number-sections --resource-path=. --toc -o README.html README.md
	wkhtmltopdf toc README.html README.pdf

README.md: $(DIR_DOC)/README.erb.md $(INCL_COMMANDS) $(INCL_USAGE) $(INCL_ASESSION)
	COMMANDS=$(INCL_COMMANDS) USAGE=$(INCL_USAGE) ASESSION=$(INCL_ASESSION) VERSION=`$(EXE_NOMAN) --version` TOOLNAME=$(EXENAME) erb $(DIR_DOC)/README.erb.md > README.md

$(INCL_COMMANDS): Makefile
	sed -nEe 's/.*\$$\(EXE_MAN.?\)/$(EXENAME)/p' Makefile|sed -E -e 's/(")(url|api_key|username|password|access_key_id|secret_access_key|pass)(":")[^"]*(")/\1\2\3my_\2_here\4/g;s/--(secret|url|password|username)=[^ ]*/--\1=my_\1_here/g;s/\$$\(([^)]+)\)/\1/g;s/"'"'"'"/"/g;s/CF_([0-9A-Z_]*)/my_\1/g;s/\$$(\$$'"'"')/\1/;s/\$$(\$$)/\1/g'|sort -u > $(INCL_COMMANDS)
incl:
	sed -nEe 's/.*\$$\(EXE_MAN.?\)/$(EXENAME)/p' Makefile|sed -E -e 's/(")(url|api_key|username|password|access_key_id|secret_access_key|pass)(":")[^"]*(")/\1\2\3my_\2_here\4/g;s/--(secret|url|password|username)=[^ ]*/--\1=my_\1_here/g;s/\$$\(([^)]+)\)/\1/g;s/"'"'"'"/"/g;s/CF_([0-9A-Z_]*)/my_\1/g;s/\$$(\$$'"'"')/\1/;s/\$$(\$$)/\1/g'|sort -u 
# generated help of tools depends on all sources, so regenerate always
.PHONY: $(INCL_USAGE)
$(INCL_USAGE):
	$(EXE_NOMAN) -Cnone -h 2> $(INCL_USAGE) || true
.PHONY: $(INCL_ASESSION)
$(INCL_ASESSION):
	$(DIR_BIN)/asession -h 2> $(INCL_ASESSION) || true

# gem file is generated in top folder
$(PATH_GEMFILE): README.md
	gem build $(GEMNAME)

gem: $(PATH_GEMFILE)

install: $(PATH_GEMFILE)
	gem install $(PATH_GEMFILE)

yank:
	gem yank aspera -v $(GEMVERSION)

dotag:
	git tag -a $(GIT_TAG_CURRENT) -m "gem version $(GEMVERSION) pushed"

deltag:
	git tag --delete $(GIT_TAG_CURRENT)

gempush: all dotag
	gem push $(PATH_GEMFILE)

commit:
	git commit -a
# eq to: git push origin master
push:
	git push

clean::
	rm -fr $(DIR_TMP)
$(DIR_TMP)/.exists:
	mkdir -p $(DIR_TMP)
	@touch $(DIR_TMP)/.exists

$(T)/unit:
	@echo $@
	bundle exec rake spec
	@touch $@
$(T)/sh1:
	@echo $@
	$(EXE_MAN) shares repository browse /
	@touch $@
$(T)/sh2: $(DIR_TMP)/.exists
	@echo $@
	$(EXE_MAN) shares repository upload --to-folder=/$(CF_SHARES_UPLOAD) $(CF_SAMPLE_FILEPATH)
	$(EXE_MAN) shares repository download --to-folder=$(DIR_TMP) /$(CF_SHARES_UPLOAD)/$(CF_SAMPLE_FILENAME)
	$(EXE_MAN) shares repository delete /$(CF_SHARES_UPLOAD)/$(CF_SAMPLE_FILENAME)
	@touch $@
tshares: $(T)/sh1 $(T)/sh2

NEW_SERVER_FOLDER=$(CF_HSTS_FOLDER_UPLOAD)/server_folder
$(T)/serv_browse:
	@echo $@
	$(EXE_MAN) server browse /
	@touch $@
$(T)/serv_mkdir:
	@echo $@
	$(EXE_MAN) server mkdir $(NEW_SERVER_FOLDER) --logger=stdout
	@touch $@
$(T)/serv_upload: $(T)/serv_mkdir
	@echo $@
	$(EXE_MAN) server upload $(CF_SAMPLE_FILEPATH) --to-folder=$(NEW_SERVER_FOLDER)
	$(EXE_MAN) server upload --src-type=pair $(CF_SAMPLE_FILEPATH) $(NEW_SERVER_FOLDER)/othername
	$(EXE_MAN) server upload --src-type=pair --sources=@json:'["$(CF_SAMPLE_FILEPATH)","$(NEW_SERVER_FOLDER)/othername"]'
	$(EXE_MAN) server upload --sources=@ts --ts=@json:'{"paths":[{"source":"$(CF_SAMPLE_FILEPATH)","destination":"$(NEW_SERVER_FOLDER)/othername"}]}'
	@touch $@
$(T)/serv_md5: $(T)/serv_upload
	@echo $@
	$(EXE_MAN) server md5sum $(NEW_SERVER_FOLDER)/$(CF_SAMPLE_FILENAME)
	@touch $@
$(T)/serv_down_lcl: $(T)/serv_upload $(DIR_TMP)/.exists
	@echo $@
	$(EXE_MAN) server download $(NEW_SERVER_FOLDER)/$(CF_SAMPLE_FILENAME) --to-folder=$(DIR_TMP)
	@touch $@
$(T)/serv_down_from_node: $(T)/serv_upload
	@echo $@
	$(EXE_MAN) server download $(NEW_SERVER_FOLDER)/$(CF_SAMPLE_FILENAME) --to-folder=$(CF_HSTS_FOLDER_UPLOAD) --transfer=node
	@touch $@
$(T)/serv_cp: $(T)/serv_upload
	@echo $@
	$(EXE_MAN) server cp $(NEW_SERVER_FOLDER)/$(CF_SAMPLE_FILENAME) $(CF_HSTS_FOLDER_UPLOAD)/200KB.2
	@touch $@
$(T)/serv_mv: $(T)/serv_cp
	@echo $@
	$(EXE_MAN) server mv $(CF_HSTS_FOLDER_UPLOAD)/200KB.2 $(CF_HSTS_FOLDER_UPLOAD)/to.delete
	@touch $@
$(T)/serv_delete: $(T)/serv_mv
	@echo $@
	$(EXE_MAN) server delete $(CF_HSTS_FOLDER_UPLOAD)/to.delete
	@touch $@
$(T)/serv_cleanup1:
	@echo $@
	$(EXE_MAN) server delete $(NEW_SERVER_FOLDER)
	@touch $@
$(T)/serv_info:
	@echo $@
	$(EXE_MAN) server info
	@touch $@
$(T)/serv_du:
	@echo $@
	$(EXE_MAN) server du /
	@touch $@
$(T)/serv_df:
	@echo $@
	$(EXE_MAN) server df
	@touch $@
$(T)/serv_nodeadmin:
	@echo $@
	$(EXE_MAN) -N server --url=ssh://$(CF_HSTS_ADDR):33001 --username=$(CF_HSTS_ADMIN_USER) --ssh-keys=$(CF_HSTS_TEST_KEY) nodeadmin -- -l
	@touch $@
$(T)/serv_nagios_webapp:
	@echo $@
	$(EXE_MAN) -N server --url=$(CF_FASPEX_SSH_URL) --username=$(CF_HSTS_ADMIN_USER) --ssh-keys=$(CF_HSTS_TEST_KEY) --format=nagios nagios app_services
	@touch $@
$(T)/serv_nagios_transfer:
	@echo $@
	$(EXE_MAN) -N server --url=$(CF_HSTS_SSH_URL) --username=$(CF_HSTS_SSH_USER) --password=$(CF_HSTS_SSH_PASS) --format=nagios nagios transfer --to-folder=$(CF_HSTS_FOLDER_UPLOAD)
	@touch $@
$(T)/serv3:
	@echo $@
	$(EXE_MAN) -N server --url=$(CF_FASPEX_SSH_URL) --username=$(CF_HSTS_ADMIN_USER) --ssh-keys=$(CF_HSTS_TEST_KEY) ctl all:status
	@touch $@
$(T)/serv_key:
	@echo $@
	$(EXE_MAN) -Pserver_eudemo_key server br /
	@touch $@
$(T)/asession:
	@echo $@
	$(DIR_BIN)/asession @json:'{"remote_host":"demo.asperasoft.com","remote_user":"$(CF_HSTS_SSH_USER)","ssh_port":33001,"remote_password":"$(CF_HSTS_SSH_PASS)","direction":"receive","destination_root":"$(DIR_TMP)","paths":[{"source":"/aspera-test-dir-tiny/200KB.1"}]}'
	@touch $@

tfasp: $(T)/serv_browse $(T)/serv_mkdir $(T)/serv_upload $(T)/serv_md5 $(T)/serv_down_lcl $(T)/serv_down_from_node $(T)/serv_cp $(T)/serv_mv $(T)/serv_delete $(T)/serv_cleanup1 $(T)/serv_info $(T)/serv_du $(T)/serv_df $(T)/asession $(T)/serv_nodeadmin $(T)/serv_nagios_webapp $(T)/serv_nagios_transfer $(T)/serv3 $(T)/serv_key

$(T)/fx_plst:
	@echo $@
	$(EXE_MAN) faspex package list
	@touch $@
$(T)/fx_psnd:
	@echo $@
	$(EXE_MAN) faspex package send --delivery-info=@json:'{"title":"'"$(PKG_TEST_TITLE)"'","recipients":["$(CF_EMAIL_ADDR)"]}' $(CF_SAMPLE_FILEPATH)
	@touch $@
$(T)/fx_prs: $(DIR_TMP)/.exists
	@echo $@
	@sleep 5
	pack_id=$$($(EXE_MAN) faspex package list --box=sent --fields=package_id --format=csv --display=data|tail -n 1);\
	echo "id=$$pack_id";\
	$(EXE_MAN) faspex package recv --box=sent --to-folder=$(DIR_TMP) --id=$$pack_id
	@touch $@
$(T)/fx_pri: $(DIR_TMP)/.exists
	@echo $@
	pack_id=$$($(EXE_NOMAN) faspex package list --fields=package_id --format=csv --display=data|tail -n 1);\
	echo "id=$$pack_id";\
	$(EXE_MAN) faspex package recv --to-folder=$(DIR_TMP) --id=$$pack_id
	@touch $@
$(T)/fx_prl:
	@echo $@
	-$(EXE_MAN) faspex package recv --link='$(CF_FASPEX_PUBLINK_RECV_PACKAGE)'
	@touch $@
$(T)/fx_prall: $(DIR_TMP)/.exists
	@echo $@
	$(EXE_MAN) faspex package recv --to-folder=$(DIR_TMP) --id=ALL --once-only=yes
	@touch $@
$(T)/fx_pslu:
	@echo $@
	$(EXE_MAN) faspex package send --link='$(CF_FASPEX_PUBLINK_SEND_TO_USER)' --delivery-info=@json:'{"title":"'"$(PKG_TEST_TITLE)"'"}' $(CF_SAMPLE_FILEPATH)
	@touch $@
$(T)/fx_psld:
	@echo $@
	$(EXE_MAN) faspex package send --link='$(CF_FASPEX_PUBLINK_SEND_DROPBOX)' --delivery-info=@json:'{"title":"'"$(PKG_TEST_TITLE)"'"}' $(CF_SAMPLE_FILEPATH)
	@touch $@
$(T)/fx_storage:
	@echo $@
	$(EXE_MAN) faspex source name "Server Files" node br /
	@touch $@
$(T)/fx_nagios:
	@echo $@
	$(EXE_MAN) faspex nagios_check
	@touch $@
tfaspex: $(T)/fx_plst $(T)/fx_psnd $(T)/fx_prs $(T)/fx_pri $(T)/fx_prl $(T)/fx_pslu $(T)/fx_psld $(T)/fx_storage $(T)/fx_prall $(T)/fx_nagios

$(T)/cons1:
	@echo $@
	$(EXE_MAN) console transfer current list 
	@touch $@
$(T)/cons2:
	@echo $@
	$(EXE_MAN) console transfer smart list 
	@touch $@
$(T)/cons3:
	@echo $@
	$(EXE_MAN) console transfer smart sub 112 @json:'{"source":{"paths":["10MB.1"]},"source_type":"user_selected"}'
	@touch $@
tconsole: $(T)/cons1 $(T)/cons2 $(T)/cons3

$(T)/nd1:
	@echo $@
	$(EXE_MAN) node info
	$(EXE_MAN) node browse / -r
	$(EXE_MAN) node search / --value=@json:'{"sort":"mtime"}'
	@touch $@
$(T)/nd2: $(DIR_TMP)/.exists
	@echo $@
	$(EXE_MAN) node upload --to-folder=$(CF_HSTS_FOLDER_UPLOAD) --ts=@json:'{"target_rate_cap_kbps":10000}' $(CF_SAMPLE_FILEPATH)
	$(EXE_MAN) node download --to-folder=$(DIR_TMP) $(CF_HSTS_FOLDER_UPLOAD)/$(CF_SAMPLE_FILENAME)
	$(EXE_MAN) node delete $(CF_HSTS_FOLDER_UPLOAD)/$(CF_SAMPLE_FILENAME)
	rm -f $(DIR_TMP)/$(CF_SAMPLE_FILENAME)
	@touch $@
$(T)/nd3:
	@echo $@
	$(EXE_MAN) --no-default node --url=$(CF_HSTS_NODE_URL) --username=$(CF_HSTS_NODE_USER) --password=$(CF_HSTS_NODE_PASS) --insecure=yes upload --to-folder=$(CF_HSTS_FOLDER_UPLOAD) --sources=@ts --ts=@json:'{"paths":[{"source":"/aspera-test-dir-small/10MB.1"}],"remote_password":"$(CF_HSTS_SSH_PASS)","precalculate_job_size":true}' --transfer=node --transfer-info=@json:'{"url":"https://$(CF_HSTS_ADDR):9092","username":"$(CF_HSTS_NODE_USER)","password":"'$(CF_HSTS_NODE_PASS)'"}' 
	$(EXE_MAN) --no-default node --url=$(CF_HSTS_NODE_URL) --username=$(CF_HSTS_NODE_USER) --password=$(CF_HSTS_NODE_PASS) --insecure=yes delete /500M.dat
	@touch $@
$(T)/nd4:
	@echo $@
	$(EXE_MAN) node service create @json:'{"id":"service1","type":"WATCHD","run_as":{"user":"user1"}}'
	$(EXE_MAN) node service list
	@echo "waiting a little...";sleep 2
	$(EXE_MAN) node service --id=service1 delete
	$(EXE_MAN) node service list
	@echo "waiting a little...";sleep 5
	$(EXE_MAN) node service list
	@echo "waiting a little...";sleep 5
	$(EXE_MAN) node service list
	@touch $@
# test creation of access key
$(T)/nd5:
	@echo $@
	$(EXE_MAN) -N --url=$(CF_HSTS2_URL) --username=$(CF_HSTS2_NODE_USER) --password=$(CF_HSTS2_NODE_PASS) node acc create --value=@json:'{"id":"aoc_1","storage":{"type":"local","path":"/"}}'
	sleep 2&&$(EXE_MAN) -N --url=$(CF_HSTS2_URL) --username=$(CF_HSTS2_NODE_USER) --password=$(CF_HSTS2_NODE_PASS) node acc delete --id=aoc_1
	@touch $@
$(T)/nd6:
	@echo $@
	$(EXE_MAN) node transfer list --value=@json:'{"active_only":true}'
	@touch $@
$(T)/nd7:
	@echo $@
	$(EXE_MAN) node basic_token
	@touch $@
$(T)/nd_nagios:
	@echo $@
	$(EXE_MAN) node nagios_check
	@touch $@
tnode: $(T)/nd1 $(T)/nd2 $(T)/nd3 $(T)/nd4 $(T)/nd5 $(T)/nd6 $(T)/nd7 $(T)/nd_nagios

$(T)/aocg1:
	@echo $@
	$(EXE_MAN) aspera apiinfo
	@touch $@
$(T)/aocg2:
	@echo $@
	$(EXE_MAN) aspera bearer_token --display=data --scope=user:all
	@touch $@
$(T)/aocg3:
	@echo $@
	$(EXE_MAN) aspera organization
	@touch $@
$(T)/aocg4:
	@echo $@
	$(EXE_MAN) aspera workspace
	@touch $@
$(T)/aocg5:
	@echo $@
	$(EXE_MAN) aspera user info show
	@touch $@
$(T)/aocg6:
	@echo $@
	$(EXE_MAN) aspera user info modify @json:'{"name":"dummy change"}'
	@touch $@
taocgen: $(T)/aocg1 $(T)/aocg2 $(T)/aocg3 $(T)/aocg4 $(T)/aocg5 $(T)/aocg6
$(T)/aocfbr:
	@echo $@
	$(EXE_MAN) aspera files browse /
	@touch $@
$(T)/aocffin:
	@echo $@
	$(EXE_MAN) aspera files find / --value='\.partial$$'
	@touch $@
$(T)/aocfmkd:
	@echo $@
	$(EXE_MAN) aspera files mkdir /testfolder
	@touch $@
$(T)/aocfren:
	@echo $@
	$(EXE_MAN) aspera files rename /testfolder newname
	@touch $@
$(T)/aocfdel:
	@echo $@
	$(EXE_MAN) aspera files delete /newname
	@touch $@
$(T)/aocf5: $(T)/aocfupl # WS: Demo
	@echo $@
	$(EXE_MAN) aspera files transfer --workspace=eudemo --from-folder='/Demo Files/aspera-test-dir-tiny' --to-folder=unit_test 200KB.1
	@touch $@
$(T)/aocfupl:
	@echo $@
	$(EXE_MAN) aspera files upload --to-folder=/ $(CF_SAMPLE_FILEPATH)
	@touch $@
$(T)/aocfbearnode:
	@echo $@
	$(EXE_MAN) aspera files bearer /
	@touch $@

$(T)/aocfdown: $(DIR_TMP)/.exists
	@echo $@
	@rm -f $(DIR_CONNECT_DOWNLOAD)/200KB.1
	$(EXE_MAN) aspera files download --transfer=connect /200KB.1
	@rm -f $(DIR_CONNECT_DOWNLOAD)/200KB.1
	@touch $@
$(T)/aocfhttpd: $(DIR_TMP)/.exists
	@echo $@
	$(EXE_MAN) aspera files http_node_download --to-folder=$(DIR_TMP) /200KB.1
	rm -f 200KB.1
	@touch $@
$(T)/aocfv3inf:
	@echo $@
	$(EXE_MAN) aspera files v3 info
	@touch $@
$(T)/aocffid:
	@echo $@
	$(EXE_MAN) aspera files file 18891
	@touch $@
$(T)/aocfpub:
	@echo $@
	$(EXE_MAN) -N aspera files browse / --link=$(CF_AOC_PUBLINK_FOLDER)
	$(EXE_MAN) -N aspera files upload --to-folder=/ $(CF_SAMPLE_FILEPATH) --link=$(CF_AOC_PUBLINK_FOLDER)
	@touch $@
$(T)/aocshlk1:
	@echo $@
	$(EXE_MAN) aspera files short_link list --value=@json:'{"purpose":"shared_folder_auth_link"}'
	@touch $@
$(T)/aocshlk2:
	@echo $@
	$(EXE_MAN) aspera files short_link create --to-folder='my folder' --value=private
	@touch $@
$(T)/aocshlk3:
	@echo $@
	$(EXE_MAN) aspera files short_link create --to-folder='my folder' --value=public
	@touch $@
taocf: $(T)/aocfbr $(T)/aocffin $(T)/aocfmkd $(T)/aocfren $(T)/aocfdel $(T)/aocf5 $(T)/aocfupl $(T)/aocfbearnode $(T)/aocfdown $(T)/aocfhttpd $(T)/aocfv3inf $(T)/aocffid $(T)/aocfpub $(T)/aocshlk1 $(T)/aocshlk2 $(T)/aocshlk3
$(T)/aocp1:
	@echo $@
	$(EXE_MAN) aspera packages send --value=@json:'{"name":"'"$(PKG_TEST_TITLE)"'","recipients":["$(CF_EMAIL_ADDR)"],"note":"my note"}' $(CF_SAMPLE_FILEPATH)
	$(EXE_MAN) aspera packages send --value=@json:'{"name":"'"$(PKG_TEST_TITLE)"'","recipients":["laurent.martin.l+external@gmail.com"]}' --new-user-option=@json:'{"package_contact":true}' $(CF_SAMPLE_FILEPATH)
	@touch $@
$(T)/aocp2:
	@echo $@
	$(EXE_MAN) aspera packages list
	@touch $@
$(T)/aocp3:
	@echo $@
	$(EXE_MAN) aspera packages recv --id=$$($(EXE_MAN) aspera packages list --format=csv --fields=id --display=data|head -n 1)
	@touch $@
$(T)/aocp4:
	@echo $@
	$(EXE_MAN) aspera packages recv --id=ALL --once-only=yes --lock-port=12345
	@touch $@
$(T)/aocp5:
	@echo $@
	$(EXE_MAN) -N aspera org --link=$(CF_AOC_PUBLINK_RECV_PACKAGE)
	@touch $@
$(T)/aocp6:
	@echo $@
	$(EXE_MAN) -N aspera packages send --value=@json:'{"name":"'"$(PKG_TEST_TITLE)"'"}' $(CF_SAMPLE_FILEPATH) --link=$(CF_AOC_PUBLINK_SEND_DROPBOX)
	@touch $@
$(T)/aocp7:
	@echo $@
	$(EXE_MAN) -N aspera packages send --value=@json:'{"name":"'"$(PKG_TEST_TITLE)"'"}' $(CF_SAMPLE_FILEPATH) --link=$(CF_AOC_PUBLINK_SEND_USER)
	@touch $@
$(T)/aocp8:
	@echo $@
	$(EXE_MAN) aspera packages send --workspace="$(CF_AOC_WS_SH_BX)" --value=@json:'{"name":"'"$(PKG_TEST_TITLE)"'","recipients":["$(CF_AOC_SH_BX)"]}' $(CF_SAMPLE_FILEPATH)
	@touch $@

taocp: $(T)/aocp1 $(T)/aocp2 $(T)/aocp3 $(T)/aocp4 $(T)/aocp5 $(T)/aocp5 $(T)/aocp6 $(T)/aocp7 $(T)/aocp8
HIDE_SECRET1='AML3clHuHwDArShhcQNVvWGHgU9dtnpgLzRCPsBr7H5JdhrFU2oRs69_tJTEYE-hXDVSW-vQ3-klRnJvxrTkxQ'
$(T)/aoc7:
	@echo $@
	$(EXE_MAN) aspera admin res node v3 events --secret=$(HIDE_SECRET1)
	@touch $@
$(T)/aoc8:
	@echo $@
	$(EXE_MAN) aspera admin resource workspace list
	@touch $@
$(T)/aoc9:
	@echo $@
	$(EXE_MAN) aspera admin resource node --name=$(CF_AOC_NODE1_NAME) --secret=$(CF_AOC_NODE1_SECRET) v3 events
	@touch $@
$(T)/aoc11:
	@echo $@
	$(EXE_MAN) aspera admin resource node --name=$(CF_AOC_NODE1_NAME) --secret=$(CF_AOC_NODE1_SECRET) v3 access_key create --value=@json:'{"id":"testsub1","storage":{"path":"/folder1"}}'
	@touch $@
$(T)/aoc12:
	@echo $@
	$(EXE_MAN) aspera admin resource node --name=$(CF_AOC_NODE1_NAME) --secret=$(CF_AOC_NODE1_SECRET) v3 access_key delete --id=testsub1
	@touch $@
$(T)/aoc9b:
	@echo $@
	$(EXE_MAN) aspera admin resource node --name=$(CF_AOC_NODE1_NAME) --secret=$(CF_AOC_NODE1_SECRET) v4 browse /
	@touch $@
$(T)/aoc10:
	@echo $@
	$(EXE_MAN) aspera admin resource node --name=$(CF_AOC_NODE1_NAME) --secret=$(CF_AOC_NODE1_SECRET) v4 mkdir /folder1
	@touch $@
$(T)/aoc13:
	@echo $@
	$(EXE_MAN) aspera admin resource node --name=$(CF_AOC_NODE1_NAME) --secret=$(CF_AOC_NODE1_SECRET) v4 delete /folder1
	@touch $@
$(T)/aoc14:
	@echo $@
	$(EXE_MAN) aspera admin resource workspace_membership list --fields=ALL --query=@json:'{"page":1,"per_page":50,"embed":"member","inherited":false,"workspace_id":11363,"sort":"name"}'
	@touch $@
$(T)/aoc15:
	@echo $@
	$(EXE_MAN) aspera admin analytics transfers --query=@json:'{"status":"completed","direction":"receive"}'
	@touch $@
taocadm: $(T)/aoc7 $(T)/aoc8 $(T)/aoc9 $(T)/aoc9b $(T)/aoc10 $(T)/aoc11 $(T)/aoc12 $(T)/aoc13 $(T)/aoc14 $(T)/aoc15
$(T)/aocat4:
	@echo $@
	$(EXE_MAN) aspera admin ats cluster list
	@touch $@
$(T)/aocat5:
	@echo $@
	$(EXE_MAN) aspera admin ats cluster clouds
	@touch $@
$(T)/aocat6:
	@echo $@
	$(EXE_MAN) aspera admin ats cluster show --cloud=aws --region=$(CF_AWS_REGION) 
	@touch $@
$(T)/aocat7:
	@echo $@
	$(EXE_MAN) aspera admin ats cluster show --id=1f412ae7-869a-445c-9c05-02ad16813be2
	@touch $@
# see https://developer.ibm.com/api/view/aspera-prod:ibm-aspera:title-IBM_Aspera#113433
$(T)/aocat8:
	-$(EXE_MAN) aspera admin ats access_key create --cloud=softlayer --region=$(CF_ICOS_REGION) --params=@json:'{"id":"akibmcloud","secret":"somesecret","name":"laurent key","storage":{"type":"ibm-s3","bucket":"$(CF_ICOS_BUCKET)","credentials":{"access_key_id":"$(CF_ICOS_AK_ID)","secret_access_key":"$(CF_ICOS_SECRET_AK)"},"path":"/"}}'
	@touch $@
$(T)/aocat9:
	@echo $@
	-$(EXE_MAN) aspera admin ats access_key create --cloud=aws --region=$(CF_AWS_REGION) --params=@json:'{"id":"ak_aws","name":"laurent key AWS","storage":{"type":"aws_s3","bucket":"'$(CF_AWS_BUCKET)'","credentials":{"access_key_id":"'$(CF_AWS_ACCESS_KEY)'","secret_access_key":"'$(CF_AWS_SECRET_KEY)'"},"path":"/"}}'
	@touch $@
$(T)/aocat10:
	@echo $@
	$(EXE_MAN) aspera admin ats access_key list --fields=name,id
	@touch $@
$(T)/aocat11:
	@echo $@
	$(EXE_MAN) aspera admin ats access_key --id=akibmcloud --secret=somesecret node browse /
	@touch $@
$(T)/aocat13:
	@echo $@
	-$(EXE_MAN) aspera admin ats access_key --id=akibmcloud delete
	@touch $@
taocts: $(T)/aocat4 $(T)/aocat5 $(T)/aocat6 $(T)/aocat7 $(T)/aocat8 $(T)/aocat9 $(T)/aocat10 $(T)/aocat11 $(T)/aocat13
$(T)/wf_id: $(T)/aocauto1
	$(EXE_MAN) aspera automation workflow list --select=@json:'{"name":"laurent_test"}' --fields=id --format=csv --display=data> $@
$(T)/aocauto1:
	@echo $@
	$(EXE_MAN) aspera automation workflow create --value=@json:'{"name":"laurent_test"}'
	@touch $@
$(T)/aocauto2:
	@echo $@
	$(EXE_MAN) aspera automation workflow list
	$(EXE_MAN) aspera automation workflow list --value=@json:'{"show_org_workflows":"true"}' --scope=admin:all
	@touch $@
$(T)/aocauto3: $(T)/wf_id
	@echo $@
	WF_ID=$$(cat $(T)/wf_id);$(EXE_MAN) aspera automation workflow --id=$$WF_ID action create --value=@json:'{"name":"toto"}' | tee action.info
	sed -nEe 's/^\| id +\| ([^ ]+) +\|/\1/p' action.info>tmp_action_id.txt;rm -f action.info
	@touch $@
$(T)/aocauto10: $(T)/wf_id
	@echo $@
	WF_ID=$$(cat $(T)/wf_id);$(EXE_MAN) aspera automation workflow delete --id=$$WF_ID
	rm -f $(T)/wf.id
	@touch $@
taocauto: $(T)/aocauto1 $(T)/aocauto2 $(T)/aocauto3 $(T)/aocauto10
taoc: taocgen taocf taocp taocadm taocts taocauto

$(T)/o1:
	@echo $@
	$(EXE_MAN) orchestrator info
	@touch $@
$(T)/o2:
	@echo $@
	$(EXE_MAN) orchestrator workflow list
	@touch $@
$(T)/o3:
	@echo $@
	$(EXE_MAN) orchestrator workflow status
	@touch $@
$(T)/o4:
	@echo $@
	$(EXE_MAN) orchestrator workflow --id=$(CF_ORCH_WORKFLOW_ID) inputs
	@touch $@
$(T)/o5:
	@echo $@
	$(EXE_MAN) orchestrator workflow --id=$(CF_ORCH_WORKFLOW_ID) status
	@touch $@
$(T)/o6:
	@echo $@
	$(EXE_MAN) orchestrator workflow --id=$(CF_ORCH_WORKFLOW_ID) start --params=@json:'{"Param":"laurent"}'
	@touch $@
$(T)/o7:
	@echo $@
	$(EXE_MAN) orchestrator workflow --id=$(CF_ORCH_WORKFLOW_ID) start --params=@json:'{"Param":"laurent"}' --result=ResultStep:Complete_status_message
	@touch $@
$(T)/o8:
	@echo $@
	$(EXE_MAN) orchestrator plugins
	@touch $@
$(T)/o9:
	@echo $@
	$(EXE_MAN) orchestrator processes
	@touch $@

torc: $(T)/o1 $(T)/o2 $(T)/o3 $(T)/o4 $(T)/o5 $(T)/o6 $(T)/o7 $(T)/o8 $(T)/o9

$(T)/at4:
	@echo $@
	$(EXE_MAN) ats cluster list
	@touch $@
$(T)/at5:
	@echo $@
	$(EXE_MAN) ats cluster clouds
	@touch $@
$(T)/at6:
	@echo $@
	$(EXE_MAN) ats cluster show --cloud=aws --region=$(CF_AWS_REGION) 
	@touch $@
$(T)/at7:
	@echo $@
	$(EXE_MAN) ats cluster show --id=1f412ae7-869a-445c-9c05-02ad16813be2
	@touch $@
$(T)/at2:
	@echo $@
	$(EXE_MAN) ats api_key instances
	@touch $@
$(T)/at1:
	@echo $@
	$(EXE_MAN) ats api_key list
	@touch $@
$(T)/at3:
	@echo $@
	$(EXE_MAN) ats api_key create
	@touch $@
$(T)/at8:
	$(EXE_MAN) ats access_key create --cloud=softlayer --region=$(CF_ICOS_REGION) --params=@json:'{"id":"akibmcloud","secret":"somesecret","name":"laurent key","storage":{"type":"ibm-s3","bucket":"$(CF_ICOS_BUCKET)","credentials":{"access_key_id":"$(CF_ICOS_AK_ID)","secret_access_key":"$(CF_ICOS_SECRET_AK)"},"path":"/"}}'
	@touch $@
$(T)/at9:
	@echo $@
	-$(EXE_MAN) ats access_key create --cloud=aws --region=$(CF_AWS_REGION) --params=@json:'{"id":"ak_aws","name":"laurent key AWS","storage":{"type":"aws_s3","bucket":"'$(CF_AWS_BUCKET)'","credentials":{"access_key_id":"'$(CF_AWS_ACCESS_KEY)'","secret_access_key":"'$(CF_AWS_SECRET_KEY)'"},"path":"/"}}'
	@touch $@
$(T)/at10:
	@echo $@
	$(EXE_MAN) ats access_key list --fields=name,id
	@touch $@
$(T)/at11:
	@echo $@
	$(EXE_MAN) ats access_key --id=akibmcloud --secret=somesecret node browse /
	@touch $@
$(T)/at12:
	@echo $@
	$(EXE_MAN) ats access_key --id=akibmcloud --secret=somesecret cluster
	@touch $@
$(T)/at13:
	$(EXE_MAN) ats access_key --id=akibmcloud delete
	@touch $@
$(T)/at14:
	@echo $@
	-$(EXE_MAN) ats access_key --id=ak_aws delete
	@touch $@

tats: $(T)/at4 $(T)/at5 $(T)/at6 $(T)/at7 $(T)/at2 $(T)/at1 $(T)/at3 $(T)/at8 $(T)/at9 $(T)/at10 $(T)/at11 $(T)/at12 $(T)/at13 $(T)/at14

$(T)/co1:
	@echo $@
	$(EXE_MAN) config ascp show
	@touch $@
$(T)/co2:
	@echo $@
	$(EXE_MAN) config ascp products list
	@touch $@
$(T)/co3:
	@echo $@
	$(EXE_MAN) config ascp connect list
	@touch $@
$(T)/co4:
	@echo $@
	$(EXE_MAN) config ascp connect id 'Aspera Connect for Windows' info
	@touch $@
$(T)/co5:
	@echo $@
	$(EXE_MAN) config ascp connect id 'Aspera Connect for Windows' links list
	@touch $@
$(T)/co6:
	@echo $@
	$(EXE_MAN) config ascp connect id 'Aspera Connect for Windows' links id 'Windows Installer' download --to-folder=.
	@touch $@
tcon: $(T)/co1 $(T)/co2 $(T)/co3 $(T)/co4 $(T)/co5 $(T)/co6

$(T)/sy1:
	@echo $@
	$(EXE_MAN) node async list
	@touch $@
$(T)/sy2:
	@echo $@
	$(EXE_MAN) node async show --id=1
	$(EXE_MAN) node async show --id=ALL
	@touch $@
$(T)/sy3:
	@echo $@
	$(EXE_MAN) node async --id=1 counters 
	@touch $@
$(T)/sy4:
	@echo $@
	$(EXE_MAN) node async --id=1 bandwidth 
	@touch $@
$(T)/sy5:
	@echo $@
	$(EXE_MAN) node async --id=1 files 
	@touch $@
tnsync: $(T)/sy1 $(T)/sy2 $(T)/sy3 $(T)/sy4 $(T)/sy5

TEST_CONFIG=sample.conf
$(T)/conf_id_1:
	@echo $@
	ASCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config id conf_name set param value
	@touch $@
$(T)/conf_id_2:
	@echo $@
	ASCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config id conf_name show
	@touch $@
$(T)/conf_id_3:
	@echo $@
	ASCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config id default set shares conf_name
	@touch $@
$(T)/conf_id_4:
	@echo $@
	ASCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config id conf_name delete
	@touch $@
$(T)/conf_id_5:
	@echo $@
	ASCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config id conf_name initialize @json:'{"p1":"v1","p2":"v2"}'
	@touch $@
$(T)/conf_id_6:
	@echo $@
	ASCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config id conf_name update --p1=v1 --p2=v2
	@touch $@
$(T)/conf_open:
	@echo $@
	ASCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config open
	@touch $@
$(T)/conf_list:
	@echo $@
	ASCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config list
	@touch $@
$(T)/conf_over:
	@echo $@
	ASCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config overview
	@touch $@
$(T)/conf_help:
	@echo $@
	$(EXE_MAN) -h
	@touch $@
$(T)/conf_open_err:
	@echo $@
	printf -- "---\nconfig:\n  version: 0" > $(TEST_CONFIG)
	-ASCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXE_MAN) config open
	@touch $@
$(T)/conf_plugins:
	@echo $@
	$(EXE_MAN) config plugins
	@touch $@
$(T)/conf_export:
	@echo $@
	$(EXE_MAN) config export
	@touch $@
HIDE_CLIENT_ID=BMDiAWLP6g
HIDE_CLIENT_SECRET=opkZrJuN-J8anDxPcPA5CFLsY5CopRvLqBeDV24_8KJgarmuYGkI0ha5zNkBLpZ1-edRwzgHZfhisyQltG-xJ-kiZvvxf3Co
SAMPLE_CONFIG_FILE=todelete.txt
$(T)/conf_wizard_org:
	@echo $@
	$(EXE_MAN) conf flush
	$(EXE_MAN) conf wiz --url=https://$(CF_AOC_ORG).ibmaspera.com --config-file=$(SAMPLE_CONFIG_FILE) --client-id=$(HIDE_CLIENT_ID) --client-secret=$(HIDE_CLIENT_SECRET) --pkeypath='' --use-generic-client=no --username=$(CF_AOC_USER)
	cat $(SAMPLE_CONFIG_FILE)
	rm -f $(SAMPLE_CONFIG_FILE)
	@touch $@
$(T)/conf_wizard_gen:
	@echo $@
	$(EXE_MAN) conf flush
	$(EXE_MAN) conf wiz --url=https://$(CF_AOC_ORG).ibmaspera.com --config-file=$(SAMPLE_CONFIG_FILE) --pkeypath='' --username=$(CF_AOC_USER) --test-mode=yes
	cat $(SAMPLE_CONFIG_FILE)
	rm -f $(SAMPLE_CONFIG_FILE)
	@touch $@
$(T)/conf_genkey: $(DIR_TMP)/.exists
	@echo $@
	$(EXE_MAN) config genkey $(DIR_TMP)/mykey
	@touch $@
$(T)/conf_smtp:
	@echo $@
	$(EXE_MAN) config email_test aspera.user1@gmail.com
	@touch $@
$(T)/conf_pac:
	@echo $@
	$(EXE_MAN) config proxy_check --fpac=file:///./examples/proxy.pac https://eudemo.asperademo.com
	@touch $@
tconf: $(T)/conf_id_1 $(T)/conf_id_2 $(T)/conf_id_3 $(T)/conf_id_4 $(T)/conf_id_5 $(T)/conf_id_6 $(T)/conf_open $(T)/conf_list $(T)/conf_over $(T)/conf_help $(T)/conf_open_err $(T)/conf_plugins $(T)/conf_export $(T)/conf_wizard_org $(T)/conf_wizard_gen $(T)/conf_genkey $(T)/conf_smtp $(T)/conf_pac

$(T)/shar2_1:
	@echo $@
	$(EXE_MAN) shares2 appinfo
	@touch $@
$(T)/shar2_2:
	@echo $@
	$(EXE_MAN) shares2 userinfo
	@touch $@
$(T)/shar2_3:
	@echo $@
	$(EXE_MAN) shares2 repository browse /
	@touch $@
$(T)/shar2_4:
	@echo $@
	$(EXE_MAN) shares2 organization list
	@touch $@
$(T)/shar2_5:
	@echo $@
	$(EXE_MAN) shares2 project list --organization=Sport
	@touch $@
tshares2: $(T)/shar2_1 $(T)/shar2_2 $(T)/shar2_3 $(T)/shar2_4 $(T)/shar2_5

$(T)/prev_check:
	@echo $@
	$(EXE_MAN) preview check --skip-types=office
	@touch $@
$(T)/prev_dcm:
	@echo $@
	$(EXE_MAN) preview test --case=$@ png "$(CF_TSTFILE_DCM)" --log-level=debug
	@touch $@
$(T)/prev_pdf:
	@echo $@
	$(EXE_MAN) preview test --case=$@ png "$(CF_TSTFILE_PDF)" --log-level=debug
	@touch $@
$(T)/prev_docx:
	@echo $@
	$(EXE_MAN) preview test --case=$@ png "$(CF_TSTFILE_DOCX)" --log-level=debug
	@touch $@
$(T)/prev_mxf_blend:
	@echo $@
	$(EXE_MAN) preview test --case=$@ mp4 "$(CF_TSTFILE_MXF)" --video-conversion=blend --log-level=debug
	@touch $@
$(T)/prev_mxf_png_fix:
	@echo $@
	$(EXE_MAN) preview test --case=$@ png "$(CF_TSTFILE_MXF)" --video-png-conv=fixed --log-level=debug
	@touch $@
$(T)/prev_mxf_png_ani:
	@echo $@
	$(EXE_MAN) preview test --case=$@ png "$(CF_TSTFILE_MXF)" --video-png-conv=animated --log-level=debug
	@touch $@
$(T)/prev_mxf_reencode:
	@echo $@
	$(EXE_MAN) preview test --case=$@ mp4 "$(CF_TSTFILE_MXF)" --video-conversion=reencode --log-level=debug
	@touch $@
$(T)/prev_mxf_clips:
	@echo $@
	$(EXE_MAN) preview test --case=$@ mp4 "$(CF_TSTFILE_MXF)" --video-conversion=clips --log-level=debug
	@touch $@
$(T)/prev_events:
	@echo $@
	$(EXE_NOMAN) -Ptest_preview node upload "$(CF_TSTFILE_MXF)" "$(CF_TSTFILE_DOCX)" --ts=@json:'{"target_rate_kbps":1000000}'
	sleep 4
	$(EXE_MAN) preview trevents --once-only=yes --skip-types=office --log-level=info
	@touch $@
$(T)/prev_scan:
	@echo $@
	$(EXE_MAN) preview scan --skip-types=office --log-level=info
	@touch $@
$(T)/prev_folder:
	@echo $@
	$(EXE_MAN) preview folder 1 --skip-types=office --log-level=info --file-access=remote --ts=@json:'{"target_rate_kbps":1000000}'
	@touch $@

tprev: $(T)/prev_check $(T)/prev_dcm $(T)/prev_pdf $(T)/prev_docx $(T)/prev_mxf_png_fix $(T)/prev_mxf_png_ani $(T)/prev_mxf_blend $(T)/prev_mxf_reencode $(T)/prev_mxf_clips $(T)/prev_events $(T)/prev_scan
clean::
	rm -f preview_*.mp4
thot:
	rm -fr source_hot
	mkdir source_hot
	-$(EXE_MAN) server delete $(CF_HSTS_FOLDER_UPLOAD)/target_hot
	$(EXE_MAN) server mkdir $(CF_HSTS_FOLDER_UPLOAD)/target_hot
	echo hello > source_hot/newfile
	$(EXE_MAN) server upload --to-folder=$(CF_HSTS_FOLDER_UPLOAD)/target_hot --lock-port=12345 --ts=@json:'{"EX_ascp_args":["--remove-after-transfer","--remove-empty-directories","--exclude-newer-than=-8","--src-base","source_hot"]}' source_hot
	$(EXE_MAN) server browse $(CF_HSTS_FOLDER_UPLOAD)/target_hot
	ls -al source_hot
	sleep 10
	$(EXE_MAN) server upload --to-folder=$(CF_HSTS_FOLDER_UPLOAD)/target_hot --lock-port=12345 --ts=@json:'{"EX_ascp_args":["--remove-after-transfer","--remove-empty-directories","--exclude-newer-than=-8","--src-base","source_hot"]}' source_hot
	$(EXE_MAN) server browse $(CF_HSTS_FOLDER_UPLOAD)/target_hot
	ls -al source_hot
	rm -fr source_hot
	@touch $@
contents:
	mkdir -p contents
$(T)/sync1: contents
	@echo $@
	$(EXE_MAN) sync start --parameters=@json:'{"sessions":[{"name":"test","reset":true,"remote_dir":"/sync_test","local_dir":"contents","host":"$(CF_HSTS_ADDR)","user":"user1","private_key_path":"$(CF_HSTS_TEST_KEY)"}]}'
	@touch $@
tsync: $(T)/sync1
t:
	mkdir t
$(T)/sdk1:
	@echo $@
	ruby -I $(DIR_LIB) $(DIR_TOP)/examples/transfer.rb
	@touch $@
tsample: $(T)/sdk1

$(T)/tcos:
	@echo $@
	$(EXE_MAN) cos node --service-credentials=@json:@file:$(CF_ICOS_CREDS_FILE) --region=$(CF_ICOS_REGION) --bucket=$(CF_ICOS_BUCKET) info
	$(EXE_MAN) cos node --service-credentials=@json:@file:$(CF_ICOS_CREDS_FILE) --region=$(CF_ICOS_REGION) --bucket=$(CF_ICOS_BUCKET) access_key --id=self show
	$(EXE_MAN) cos node --service-credentials=@json:@file:$(CF_ICOS_CREDS_FILE) --region=$(CF_ICOS_REGION) --bucket=$(CF_ICOS_BUCKET) upload $(CF_SAMPLE_FILEPATH)
	$(EXE_MAN) cos node --service-credentials=@json:@file:$(CF_ICOS_CREDS_FILE) --region=$(CF_ICOS_REGION) --bucket=$(CF_ICOS_BUCKET) download $(CF_SAMPLE_FILENAME)
	@touch $@
tcos: $(T)/tcos

$(T)/f5_1:
	@echo $@
	$(EXE_MAN) faspex5 node list --value=@json:'{"type":"received","subtype":"mypackages"}'
	@touch $@
$(T)/f5_2:
	@echo $@
	$(EXE_MAN) faspex5 package list --value=@json:'{"state":["released"]}'
	@touch $@
$(T)/f5_3:
	@echo $@
	$(EXE_MAN) faspex5 package send --value=@json:'{"title":"test title","recipients":["admin"]}' $(CF_SAMPLE_FILEPATH)
	@touch $@
$(T)/f5_4:
	@echo $@
	LAST_PACK=$$(ascli faspex5 pack list --value=@json:'{"type":"received","subtype":"mypackages","limit":1}' --fields=id --format=csv --display=data);\
	$(EXE_MAN) faspex5 package receive --id=$$LAST_PACK
	@touch $@

tf5: $(T)/f5_1 $(T)/f5_2 $(T)/f5_3 $(T)/f5_4

tests: t $(T)/unit tshares tfaspex tconsole tnode taoc tfasp tsync torc tcon tnsync tconf tprev tats tsample tcos tf5
# tshares2

tnagios: $(T)/fx_nagios $(T)/serv_nagios_webapp $(T)/serv_nagios_transfer $(T)/nd_nagios

$(T)/fxgw:
	@echo $@
	$(EXE_MAN) aspera faspex
	@touch $@

setupprev:
	asconfigurator -x "user;user_name,xfer;file_restriction,|*;token_encryption_key,1234"
	asconfigurator -x "server;activity_logging,true;activity_event_logging,true"
	sudo asnodeadmin --reload
	-$(EXE_NOMAN) node access_key --id=testkey delete --no-default --url=$(CF_HSTS2_URL) --username=$(CF_HSTS2_NODE_USER) --password=$(CF_HSTS2_NODE_PASS)
	$(EXE_NOMAN) node access_key create --value=@json:'{"id":"testkey","name":"the test key","secret":"secret","storage":{"type":"local", "path":"/Users/xfer/docroot"}}' --no-default --url=$(CF_HSTS2_URL) --username=$(CF_HSTS2_NODE_USER) --password=$(CF_HSTS2_NODE_PASS) 
	$(EXE_NOMAN) config id test_preview update --url=$(CF_HSTS2_URL) --username=testkey --password=secret
	$(EXE_NOMAN) config id default set preview test_preview

# ruby -e 'require "yaml";YAML.load_file("lib/aspera/preview_generator_formats.yml").each {|k,v|puts v};'|while read x;do touch /Users/xfer/docroot/sample${x};done

preparelocal:
	sudo asnodeadmin --reload
	sudo asnodeadmin -a -u $(CF_HSTS2_NODE_USER) -p $(CF_HSTS2_NODE_PASS) -x xfer
	sudo asconfigurator -x "user;user_name,xfer;file_restriction,|*;absolute,"
	sudo asnodeadmin --reload
noderestart:
	sudo launchctl stop com.aspera.asperanoded
	sudo launchctl start com.aspera.asperanoded
irb:
	irb -I $(DIR_LIB)
installgem:
	gem install $$(sed -nEe "/^[^#].*add_[^_]+_dependency/ s/[^']+'([^']+)'.*/\1/p" < $(GEMNAME).gemspec )
