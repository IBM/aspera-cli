# just name of tool
EXENAME=mlia
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
EXETEST=$(EXETESTB) -w --config-file=$(MLIA_CONFIG_FILE)
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


include config.make

all:: gem

clean::
	rm -f $(GEMNAME)-*.gem $(SRCZIPBASE)*.zip *.log token.* preview.png aspera_bypass_*.pem sample_file.txt
	rm -f README.pdf README.html README.md $(INCL_COMMANDS) $(INCL_USAGE) $(INCL_ASESSION) $(TEST_CONFIG)
	rm -fr contents t doc out "PKG - "*
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
$(MY_PRIVATE_KEY_FILE):
	mkdir -p $(TOOLCONFIGDIR)
	openssl genrsa -passout pass:dummypassword -out $(MY_PRIVATE_KEY_FILE).protected 2048
	openssl rsa -passin pass:dummypassword -in $(MY_PRIVATE_KEY_FILE).protected -out $(MY_PRIVATE_KEY_FILE)
	rm -f $(MY_PRIVATE_KEY_FILE).protected

setkey: $(MY_PRIVATE_KEY_FILE)
	$(EXETEST) aspera admin res client --id=$(MY_CLIENT_ID) set_pub_key @file:$(MY_PRIVATE_KEY_FILE)

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
	$(EXETEST) shares repository upload --to-folder=/$(SHARES_UPLOAD) $(CLIENT_DEMOFILE_PATH)
	$(EXETEST) shares repository download --to-folder=$(LOCAL_FOLDER) /$(SHARES_UPLOAD)/$(SAMPLE_FILENAME)
	$(EXETEST) shares repository delete /$(SHARES_UPLOAD)/$(SAMPLE_FILENAME)
	@touch $@
tshares: t/sh1 t/sh2 t/unit

NEW_SERVER_FOLDER=$(SERVER_FOLDER_UPLOAD)/server_folder
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
	$(EXETEST) server upload $(CLIENT_DEMOFILE_PATH) --to-folder=$(NEW_SERVER_FOLDER)
	$(EXETEST) server upload --src-type=pair $(CLIENT_DEMOFILE_PATH) $(NEW_SERVER_FOLDER)/othername
	$(EXETEST) server upload --src-type=pair --sources=@json:'["$(CLIENT_DEMOFILE_PATH)","$(NEW_SERVER_FOLDER)/othername"]'
	$(EXETEST) server upload --sources=@ts --ts=@json:'{"paths":[{"source":"$(CLIENT_DEMOFILE_PATH)","destination":"$(NEW_SERVER_FOLDER)/othername"}]}'
	@touch $@
t/serv_md5: t/serv_upload
	@echo $@
	$(EXETEST) server md5sum $(NEW_SERVER_FOLDER)/$(SAMPLE_FILENAME)
	@touch $@
t/serv_down_lcl: t/serv_upload $(LOCAL_FOLDER)/.exists
	@echo $@
	$(EXETEST) server download $(NEW_SERVER_FOLDER)/$(SAMPLE_FILENAME) --to-folder=$(LOCAL_FOLDER)
	@touch $@
t/serv_down_from_node: t/serv_upload
	@echo $@
	$(EXETEST) server download $(NEW_SERVER_FOLDER)/$(SAMPLE_FILENAME) --to-folder=$(SERVER_FOLDER_UPLOAD) --transfer=node
	@touch $@
t/serv_cp: t/serv_upload
	@echo $@
	$(EXETEST) server cp $(NEW_SERVER_FOLDER)/$(SAMPLE_FILENAME) $(SERVER_FOLDER_UPLOAD)/200KB.2
	@touch $@
t/serv_mv: t/serv_cp
	@echo $@
	$(EXETEST) server mv $(SERVER_FOLDER_UPLOAD)/200KB.2 $(SERVER_FOLDER_UPLOAD)/to.delete
	@touch $@
