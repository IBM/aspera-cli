# just the name of the tool
EXENAME=mlia
# location of configuration files
TOOLCONFIGDIR=$(HOME)/.aspera/$(EXENAME)
DEV_FOLDER=.
BINDIR=$(DEV_FOLDER)/bin
LIBDIR=$(DEV_FOLDER)/lib
OUT_FOLDER=out
LOCAL_FOLDER=test.dir
CONNECT_DOWNLOAD_FOLDER=$(HOME)/Desktop
# basic tool invocation
EXETESTB=$(BINDIR)/$(EXENAME)
# this config file contains credentials of platforms used for tests
MLIA_CONFIG_FILE=$(DEV_FOLDER)/local/test.mlia.conf
EXETEST=$(EXETESTB) --warnings --config-file=$(MLIA_CONFIG_FILE)
GEMNAME=asperalm
GEMVERSION=$(shell $(EXETEST) --version)
GEM_FILENAME=$(GEMNAME)-$(GEMVERSION).gem
GEMFILE=$(OUT_FOLDER)/$(GEM_FILENAME)
GIT_TAG_VERSION_PREFIX='v_'
GIT_TAG_CURRENT=$(GIT_TAG_VERSION_PREFIX)$(GEMVERSION)

SRCZIPBASE=$(GEMNAME)_src
TODAY=$(shell date +%Y%m%d)
RELEASE_ZIP_FILE=$(SRCZIPBASE)_$(TODAY).zip
LATEST_TAG=$(shell git describe --tags --abbrev=0)
# these lines do not go to manual samples
EXE_NOMAN=$(EXETEST)

INCL_USAGE=$(OUT_FOLDER)/$(EXENAME)_usage.txt
INCL_COMMANDS=$(OUT_FOLDER)/$(EXENAME)_commands.txt
INCL_ASESSION=$(OUT_FOLDER)/asession_usage.txt

CURRENT_DATE=$(shell date)


include local/config.make

all:: gem

clean::
	rm -f $(GEMNAME)-*.gem $(SRCZIPBASE)*.zip *.log token.* preview.png aspera_bypass_*.pem sample_file.txt
	rm -f README.pdf README.html README.md $(INCL_COMMANDS) $(INCL_USAGE) $(INCL_ASESSION) $(TEST_CONFIG)
	rm -fr tmp_* contents t doc out "PKG - "*
	mkdir t out
	rm -f 200KB* *AsperaConnect-ML* sample.conf* .DS_Store 10M.dat
	gem uninstall -a -x $(GEMNAME)
cleanupgems:
	gem uninstall -a -x $(gem list|cut -f 1 -d' '|egrep -v 'rdoc|psych|rake|openssl|json|io-console|bigdecimal')

changes:
	@echo "Changes since $(LATEST_TAG)"
	git log $(LATEST_TAG)..HEAD --oneline
diff: changes

doc: README.pdf

README.pdf: README.md
	pandoc --number-sections --resource-path=. --toc -o README.html README.md
	wkhtmltopdf toc README.html README.pdf

README.md: README.erb.md $(INCL_COMMANDS) $(INCL_USAGE) $(INCL_ASESSION)
	COMMANDS=$(INCL_COMMANDS) USAGE=$(INCL_USAGE) ASESSION=$(INCL_ASESSION) VERSION=`$(EXETEST) --version` TOOLNAME=$(EXENAME) erb README.erb.md > README.md

$(INCL_COMMANDS): Makefile
	sed -nEe 's/.*\$$\(EXETEST.?\)/$(EXENAME)/p' Makefile|grep -v 'Sales Engineering'|sed -E -e 's/ibmfaspex.asperasoft.com/faspex.mycompany.com/g;s/(")(url|api_key|username|password|access_key_id|secret_access_key|pass)(":")[^"]*(")/\1\2\3my_\2_here\4/g;s/--(secret|url|password|username)=[^ ]*/--\1=my_\1_here/g;s/Aspera123_/_my_pass_/g;s/\$$\(([^)]+)\)/\1/g'|grep -v 'localhost:9443'|sort -u > $(INCL_COMMANDS)
incl: Makefile
	sed -nEe 's/^	\$$\(EXETEST.?\)/$(EXENAME)/p' Makefile|sed -Ee 's/\$$\(([^)]+)\)/\&lt;\1\&gt;/g'
# depends on all sources, so regenerate always
.PHONY: $(INCL_USAGE)
$(INCL_USAGE):
	$(EXE_NOMAN) -Cnone -h 2> $(INCL_USAGE) || true

.PHONY: $(INCL_ASESSION)
$(INCL_ASESSION):
	$(BINDIR)/asession -h 2> $(INCL_ASESSION) || true

$(RELEASE_ZIP_FILE): README.md
	rm -f $(SRCZIPBASE)_*.zip
	zip -r $(RELEASE_ZIP_FILE) `git ls-files`

$(GEMFILE): README.md
	gem build asperalm.gemspec
	mv $(GEM_FILENAME) $(OUT_FOLDER)

gem: $(GEMFILE)

install: $(GEMFILE)
	gem install $(GEMFILE)

# create a private/public key pair
# note that the key can also be generated with: ssh-keygen -t rsa -f data/myid -N ''
# amd the pub key can be extracted with: openssl rsa -in data/myid -pubout -out data/myid.pub.pem
$(CF_PRIVATE_KEY_FILE):
	mkdir -p $(TOOLCONFIGDIR)
	openssl genrsa -passout pass:dummypassword -out $(CF_PRIVATE_KEY_FILE).protected 2048
	openssl rsa -passin pass:dummypassword -in $(CF_PRIVATE_KEY_FILE).protected -out $(CF_PRIVATE_KEY_FILE)
	rm -f $(CF_PRIVATE_KEY_FILE).protected

setkey: $(CF_PRIVATE_KEY_FILE)
	$(EXETEST) aspera admin res client --id=$(CF_AOC1_CLIENT_ID) set_pub_key @file:$(CF_PRIVATE_KEY_FILE)