t/serv_delete: t/serv_mv
	@echo $@
	$(EXETEST) server delete $(SERVER_FOLDER_UPLOAD)/to.delete
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
	$(BINDIR)/asession @json:'{"remote_host":"demo.asperasoft.com","remote_user":"asperaweb","ssh_port":33001,"remote_password":"demoaspera","direction":"receive","destination_root":"./test.dir","paths":[{"source":"/aspera-test-dir-tiny/200KB.1"}]}'
	@touch $@
t/serv_nodeadmin:
	@echo $@
	$(EXETEST) -N server --url=ssh://$(HSTS_ADDR):33001 --username=root --ssh-keys=~/.ssh/id_rsa nodeadmin -- -l
	@touch $@
t/serv_nagios_webapp:
	@echo $@
	$(EXETEST) -N server --url=$(FASPEX_SSH_URL) --username=root --ssh-keys=~/.ssh/id_rsa --format=nagios nagios app_services
	@touch $@
t/serv_nagios_transfer:
	@echo $@
	$(EXETEST) -N server --url=$(HSTS_SSH_URL) --username=asperaweb --password=demoaspera --format=nagios nagios transfer --to-folder=$(SERVER_FOLDER_UPLOAD)
	@touch $@
t/serv3:
	@echo $@
	$(EXETEST) -N server --url=$(FASPEX_SSH_URL) --username=root --ssh-keys=~/.ssh/id_rsa ctl all:status
	@touch $@
tfasp: t/serv_browse t/serv_mkdir t/serv_upload t/serv_md5 t/serv_down_lcl t/serv_down_from_node t/serv_cp t/serv_mv t/serv_delete t/serv_cleanup1 t/serv_info t/serv_du t/serv_df t/asession t/serv_nodeadmin t/serv_nagios_webapp t/serv_nagios_transfer t/serv3

t/fx1:
	@echo $@
	$(EXETEST) faspex package list
	@touch $@
t/fx2:
	@echo $@
	$(EXETEST) faspex package send --delivery-info=@json:'{"title":"'"$(CURRENT_DATE)"'","recipients":["laurent.martin.aspera@fr.ibm.com"]}' $(CLIENT_DEMOFILE_PATH)
	@touch $@
t/fx3: $(LOCAL_FOLDER)/.exists
	@echo $@
	$(EXETEST) faspex package recv --to-folder=$(LOCAL_FOLDER) --id=$$($(EXETEST) faspex package list --fields=delivery_id --format=csv --box=sent|tail -n 1) --box=sent
	@touch $@
t/fx4:
	@echo $@
	-$(EXETEST) faspex package recv --link='$(FASPEX_PUBLINK_RECV_PACKAGE)'
	@touch $@
t/fx4b:
	@echo $@
	$(EXETEST) faspex package send --link='$(FASPEX_PUBLINK_SEND_TO_USER)' --delivery-info=@json:'{"title":"'"$(CURRENT_DATE)"'"}' $(CLIENT_DEMOFILE_PATH)
	@touch $@
t/fx4c:
	@echo $@
	$(EXETEST) faspex package send --link='$(FASPEX_PUBLINK_SEND_DROPBOX)' --delivery-info=@json:'{"title":"'"$(CURRENT_DATE)"'"}' $(CLIENT_DEMOFILE_PATH)
	@touch $@
t/fx5:
	@echo $@
	$(EXETEST) faspex source name "Server Files" node br /
	@touch $@
t/fx6: $(LOCAL_FOLDER)/.exists
	@echo $@
	$(EXETEST) faspex package recv --to-folder=$(LOCAL_FOLDER) --id=ALL --once-only=yes
	@touch $@
t/fx_nagios:
	@echo $@
	$(EXETEST) faspex nagios_check
	@touch $@
tfaspex: t/fx1 t/fx2 t/fx3 t/fx4 t/fx4b t/fx4c t/fx5 t/fx6 t/fx_nagios

t/cons1:
	@echo $@
	$(EXETEST) console transfer current list 
	@touch $@
tconsole: t/cons1

t/nd1:
	@echo $@
	$(EXETEST) node info
	$(EXETEST) node browse / -r
	$(EXETEST) node search / --value=@json:'{"sort":"mtime"}'
	@touch $@