yank:
	gem yank asperalm -v $(GEMVERSION)

dotag:
	git tag -a $(GIT_TAG_CURRENT) -m "gem version $(GEMVERSION) pushed"

deltag:
	git tag --delete $(GIT_TAG_CURRENT)

gempush: all dotag
	gem push $(GEMFILE)

commit:
	git commit -a
# eq to: git push origin master
push:
	git push

installdeps:
	gem install jwt formatador ruby-progressbar


clean::
	rm -fr $(LOCAL_FOLDER)
$(LOCAL_FOLDER)/.exists:
	mkdir -p $(LOCAL_FOLDER)
	@touch $(LOCAL_FOLDER)/.exists
t/unit:
	@echo $@
	bundle exec rake spec
	@touch $@
t/sh1:
	@echo $@
	$(EXETEST) shares repository browse /
	@touch $@
t/sh2: $(LOCAL_FOLDER)/.exists
	@echo $@
	$(EXETEST) shares repository upload --to-folder=/$(CF_SHARES_UPLOAD) $(CF_SAMPLE_FILEPATH)
	$(EXETEST) shares repository download --to-folder=$(LOCAL_FOLDER) /$(CF_SHARES_UPLOAD)/$(CF_SAMPLE_FILENAME)
	$(EXETEST) shares repository delete /$(CF_SHARES_UPLOAD)/$(CF_SAMPLE_FILENAME)
	@touch $@
tshares: t/sh1 t/sh2

NEW_SERVER_FOLDER=$(CF_HSTS_FOLDER_UPLOAD)/server_folder
t/serv_browse:
	@echo $@
	$(EXETEST) server browse /
	@touch $@
t/serv_mkdir:
	@echo $@
	$(EXETEST) server mkdir $(NEW_SERVER_FOLDER) --logger=stdout
	@touch $@
t/serv_upload: t/serv_mkdir
	@echo $@
	$(EXETEST) server upload $(CF_SAMPLE_FILEPATH) --to-folder=$(NEW_SERVER_FOLDER)
	$(EXETEST) server upload --src-type=pair $(CF_SAMPLE_FILEPATH) $(NEW_SERVER_FOLDER)/othername
	$(EXETEST) server upload --src-type=pair --sources=@json:'["$(CF_SAMPLE_FILEPATH)","$(NEW_SERVER_FOLDER)/othername"]'
	$(EXETEST) server upload --sources=@ts --ts=@json:'{"paths":[{"source":"$(CF_SAMPLE_FILEPATH)","destination":"$(NEW_SERVER_FOLDER)/othername"}]}'
	@touch $@
t/serv_md5: t/serv_upload
	@echo $@
	$(EXETEST) server md5sum $(NEW_SERVER_FOLDER)/$(CF_SAMPLE_FILENAME)
	@touch $@
t/serv_down_lcl: t/serv_upload $(LOCAL_FOLDER)/.exists
	@echo $@
	$(EXETEST) server download $(NEW_SERVER_FOLDER)/$(CF_SAMPLE_FILENAME) --to-folder=$(LOCAL_FOLDER)
	@touch $@
t/serv_down_from_node: t/serv_upload
	@echo $@
	$(EXETEST) server download $(NEW_SERVER_FOLDER)/$(CF_SAMPLE_FILENAME) --to-folder=$(CF_HSTS_FOLDER_UPLOAD) --transfer=node
	@touch $@
t/serv_cp: t/serv_upload
	@echo $@
	$(EXETEST) server cp $(NEW_SERVER_FOLDER)/$(CF_SAMPLE_FILENAME) $(CF_HSTS_FOLDER_UPLOAD)/200KB.2
	@touch $@
t/serv_mv: t/serv_cp
	@echo $@
	$(EXETEST) server mv $(CF_HSTS_FOLDER_UPLOAD)/200KB.2 $(CF_HSTS_FOLDER_UPLOAD)/to.delete
	@touch $@
t/serv_delete: t/serv_mv
	@echo $@
	$(EXETEST) server delete $(CF_HSTS_FOLDER_UPLOAD)/to.delete
	@touch $@
t/serv_cleanup1:
	@echo $@
	$(EXETEST) server delete $(NEW_SERVER_FOLDER)
	@touch $@
t/serv_info:
	@echo $@
	$(EXETEST) server info
	@touch $@
t/serv_du:
	@echo $@
	$(EXETEST) server du /
	@touch $@
t/serv_df:
	@echo $@
	$(EXETEST) server df
	@touch $@
t/asession:
	@echo $@
	$(BINDIR)/asession @json:'{"remote_host":"demo.asperasoft.com","remote_user":"$(CF_HSTS_SSH_USER)","ssh_port":33001,"remote_password":"$(CF_HSTS_SSH_PASS)","direction":"receive","destination_root":"./test.dir","paths":[{"source":"/aspera-test-dir-tiny/200KB.1"}]}'
	@touch $@
t/serv_nodeadmin:
	@echo $@
	$(EXETEST) -N server --url=ssh://$(CF_HSTS1_ADDR):33001 --username=root --ssh-keys=~/.ssh/id_rsa nodeadmin -- -l
	@touch $@
t/serv_nagios_webapp:
	@echo $@
	$(EXETEST) -N server --url=$(CF_FASPEX_SSH_URL) --username=root --ssh-keys=~/.ssh/id_rsa --format=nagios nagios app_services
	@touch $@
t/serv_nagios_transfer:
	@echo $@
	$(EXETEST) -N server --url=$(CF_HSTS_SSH_URL) --username=$(CF_HSTS_SSH_USER) --password=$(CF_HSTS_SSH_PASS) --format=nagios nagios transfer --to-folder=$(CF_HSTS_FOLDER_UPLOAD)
	@touch $@
t/serv3:
	@echo $@
	$(EXETEST) -N server --url=$(CF_FASPEX_SSH_URL) --username=root --ssh-keys=~/.ssh/id_rsa ctl all:status
	@touch $@