t/nd2: $(LOCAL_FOLDER)/.exists
	@echo $@
	$(EXETEST) node upload --to-folder=$(SERVER_FOLDER_UPLOAD) --ts=@json:'{"target_rate_cap_kbps":10000}' $(CLIENT_DEMOFILE_PATH)
	$(EXETEST) node download --to-folder=$(LOCAL_FOLDER) $(SERVER_FOLDER_UPLOAD)/$(SAMPLE_FILENAME)
	$(EXETEST) node delete $(SERVER_FOLDER_UPLOAD)/$(SAMPLE_FILENAME)
	rm -f $(LOCAL_FOLDER)/$(SAMPLE_FILENAME)
	@touch $@
t/nd3:
	@echo $@
	$(EXETEST) --no-default node --url=$(HSTS_NODE_URL) --username=$(TEST_NODE_USER) --password=$(TEST_NODE_PASS) --insecure=yes upload --to-folder=$(SERVER_FOLDER_UPLOAD) --sources=@ts --ts=@json:'{"paths":[{"source":"/aspera-test-dir-small/10MB.1"}],"remote_password":"demoaspera","precalculate_job_size":true}' --transfer=node --transfer-info=@json:'{"url":"https://$(HSTS_ADDR):9092","username":"$(TEST_NODE_USER)","password":"'$(TEST_NODE_PASS)'"}' 
	$(EXETEST) --no-default node --url=$(HSTS_NODE_URL) --username=$(TEST_NODE_USER) --password=$(TEST_NODE_PASS) --insecure=yes delete /500M.dat
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
	$(EXETEST) -N --url=https://localhost:9092 --username=node_xfer --password=$(NODE_PASS) node acc create --value=@json:'{"id":"aoc_1","secret":"'$(NODE_PASS)'","storage":{"type":"local","path":"/"}}'
	sleep 2&&$(EXETEST) -N --url=https://localhost:9092 --username=node_xfer --password=$(NODE_PASS) node acc delete --id=aoc_1
	@touch $@
t/nd6:
	@echo $@
	$(EXETEST) node transfer list
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
t/aocf1:
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
t/aocfdel:
	@echo $@
	$(EXETEST) aspera files rename /testfolder newname
	@touch $@
t/aocf1d:
	@echo $@
	$(EXETEST) aspera files delete /newname
	@touch $@
t/aocf5: t/aocf2 # WS: Demo
	@echo $@
	$(EXETEST) aspera files transfer --workspace=eudemo --from-folder='/Demo Files/aspera-test-dir-tiny' --to-folder=xxx 200KB.1
	@touch $@
t/aocf2:
	@echo $@
	$(EXETEST) aspera files upload --to-folder=/ $(CLIENT_DEMOFILE_PATH)
	@touch $@
t/aocf3: $(LOCAL_FOLDER)/.exists
	@echo $@
	@rm -f $(CONNECT_DOWNLOAD_FOLDER)/200KB.1
	$(EXETEST) aspera files download --transfer=connect /200KB.1
	@rm -f $(CONNECT_DOWNLOAD_FOLDER)/200KB.1
	@touch $@
t/aocf4: $(LOCAL_FOLDER)/.exists
	@echo $@
	$(EXETEST) aspera files http_node_download --to-folder=$(LOCAL_FOLDER) /200KB.1
	rm -f 200KB.1
	@touch $@
t/aocf1e:
	@echo $@
	$(EXETEST) aspera files v3 info
	@touch $@
t/aocf1f:
	@echo $@
	$(EXETEST) aspera files file 18891
	@touch $@
t/aocfpub:
	@echo $@
	$(EXETEST) -N aspera files browse / --link=$(AOC_PUBLINK_FOLDER)
	$(EXETEST) -N aspera files upload --to-folder=/ $(CLIENT_DEMOFILE_PATH) --link=$(AOC_PUBLINK_FOLDER)
	@touch $@
taocf: t/aocf1 t/aocffin t/aocfmkd t/aocfdel t/aocf1d t/aocf5 t/aocf2 t/aocf3 t/aocf4 t/aocf1e t/aocf1f t/aocfpub
t/aocp1:
	@echo $@
	$(EXETEST) aspera packages send --value=@json:'{"name":"'"$(CURRENT_DATE)"'","recipients":["laurent.martin.aspera@fr.ibm.com"],"note":"my note"}' $(CLIENT_DEMOFILE_PATH)
	$(EXETEST) aspera packages send --value=@json:'{"name":"'"$(CURRENT_DATE)"'","recipients":["laurent.martin.l+external@gmail.com"]}' --new-user-option=@json:'{"package_contact":true}' $(CLIENT_DEMOFILE_PATH)
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
	$(EXETEST) -N aspera org --link=$(AOC_PUBLINK_RECV_PACKAGE)
	@touch $@
t/aocp6:
	@echo $@
	$(EXETEST) -N aspera packages send --value=@json:'{"name":"'"$(CURRENT_DATE)"'"}' $(CLIENT_DEMOFILE_PATH) --link=$(AOC_PUBLINK_SEND_DROPBOX)
	@touch $@
t/aocp7:
	@echo $@
	$(EXETEST) -N aspera packages send --value=@json:'{"name":"'"$(CURRENT_DATE)"'"}' $(CLIENT_DEMOFILE_PATH) --link=$(AOC_PUBLINK_SEND_USER)
	@touch $@

taocp: t/aocp1 t/aocp2 t/aocp3 t/aocp4 t/aocp5 t/aocp5
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
	$(EXETEST) aspera admin resource node --name=eudemo-sedemo --secret=$(NODE_PASS) v3 events
	@touch $@
t/aoc11:
	@echo $@
	$(EXETEST) aspera admin resource node --name=eudemo-sedemo --secret=$(NODE_PASS) v3 access_key create --value=@json:'{"id":"testsub1","storage":{"path":"/folder1"}}'
	@touch $@
t/aoc12:
	@echo $@
	$(EXETEST) aspera admin resource node --name=eudemo-sedemo --secret=$(NODE_PASS) v3 access_key delete --id=testsub1
	@touch $@
t/aoc9b:
	@echo $@
	$(EXETEST) aspera admin resource node --name=eudemo-sedemo --secret=$(NODE_PASS) v4 browse /
	@touch $@
t/aoc10:
	@echo $@
	$(EXETEST) aspera admin resource node --name=eudemo-sedemo --secret=$(NODE_PASS) v4 mkdir /folder1
	@touch $@
t/aoc13:
	@echo $@
	$(EXETEST) aspera admin resource node --name=eudemo-sedemo --secret=$(NODE_PASS) v4 delete /folder1
	@touch $@
t/aoc14:
	@echo $@
	$(EXETEST) aspera admin resource workspace_membership list --fields=ALL --query=@json:'{"page":1,"per_page":50,"embed":"member","inherited":false,"workspace_id":11363,"sort":"name"}'
	@touch $@
t/aoc15:
	@echo $@
	$(EXETEST) aspera admin eve --query=@json:'{"page":1,"per_page":2,"q":"*","sort":"-date"}'
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
	$(EXETEST) aspera admin ats cluster show --cloud=aws --region=eu-west-1 
	@touch $@
t/aocat7:
	@echo $@
	$(EXETEST) aspera admin ats cluster show --id=1f412ae7-869a-445c-9c05-02ad16813be2
	@touch $@
t/aocat8:
#	$(EXETEST) aspera admin ats access_key create --cloud=softlayer --region=ams --params=@json:'{"id":"testkey2","name":"laurent key","storage":{"type":"softlayer_swift","container":"laurent","credentials":{"api_key":"e5d032e026e0b0a16e890a3d44d11fd1471217b6262e83c7f60529f1ff4b27de","username":"IBMOS303446-9:laurentmartin"},"path":"/"}}'
	@touch $@
t/aocat9:
	@echo $@
	$(EXETEST) aspera admin ats access_key create --cloud=aws --region=eu-west-1 --params=@json:'{"id":"test_key_aoc","name":"laurent key AWS","storage":{"type":"aws_s3","bucket":"sedemo-ireland","credentials":{"access_key_id":"AKIAIDSWKOSIM7XUVCJA","secret_access_key":"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"},"path":"/laurent"}}'
	@touch $@