t/serv_key:
	@echo $@
	$(EXETEST) -Pserver_eudemo_key server br /
	@touch $@

tfasp: t/serv_browse t/serv_mkdir t/serv_upload t/serv_md5 t/serv_down_lcl t/serv_down_from_node t/serv_cp t/serv_mv t/serv_delete t/serv_cleanup1 t/serv_info t/serv_du t/serv_df t/asession t/serv_nodeadmin t/serv_nagios_webapp t/serv_nagios_transfer t/serv3 t/serv_key

t/fx_plst:
	@echo $@
	$(EXETEST) faspex package list
	@touch $@
t/fx_psnd:
	@echo $@
	$(EXETEST) faspex package send --delivery-info=@json:'{"title":"'"$(CURRENT_DATE)"'","recipients":["laurent.martin.aspera@fr.ibm.com"]}' $(CF_SAMPLE_FILEPATH)
	@touch $@
t/fx_prs: $(LOCAL_FOLDER)/.exists
	@echo $@
	@sleep 5
	$(EXETEST) faspex package recv --box=sent --to-folder=$(LOCAL_FOLDER) --id=$$($(EXETEST) faspex package list --fields=package_id --format=csv --box=sent|tail -n 1)
	@touch $@
t/fx_pri: $(LOCAL_FOLDER)/.exists
	@echo $@
	$(EXETEST) faspex package recv --to-folder=$(LOCAL_FOLDER) --id=$$($(EXETEST) faspex package list --fields=package_id --format=csv|tail -n 1)
	@touch $@
t/fx_prl:
	@echo $@
	-$(EXETEST) faspex package recv --link='$(CF_FASPEX_PUBLINK_RECV_PACKAGE)'
	@touch $@
t/fx_prall: $(LOCAL_FOLDER)/.exists
	@echo $@
	$(EXETEST) faspex package recv --to-folder=$(LOCAL_FOLDER) --id=ALL --once-only=yes
	@touch $@
t/fx_pslu:
	@echo $@
	$(EXETEST) faspex package send --link='$(CF_FASPEX_PUBLINK_SEND_TO_USER)' --delivery-info=@json:'{"title":"'"$(CURRENT_DATE)"'"}' $(CF_SAMPLE_FILEPATH)
	@touch $@
t/fx_psld:
	@echo $@
	$(EXETEST) faspex package send --link='$(CF_FASPEX_PUBLINK_SEND_DROPBOX)' --delivery-info=@json:'{"title":"'"$(CURRENT_DATE)"'"}' $(CF_SAMPLE_FILEPATH)
	@touch $@
t/fx_storage:
	@echo $@
	$(EXETEST) faspex source name "Server Files" node br /
	@touch $@
t/fx_nagios:
	@echo $@
	$(EXETEST) faspex nagios_check
	@touch $@
tfaspex: t/fx_plst t/fx_psnd t/fx_prs t/fx_pri t/fx_prl t/fx_pslu t/fx_psld t/fx_storage t/fx_prall t/fx_nagios

t/cons1:
	@echo $@
	$(EXETEST) console transfer current list 
	@touch $@
t/cons2:
	@echo $@
	$(EXETEST) console transfer smart list 
	@touch $@
t/cons3:
	@echo $@
	$(EXETEST) console transfer smart sub 112 @json:'{"source":{"paths":["10MB.1"]},"source_type":"user_selected"}'
	@touch $@
tconsole: t/cons1 t/cons2 t/cons3

t/nd1:
	@echo $@
	$(EXETEST) node info
	$(EXETEST) node browse / -r
	$(EXETEST) node search / --value=@json:'{"sort":"mtime"}'
	@touch $@
t/nd2: $(LOCAL_FOLDER)/.exists
	@echo $@
	$(EXETEST) node upload --to-folder=$(CF_HSTS_FOLDER_UPLOAD) --ts=@json:'{"target_rate_cap_kbps":10000}' $(CF_SAMPLE_FILEPATH)
	$(EXETEST) node download --to-folder=$(LOCAL_FOLDER) $(CF_HSTS_FOLDER_UPLOAD)/$(CF_SAMPLE_FILENAME)
	$(EXETEST) node delete $(CF_HSTS_FOLDER_UPLOAD)/$(CF_SAMPLE_FILENAME)
	rm -f $(LOCAL_FOLDER)/$(CF_SAMPLE_FILENAME)
	@touch $@
t/nd3:
	@echo $@
	$(EXETEST) --no-default node --url=$(CF_HSTS_NODE_URL) --username=$(CF_HSTS_NODE_USER) --password=$(CF_HSTS_NODE_PASS) --insecure=yes upload --to-folder=$(CF_HSTS_FOLDER_UPLOAD) --sources=@ts --ts=@json:'{"paths":[{"source":"/aspera-test-dir-small/10MB.1"}],"remote_password":"$(CF_HSTS_SSH_PASS)","precalculate_job_size":true}' --transfer=node --transfer-info=@json:'{"url":"https://$(CF_HSTS1_ADDR):9092","username":"$(CF_HSTS_NODE_USER)","password":"'$(CF_HSTS_NODE_PASS)'"}' 
	$(EXETEST) --no-default node --url=$(CF_HSTS_NODE_URL) --username=$(CF_HSTS_NODE_USER) --password=$(CF_HSTS_NODE_PASS) --insecure=yes delete /500M.dat
	@touch $@
t/nd4:
	@echo $@
	$(EXETEST) node service create @json:'{"id":"service1","type":"WATCHD","run_as":{"user":"user1"}}'
	$(EXETEST) node service list
	@echo "waiting a little...";sleep 2
	$(EXETEST) node service --id=service1 delete
	$(EXETEST) node service list
	@echo "waiting a little...";sleep 5
	$(EXETEST) node service list
	@echo "waiting a little...";sleep 5
	$(EXETEST) node service list
	@touch $@