t/aocat10:
	@echo $@
	$(EXETEST) aspera admin ats access_key list --fields=name,id,secret
	@touch $@
t/aocat11:
	@echo $@
	$(EXETEST) aspera admin ats access_key --id=test_key_aoc node browse /
	@touch $@
t/aocat13:
	@echo $@
	-$(EXETEST) aspera admin ats access_key --id=test_key_aoc delete
	@touch $@
taocts: t/aocat4 t/aocat5 t/aocat6 t/aocat7 t/aocat8 t/aocat9 t/aocat10 t/aocat11 t/aocat13
taoc: taocgen taocf taocp taocadm taocts

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
	$(EXETEST) orchestrator workflow --id=$(TEST_WORKFLOW_ID) inputs
	@touch $@
t/o5:
	@echo $@
	$(EXETEST) orchestrator workflow --id=$(TEST_WORKFLOW_ID) status
	@touch $@
t/o6:
	@echo $@
	$(EXETEST) orchestrator workflow --id=$(TEST_WORKFLOW_ID) start --params=@json:'{"Param":"laurent"}'
	@touch $@
t/o7:
	@echo $@
	$(EXETEST) orchestrator workflow --id=$(TEST_WORKFLOW_ID) start --params=@json:'{"Param":"laurent"}' --result=ResultStep:Complete_status_message
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
	$(EXETEST) ats cluster show --cloud=aws --region=eu-west-1 
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
#	$(EXETEST) ats access_key create --cloud=softlayer --region=ams --params=@json:'{"id":"testkey2","name":"laurent key","storage":{"type":"softlayer_swift","container":"laurent","credentials":{"api_key":"e5d032e026e0b0a16e890a3d44d11fd1471217b6262e83c7f60529f1ff4b27de","username":"IBMOS303446-9:laurentmartin"},"path":"/"}}'
	@touch $@
t/at9:
	@echo $@
	$(EXETEST) ats access_key create --cloud=aws --region=eu-west-1 --params=@json:'{"id":"test_key_ats","name":"laurent key AWS","storage":{"type":"aws_s3","bucket":"sedemo-ireland","credentials":{"access_key_id":"AKIAIDSWKOSIM7XUVCJA","secret_access_key":"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"},"path":"/laurent"}}'
	@touch $@
t/at10:
	@echo $@
	$(EXETEST) ats access_key list --fields=name,id,secret
	@touch $@
t/at11:
	@echo $@
	$(EXETEST) ats access_key --id=test_key_ats node browse /
	@touch $@
t/at12:
	@echo $@
	$(EXETEST) ats access_key --id=test_key_ats cluster
	@touch $@
t/at13:
#	-$(EXETEST) ats access_key --id=testkey2 delete
	@touch $@
t/at14:
	@echo $@
	$(EXETEST) ats access_key --id=test_key_ats delete
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

t/prev1:
	@echo $@
	$(EXETEST) preview events --once-only=yes --skip-types=office
	@touch $@
t/prev2:
	@echo $@
	$(EXETEST) preview scan --skip-types=office --log-level=info
	@touch $@
t/prev3:
	@echo $@
	$(EXETEST) preview test ~/Documents/Samples/anatomic-2k/TG18-CH/TG18-CH-2k-01.dcm --log-level=debug png
	@touch $@
t/prev4:
	@echo $@
	$(EXETEST) preview test ~/'Documents/Samples/YıçşöğüİÇŞÖĞÜ.pdf' --log-level=debug png
	@touch $@
t/prev5:
	@echo $@
	$(EXETEST) preview test ~/'Documents/Samples/mxf_video.mxf' --log-level=debug mp4 --video-conversion=preview
	mv preview.mp4 preview_preview.mp4
	@touch $@
t/prev6:
	@echo $@
	$(EXETEST) preview test ~/'Documents/Samples/mxf_video.mxf' --log-level=debug mp4 --video-conversion=reencode
	mv preview.mp4 preview_reencode.mp4
	@touch $@
t/prev7:
	@echo $@
	$(EXETEST) preview test ~/'Documents/Samples/mxf_video.mxf' --log-level=debug mp4 --video-conversion=clips
	mv preview.mp4 preview_clips.mp4
	@touch $@