# test creation of access key
t/nd5:
	@echo $@
	$(EXETEST) -N --url=https://localhost:9092 --username=node_xfer --password=$(CF_COMMON_PASS) node acc create --value=@json:'{"id":"aoc_1","secret":"'$(CF_COMMON_PASS)'","storage":{"type":"local","path":"/"}}'
	sleep 2&&$(EXETEST) -N --url=https://localhost:9092 --username=node_xfer --password=$(CF_COMMON_PASS) node acc delete --id=aoc_1
	@touch $@
t/nd6:
	@echo $@
	$(EXETEST) node transfer list --value=@json:'{"active_only":true}'
	@touch $@
t/nd7:
	@echo $@
	$(EXETEST) node basic_token
	@touch $@
t/nd_nagios:
	@echo $@
	$(EXETEST) node nagios_check
	@touch $@
tnode: t/nd1 t/nd2 t/nd3 t/nd4 t/nd5 t/nd6 t/nd7 t/nd_nagios

t/aocg1:
	@echo $@
	$(EXETEST) aspera apiinfo
	@touch $@
t/aocg2:
	@echo $@
	$(EXETEST) aspera bearer_token --display=data --scope=user:all
	@touch $@
t/aocg3:
	@echo $@
	$(EXETEST) aspera organization
	@touch $@
t/aocg4:
	@echo $@
	$(EXETEST) aspera workspace
	@touch $@
t/aocg5:
	@echo $@
	$(EXETEST) aspera user info show
	@touch $@
t/aocg6:
	@echo $@
	$(EXETEST) aspera user info modify @json:'{"name":"dummy change"}'
	@touch $@
taocgen: t/aocg1 t/aocg2 t/aocg3 t/aocg4 t/aocg5 t/aocg6
t/aocfbr:
	@echo $@
	$(EXETEST) aspera files browse /
	@touch $@
t/aocffin:
	@echo $@
	$(EXETEST) aspera files find / --value='\.partial$$'
	@touch $@
t/aocfmkd:
	@echo $@
	$(EXETEST) aspera files mkdir /testfolder
	@touch $@
t/aocfren:
	@echo $@
	$(EXETEST) aspera files rename /testfolder newname
	@touch $@
t/aocfdel:
	@echo $@
	$(EXETEST) aspera files delete /newname
	@touch $@
t/aocf5: t/aocfupl # WS: Demo
	@echo $@
	$(EXETEST) aspera files transfer --workspace=eudemo --from-folder='/Demo Files/aspera-test-dir-tiny' --to-folder=unit_test 200KB.1
	@touch $@
t/aocfupl:
	@echo $@
	$(EXETEST) aspera files upload --to-folder=/ $(CF_SAMPLE_FILEPATH)
	@touch $@
t/aocfbearnode:
	@echo $@
	$(EXETEST) aspera files bearer /
	@touch $@

t/aocfdown: $(LOCAL_FOLDER)/.exists
	@echo $@
	@rm -f $(CONNECT_DOWNLOAD_FOLDER)/200KB.1
	$(EXETEST) aspera files download --transfer=connect /200KB.1
	@rm -f $(CONNECT_DOWNLOAD_FOLDER)/200KB.1
	@touch $@
t/aocfhttpd: $(LOCAL_FOLDER)/.exists
	@echo $@
	$(EXETEST) aspera files http_node_download --to-folder=$(LOCAL_FOLDER) /200KB.1
	rm -f 200KB.1
	@touch $@
t/aocfv3inf:
	@echo $@
	$(EXETEST) aspera files v3 info
	@touch $@
t/aocffid:
	@echo $@
	$(EXETEST) aspera files file 18891
	@touch $@
t/aocfpub:
	@echo $@
	$(EXETEST) -N aspera files browse / --link=$(CF_AOC_PUBLINK_FOLDER)
	$(EXETEST) -N aspera files upload --to-folder=/ $(CF_SAMPLE_FILEPATH) --link=$(CF_AOC_PUBLINK_FOLDER)
	@touch $@
t/aocshlk1:
	@echo $@
	$(EXETEST) aspera files short_link list --value=@json:'{"purpose":"shared_folder_auth_link"}'
	@touch $@
t/aocshlk2:
	@echo $@
	$(EXETEST) aspera files short_link create --to-folder='my folder' --value=private
	@touch $@
t/aocshlk3:
	@echo $@
	$(EXETEST) aspera files short_link create --to-folder='my folder' --value=public
	@touch $@
taocf: t/aocfbr t/aocffin t/aocfmkd t/aocfren t/aocfdel t/aocf5 t/aocfupl t/aocfbearnode t/aocfdown t/aocfhttpd t/aocfv3inf t/aocffid t/aocfpub t/aocshlk1 t/aocshlk2 t/aocshlk3
t/aocp1:
	@echo $@
	$(EXETEST) aspera packages send --value=@json:'{"name":"'"$(CURRENT_DATE)"'","recipients":["laurent.martin.aspera@fr.ibm.com"],"note":"my note"}' $(CF_SAMPLE_FILEPATH)
	$(EXETEST) aspera packages send --value=@json:'{"name":"'"$(CURRENT_DATE)"'","recipients":["laurent.martin.l+external@gmail.com"]}' --new-user-option=@json:'{"package_contact":true}' $(CF_SAMPLE_FILEPATH)
	@touch $@
t/aocp2:
	@echo $@
	$(EXETEST) aspera packages list
	@touch $@
t/aocp3:
	@echo $@
	$(EXETEST) aspera packages recv --id=$$($(EXETEST) aspera packages list --format=csv --fields=id|head -n 1)
	@touch $@
t/aocp4:
	@echo $@
	$(EXETEST) aspera packages recv --id=ALL --once-only=yes --lock-port=12345
	@touch $@
t/aocp5:
	@echo $@
	$(EXETEST) -N aspera org --link=$(CF_AOC_PUBLINK_RECV_PACKAGE)
	@touch $@
t/aocp6:
	@echo $@
	$(EXETEST) -N aspera packages send --value=@json:'{"name":"'"$(CURRENT_DATE)"'"}' $(CF_SAMPLE_FILEPATH) --link=$(CF_AOC_PUBLINK_SEND_DROPBOX)
	@touch $@
t/aocp7:
	@echo $@
	$(EXETEST) -N aspera packages send --value=@json:'{"name":"'"$(CURRENT_DATE)"'"}' $(CF_SAMPLE_FILEPATH) --link=$(CF_AOC_PUBLINK_SEND_USER)
	@touch $@
t/aocp8:
	@echo $@
	$(EXETEST) aspera packages send --workspace="$(CF_AOC_WS_SH_BX)" --value=@json:'{"name":"'"$(CURRENT_DATE)"'","recipients":["$(CF_AOC_SH_BX)"]}' $(CF_SAMPLE_FILEPATH)
	@touch $@

taocp: t/aocp1 t/aocp2 t/aocp3 t/aocp4 t/aocp5 t/aocp5 t/aocp6 t/aocp7 t/aocp8
HIDE_SECRET1='AML3clHuHwDArShhcQNVvWGHgU9dtnpgLzRCPsBr7H5JdhrFU2oRs69_tJTEYE-hXDVSW-vQ3-klRnJvxrTkxQ'
t/aoc7:
	@echo $@
	$(EXETEST) aspera admin res node v3 events --secret=$(HIDE_SECRET1)
	@touch $@
t/aoc8:
	@echo $@
	$(EXETEST) aspera admin resource workspace list
	@touch $@
t/aoc9:
	@echo $@
	$(EXETEST) aspera admin resource node --name=eudemo-sedemo --secret=$(CF_COMMON_PASS) v3 events
	@touch $@
t/aoc11:
	@echo $@
	$(EXETEST) aspera admin resource node --name=eudemo-sedemo --secret=$(CF_COMMON_PASS) v3 access_key create --value=@json:'{"id":"testsub1","storage":{"path":"/folder1"}}'
	@touch $@
t/aoc12:
	@echo $@
	$(EXETEST) aspera admin resource node --name=eudemo-sedemo --secret=$(CF_COMMON_PASS) v3 access_key delete --id=testsub1
	@touch $@
t/aoc9b:
	@echo $@
	$(EXETEST) aspera admin resource node --name=eudemo-sedemo --secret=$(CF_COMMON_PASS) v4 browse /
	@touch $@
t/aoc10:
	@echo $@
	$(EXETEST) aspera admin resource node --name=eudemo-sedemo --secret=$(CF_COMMON_PASS) v4 mkdir /folder1
	@touch $@
t/aoc13:
	@echo $@
	$(EXETEST) aspera admin resource node --name=eudemo-sedemo --secret=$(CF_COMMON_PASS) v4 delete /folder1
	@touch $@
t/aoc14:
	@echo $@
	$(EXETEST) aspera admin resource workspace_membership list --fields=ALL --query=@json:'{"page":1,"per_page":50,"embed":"member","inherited":false,"workspace_id":11363,"sort":"name"}'
	@touch $@
t/aoc15:
	@echo $@
	$(EXETEST) aspera admin analytics transfers --query=@json:'{"status":"completed","direction":"receive"}'
	@touch $@
taocadm: t/aoc7 t/aoc8 t/aoc9 t/aoc9b t/aoc10 t/aoc11 t/aoc12 t/aoc13 t/aoc14 t/aoc15
t/aocat4:
	@echo $@
	$(EXETEST) aspera admin ats cluster list
	@touch $@
t/aocat5:
	@echo $@
	$(EXETEST) aspera admin ats cluster clouds
	@touch $@
t/aocat6:
	@echo $@
	$(EXETEST) aspera admin ats cluster show --cloud=aws --region=$(CF_AWS_REGION) 
	@touch $@
t/aocat7:
	@echo $@
	$(EXETEST) aspera admin ats cluster show --id=1f412ae7-869a-445c-9c05-02ad16813be2
	@touch $@
# see https://developer.ibm.com/api/view/aspera-prod:ibm-aspera:title-IBM_Aspera#113433
t/aocat8:
	-$(EXETEST) aspera admin ats access_key create --cloud=softlayer --region=$(CF_ICOS_REGION) --params=@json:'{"id":"akibmcloud","secret":"somesecret","name":"laurent key","storage":{"type":"ibm-s3","bucket":"$(CF_ICOS_BUCKET)","credentials":{"access_key_id":"$(CF_ICOS_AK_ID)","secret_access_key":"$(CF_ICOS_SECRET_AK)"},"path":"/"}}'
	@touch $@
t/aocat9:
	@echo $@
	-$(EXETEST) aspera admin ats access_key create --cloud=aws --region=$(CF_AWS_REGION) --params=@json:'{"id":"ak_aws","name":"laurent key AWS","storage":{"type":"aws_s3","bucket":"'$(CF_AWS_BUCKET)'","credentials":{"access_key_id":"'$(CF_AWS_ACCESS_KEY)'","secret_access_key":"'$(CF_AWS_SECRET_KEY)'"},"path":"/"}}'
	@touch $@
t/aocat10:
	@echo $@
	$(EXETEST) aspera admin ats access_key list --fields=name,id
	@touch $@
t/aocat11:
	@echo $@
	$(EXETEST) aspera admin ats access_key --id=akibmcloud --secret=somesecret node browse /
	@touch $@
t/aocat13:
	@echo $@
	-$(EXETEST) aspera admin ats access_key --id=akibmcloud delete
	@touch $@
taocts: t/aocat4 t/aocat5 t/aocat6 t/aocat7 t/aocat8 t/aocat9 t/aocat10 t/aocat11 t/aocat13
t/wf_id: t/aocauto1
	$(EXETEST) aspera automation workflow list --select=@json:'{"name":"laurent_test"}' --fields=id --format=csv > $@
t/aocauto1:
	@echo $@
	$(EXETEST) aspera automation workflow create --value=@json:'{"name":"laurent_test"}'
	@touch $@