tprev: t/prev1 t/prev2 t/prev3 t/prev4 t/prev5 t/prev6 t/prev7
clean::
	rm -f preview_*.mp4
thot:
	rm -fr source_hot
	mkdir source_hot
	-$(EXETEST) server delete $(SERVER_FOLDER_UPLOAD)/target_hot
	$(EXETEST) server mkdir $(SERVER_FOLDER_UPLOAD)/target_hot
	echo hello > source_hot/newfile
	$(EXETEST) server upload --to-folder=$(SERVER_FOLDER_UPLOAD)/target_hot --lock-port=12345 --ts=@json:'{"EX_ascp_args":["--remove-after-transfer","--remove-empty-directories","--exclude-newer-than=-8","--src-base","source_hot"]}' source_hot
	$(EXETEST) server browse $(SERVER_FOLDER_UPLOAD)/target_hot
	ls -al source_hot
	sleep 10
	$(EXETEST) server upload --to-folder=$(SERVER_FOLDER_UPLOAD)/target_hot --lock-port=12345 --ts=@json:'{"EX_ascp_args":["--remove-after-transfer","--remove-empty-directories","--exclude-newer-than=-8","--src-base","source_hot"]}' source_hot
	$(EXETEST) server browse $(SERVER_FOLDER_UPLOAD)/target_hot
	ls -al source_hot
	rm -fr source_hot
	@touch $@
contents:
	mkdir -p contents
t/sync1: contents
	@echo $@
	$(EXETEST) sync start --parameters=@json:'{"sessions":[{"name":"test","reset":true,"remote_dir":"/sync_test","local_dir":"contents","host":"$(HSTS_ADDR)","user":"user1","private_key_path":"/Users/laurent/.ssh/id_rsa"}]}'
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
	mlia cos node --service-credentials=@json:@file:$(SERVICE_CREDS_FILE) --region=$(COS_REGION) --bucket=$(COS_BUCKET) info
	mlia cos node --service-credentials=@json:@file:$(SERVICE_CREDS_FILE) --region=$(COS_REGION) --bucket=$(COS_BUCKET) access_key --id=self show
	mlia cos node --service-credentials=@json:@file:$(SERVICE_CREDS_FILE) --region=$(COS_REGION) --bucket=$(COS_BUCKET) upload $(CLIENT_DEMOFILE_PATH)
	mlia cos node --service-credentials=@json:@file:$(SERVICE_CREDS_FILE) --region=$(COS_REGION) --bucket=$(COS_BUCKET) download $(SAMPLE_FILENAME)
	@touch $@
tcos: t/tcos

tests: t tshares tfaspex tconsole tnode taoc tfasp tsync torc tcon tnsync tconf tprev tats tsample tcos
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
	-$(EXE_NOMAN) node access_key --id=testkey delete --no-default --url=https://localhost:9092 --username=node_xfer --password=$(NODE_PASS)
	$(EXE_NOMAN) node access_key create --value=@json:'{"id":"testkey","name":"the test key","secret":"secret","storage":{"type":"local", "path":"/Users/xfer/docroot"}}' --no-default --url=https://localhost:9092 --username=node_xfer --password=$(NODE_PASS) 
	$(EXE_NOMAN) config id test_preview update --url=https://localhost:9092 --username=testkey --password=secret
	$(EXE_NOMAN) config id default set preview test_preview

# ruby -e 'require "yaml";YAML.load_file("lib/asperalm/preview_generator_formats.yml").each {|k,v|puts v};'|while read x;do touch /Users/xfer/docroot/sample${x};done

preparelocal:
	sudo asnodeadmin -a -u node_xfer -p $(NODE_PASS) -x xfer
	sudo asconfigurator -x "user;user_name,xfer;file_restriction,|*;absolute,"
	sudo asnodeadmin --reload
irb:
	irb -I $(LIBDIR)
installgem:
	gem install $$(sed -nEe "/^[^#].*add_[^_]+_dependency/ s/[^']+'([^']+)'.*/\1/p" < asperalm.gemspec )