t/aocauto2:
	@echo $@
	$(EXETEST) aspera automation workflow list
	$(EXETEST) aspera automation workflow list --value=@json:'{"show_org_workflows":"true"}' --scope=admin:all
	@touch $@
t/aocauto3: t/wf_id
	@echo $@
	WF_ID=$$(cat t/wf_id);$(EXETEST) aspera automation workflow --id=$$WF_ID action create --value=@json:'{"name":"toto"}' | tee action.info
	sed -nEe 's/^\| id +\| ([^ ]+) +\|/\1/p' action.info>tmp_action_id.txt;rm -f action.info
	@touch $@
t/aocauto10: t/wf_id
	@echo $@
	WF_ID=$$(cat t/wf_id);$(EXETEST) aspera automation workflow delete --id=$$WF_ID
	rm -f t/wf.id
	@touch $@
taocauto: t/aocauto1 t/aocauto2 t/aocauto3 t/aocauto10
taoc: taocgen taocf taocp taocadm taocts taocauto

t/o1:
	@echo $@
	$(EXETEST) orchestrator info
	@touch $@
t/o2:
	@echo $@
	$(EXETEST) orchestrator workflow list
	@touch $@
t/o3:
	@echo $@
	$(EXETEST) orchestrator workflow status
	@touch $@
t/o4:
	@echo $@
	$(EXETEST) orchestrator workflow --id=$(CF_WORKFLOW_ID) inputs
	@touch $@
t/o5:
	@echo $@
	$(EXETEST) orchestrator workflow --id=$(CF_WORKFLOW_ID) status
	@touch $@
t/o6:
	@echo $@
	$(EXETEST) orchestrator workflow --id=$(CF_WORKFLOW_ID) start --params=@json:'{"Param":"laurent"}'
	@touch $@
t/o7:
	@echo $@
	$(EXETEST) orchestrator workflow --id=$(CF_WORKFLOW_ID) start --params=@json:'{"Param":"laurent"}' --result=ResultStep:Complete_status_message
	@touch $@
t/o8:
	@echo $@
	$(EXETEST) orchestrator plugins
	@touch $@
t/o9:
	@echo $@
	$(EXETEST) orchestrator processes
	@touch $@

torc: t/o1 t/o2 t/o3 t/o4 t/o5 t/o6 t/o7 t/o8 t/o9

t/at4:
	@echo $@
	$(EXETEST) ats cluster list
	@touch $@
t/at5:
	@echo $@
	$(EXETEST) ats cluster clouds
	@touch $@
t/at6:
	@echo $@
	$(EXETEST) ats cluster show --cloud=aws --region=$(CF_AWS_REGION) 
	@touch $@
t/at7:
	@echo $@
	$(EXETEST) ats cluster show --id=1f412ae7-869a-445c-9c05-02ad16813be2
	@touch $@
t/at2:
	@echo $@
	$(EXETEST) ats api_key instances
	@touch $@
t/at1:
	@echo $@
	$(EXETEST) ats api_key list
	@touch $@
t/at3:
	@echo $@
	$(EXETEST) ats api_key create
	@touch $@
t/at8:
	$(EXETEST) ats access_key create --cloud=softlayer --region=$(CF_ICOS_REGION) --params=@json:'{"id":"akibmcloud","secret":"somesecret","name":"laurent key","storage":{"type":"ibm-s3","bucket":"$(CF_ICOS_BUCKET)","credentials":{"access_key_id":"$(CF_ICOS_AK_ID)","secret_access_key":"$(CF_ICOS_SECRET_AK)"},"path":"/"}}'
	@touch $@
t/at9:
	@echo $@
	-$(EXETEST) ats access_key create --cloud=aws --region=$(CF_AWS_REGION) --params=@json:'{"id":"ak_aws","name":"laurent key AWS","storage":{"type":"aws_s3","bucket":"'$(CF_AWS_BUCKET)'","credentials":{"access_key_id":"'$(CF_AWS_ACCESS_KEY)'","secret_access_key":"'$(CF_AWS_SECRET_KEY)'"},"path":"/"}}'
	@touch $@
t/at10:
	@echo $@
	$(EXETEST) ats access_key list --fields=name,id
	@touch $@
t/at11:
	@echo $@
	$(EXETEST) ats access_key --id=akibmcloud --secret=somesecret node browse /
	@touch $@
t/at12:
	@echo $@
	$(EXETEST) ats access_key --id=akibmcloud --secret=somesecret cluster
	@touch $@
t/at13:
	$(EXETEST) ats access_key --id=akibmcloud delete
	@touch $@
t/at14:
	@echo $@
	-$(EXETEST) ats access_key --id=ak_aws delete
	@touch $@

tats: t/at4 t/at5 t/at6 t/at7 t/at2 t/at1 t/at3 t/at8 t/at9 t/at10 t/at11 t/at12 t/at13 t/at14

t/co1:
	@echo $@
	$(EXETEST) config ascp show
	@touch $@
t/co2:
	@echo $@
	$(EXETEST) config ascp products list
	@touch $@
t/co3:
	@echo $@
	$(EXETEST) config ascp connect list
	@touch $@
t/co4:
	@echo $@
	$(EXETEST) config ascp connect id 'Aspera Connect for Windows' info
	@touch $@
t/co5:
	@echo $@
	$(EXETEST) config ascp connect id 'Aspera Connect for Windows' links list
	@touch $@
t/co6:
	@echo $@
	$(EXETEST) config ascp connect id 'Aspera Connect for Windows' links id 'Windows Installer' download --to-folder=.
	@touch $@
tcon: t/co1 t/co2 t/co3 t/co4 t/co5 t/co6

t/sy1:
	@echo $@
	$(EXETEST) node async list
	@touch $@
t/sy2:
	@echo $@
	$(EXETEST) node async show --id=1
	$(EXETEST) node async show --id=ALL
	@touch $@
t/sy3:
	@echo $@
	$(EXETEST) node async --id=1 counters 
	@touch $@
t/sy4:
	@echo $@
	$(EXETEST) node async --id=1 bandwidth 
	@touch $@
t/sy5:
	@echo $@
	$(EXETEST) node async --id=1 files 
	@touch $@
tnsync: t/sy1 t/sy2 t/sy3 t/sy4 t/sy5

TEST_CONFIG=sample.conf
t/conf_id_1:
	@echo $@
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config id conf_name set param value
	@touch $@
t/conf_id_2:
	@echo $@
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config id conf_name show
	@touch $@
t/conf_id_3:
	@echo $@
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config id default set shares conf_name
	@touch $@
t/conf_id_4:
	@echo $@
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config id conf_name delete
	@touch $@
t/conf_id_5:
	@echo $@
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config id conf_name initialize @json:'{"p1":"v1","p2":"v2"}'
	@touch $@
t/conf_id_6:
	@echo $@
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config id conf_name update --p1=v1 --p2=v2
	@touch $@
t/conf_open:
	@echo $@
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config open
	@touch $@
t/conf_list:
	@echo $@
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config list
	@touch $@
t/conf_over:
	@echo $@
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config overview
	@touch $@
t/conf_help:
	@echo $@
	$(EXETEST) -h
	@touch $@
t/conf_open_err:
	@echo $@
	printf -- "---\nconfig:\n  version: 0" > $(TEST_CONFIG)
	-MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config open
	@touch $@
t/conf_plugins:
	@echo $@
	$(EXETEST) config plugins
	@touch $@
t/conf_export:
	@echo $@
	$(EXETEST) config export
	@touch $@
HIDE_CLIENT_ID=BMDiAWLP6g
HIDE_CLIENT_SECRET=opkZrJuN-J8anDxPcPA5CFLsY5CopRvLqBeDV24_8KJgarmuYGkI0ha5zNkBLpZ1-edRwzgHZfhisyQltG-xJ-kiZvvxf3Co
SAMPLE_CONFIG_FILE=todelete.txt
t/conf_wizard_org:
	@echo $@
	$(EXETEST) conf flush
	$(EXETEST) conf wiz --url=https://sedemo.ibmaspera.com --config-file=$(SAMPLE_CONFIG_FILE) --client-id=$(HIDE_CLIENT_ID) --client-secret=$(HIDE_CLIENT_SECRET) --pkeypath='' --use-generic-client=no --username=laurent.martin.aspera@fr.ibm.com
	cat $(SAMPLE_CONFIG_FILE)
	rm -f $(SAMPLE_CONFIG_FILE)
	@touch $@
t/conf_wizard_gen:
	@echo $@
	$(EXETEST) conf flush
	$(EXETEST) conf wiz --url=https://sedemo.ibmaspera.com --config-file=$(SAMPLE_CONFIG_FILE) --pkeypath='' --username=laurent.martin.aspera@fr.ibm.com --test-mode=yes
	cat $(SAMPLE_CONFIG_FILE)
	rm -f $(SAMPLE_CONFIG_FILE)
	@touch $@
t/conf_genkey: $(LOCAL_FOLDER)/.exists
	@echo $@
	$(EXETEST) config genkey $(LOCAL_FOLDER)/mykey
	@touch $@
t/conf_smtp:
	@echo $@
	$(EXETEST) config email_test aspera.user1@gmail.com
	@touch $@
t/conf_pac:
	@echo $@
	$(EXETEST) config proxy_check --fpac=file:///./examples/proxy.pac https://eudemo.asperademo.com
	@touch $@
tconf: t/conf_id_1 t/conf_id_2 t/conf_id_3 t/conf_id_4 t/conf_id_5 t/conf_id_6 t/conf_open t/conf_list t/conf_over t/conf_help t/conf_open_err t/conf_plugins t/conf_export t/conf_wizard_org t/conf_wizard_gen t/conf_genkey t/conf_smtp t/conf_pac

t/shar2_1:
	@echo $@
	$(EXETEST) shares2 appinfo
	@touch $@
t/shar2_2:
	@echo $@
	$(EXETEST) shares2 userinfo
	@touch $@
t/shar2_3:
	@echo $@
	$(EXETEST) shares2 repository browse /
	@touch $@
t/shar2_4:
	@echo $@
	$(EXETEST) shares2 organization list
	@touch $@
t/shar2_5:
	@echo $@
	$(EXETEST) shares2 project list --organization=Sport
	@touch $@
tshares2: t/shar2_1 t/shar2_2 t/shar2_3 t/shar2_4 t/shar2_5

t/prev_events:
	@echo $@
	$(EXETEST) preview events --once-only=yes --skip-types=office
	@touch $@
t/prev_scan:
	@echo $@
	$(EXETEST) preview scan --skip-types=office --log-level=info
	@touch $@
t/prev_dcm:
	@echo $@
	$(EXETEST) preview test --case=$@ png ~/Documents/Samples/anatomic-2k/TG18-CH/TG18-CH-2k-01.dcm --log-level=debug
	@touch $@
t/prev_pdf:
	@echo $@
	$(EXETEST) preview test --case=$@ png ~/'Documents/Samples/YıçşöğüİÇŞÖĞÜ.pdf' --log-level=debug
	@touch $@
t/prev_mxf_blend:
	@echo $@
	$(EXETEST) preview test --case=$@ mp4 ~/'Documents/Samples/mxf_video.mxf' --video-conversion=blend --log-level=debug
	@touch $@
t/prev_mxf_reencode:
	@echo $@
	$(EXETEST) preview test --case=$@ mp4 ~/'Documents/Samples/mxf_video.mxf' --video-conversion=reencode --log-level=debug
	@touch $@
t/prev_mxf_clips:
	@echo $@
	$(EXETEST) preview test --case=$@ mp4 ~/'Documents/Samples/mxf_video.mxf' --video-conversion=clips --log-level=debug
	@touch $@

tprev: t/prev_events t/prev_scan t/prev_dcm t/prev_pdf t/prev_mxf_blend t/prev_mxf_reencode t/prev_mxf_clips
clean::
	rm -f preview_*.mp4
thot:
	rm -fr source_hot
	mkdir source_hot
	-$(EXETEST) server delete $(CF_HSTS_FOLDER_UPLOAD)/target_hot
	$(EXETEST) server mkdir $(CF_HSTS_FOLDER_UPLOAD)/target_hot
	echo hello > source_hot/newfile
	$(EXETEST) server upload --to-folder=$(CF_HSTS_FOLDER_UPLOAD)/target_hot --lock-port=12345 --ts=@json:'{"EX_ascp_args":["--remove-after-transfer","--remove-empty-directories","--exclude-newer-than=-8","--src-base","source_hot"]}' source_hot
	$(EXETEST) server browse $(CF_HSTS_FOLDER_UPLOAD)/target_hot
	ls -al source_hot
	sleep 10
	$(EXETEST) server upload --to-folder=$(CF_HSTS_FOLDER_UPLOAD)/target_hot --lock-port=12345 --ts=@json:'{"EX_ascp_args":["--remove-after-transfer","--remove-empty-directories","--exclude-newer-than=-8","--src-base","source_hot"]}' source_hot
	$(EXETEST) server browse $(CF_HSTS_FOLDER_UPLOAD)/target_hot
	ls -al source_hot
	rm -fr source_hot
	@touch $@
contents:
	mkdir -p contents
t/sync1: contents
	@echo $@
	$(EXETEST) sync start --parameters=@json:'{"sessions":[{"name":"test","reset":true,"remote_dir":"/sync_test","local_dir":"contents","host":"$(CF_HSTS1_ADDR)","user":"user1","private_key_path":"/Users/laurent/.ssh/id_rsa"}]}'
	@touch $@
tsync: t/sync1
t:
	mkdir t
t/sdk1:
	@echo $@
	ruby -I $(LIBDIR) $(DEV_FOLDER)/examples/transfer.rb
	@touch $@
tsample: t/sdk1

t/tcos:
	@echo $@
	$(EXETEST) cos node --service-credentials=@json:@file:$(CF_ICOS_CREDS_FILE) --region=$(CF_ICOS_REGION) --bucket=$(CF_ICOS_BUCKET) info
	$(EXETEST) cos node --service-credentials=@json:@file:$(CF_ICOS_CREDS_FILE) --region=$(CF_ICOS_REGION) --bucket=$(CF_ICOS_BUCKET) access_key --id=self show
	$(EXETEST) cos node --service-credentials=@json:@file:$(CF_ICOS_CREDS_FILE) --region=$(CF_ICOS_REGION) --bucket=$(CF_ICOS_BUCKET) upload $(CF_SAMPLE_FILEPATH)
	$(EXETEST) cos node --service-credentials=@json:@file:$(CF_ICOS_CREDS_FILE) --region=$(CF_ICOS_REGION) --bucket=$(CF_ICOS_BUCKET) download $(CF_SAMPLE_FILENAME)
	@touch $@
tcos: t/tcos

t/f5_1:
	@echo $@
	$(EXETEST) faspex5 node list --value=@json:'{"type":"received","subtype":"mypackages"}'
	@touch $@
t/f5_2:
	@echo $@
	$(EXETEST) faspex5 package list --value=@json:'{"state":["released"]}'
	@touch $@
t/f5_3:
	@echo $@
	$(EXETEST) faspex5 package send --value=@json:'{"title":"test title","recipients":["admin"]}' $(CF_SAMPLE_FILEPATH)
	@touch $@
t/f5_4:
	@echo $@
	LAST_PACK=$$(mlia faspex5 pack list --value=@json:'{"type":"received","subtype":"mypackages","limit":1}' --fields=id --format=csv);\
	$(EXETEST) faspex5 package receive --id=$$LAST_PACK
	@touch $@

tf5: t/f5_1 t/f5_2 t/f5_3 t/f5_4

tests: t t/unit tshares tfaspex tconsole tnode taoc tfasp tsync torc tcon tnsync tconf tprev tats tsample tcos tf5
# tshares2

tnagios: t/fx_nagios t/serv_nagios_webapp t/serv_nagios_transfer t/nd_nagios

t/fxgw:
	@echo $@
	$(EXETEST) aspera faspex
	@touch $@

setupprev:
	asconfigurator -x "user;user_name,xfer;file_restriction,|*;token_encryption_key,1234"
	asconfigurator -x "server;activity_logging,true;activity_event_logging,true"
	sudo asnodeadmin --reload
	-$(EXE_NOMAN) node access_key --id=testkey delete --no-default --url=https://localhost:9092 --username=node_xfer --password=$(CF_COMMON_PASS)
	$(EXE_NOMAN) node access_key create --value=@json:'{"id":"testkey","name":"the test key","secret":"secret","storage":{"type":"local", "path":"/Users/xfer/docroot"}}' --no-default --url=https://localhost:9092 --username=node_xfer --password=$(CF_COMMON_PASS) 
	$(EXE_NOMAN) config id test_preview update --url=https://localhost:9092 --username=testkey --password=secret
	$(EXE_NOMAN) config id default set preview test_preview

# ruby -e 'require "yaml";YAML.load_file("lib/asperalm/preview_generator_formats.yml").each {|k,v|puts v};'|while read x;do touch /Users/xfer/docroot/sample${x};done

preparelocal:
	sudo asnodeadmin --reload
	sudo asnodeadmin -a -u node_xfer -p $(CF_COMMON_PASS) -x xfer
	sudo asconfigurator -x "user;user_name,xfer;file_restriction,|*;absolute,"
	sudo asnodeadmin --reload
noderestart:
	sudo launchctl stop com.aspera.asperanoded
	sudo launchctl start com.aspera.asperanoded
irb:
	irb -I $(LIBDIR)
installgem:
	gem install $$(sed -nEe "/^[^#].*add_[^_]+_dependency/ s/[^']+'([^']+)'.*/\1/p" < asperalm.gemspec )
