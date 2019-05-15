# just name of tool
EXENAME=mlia
TOOLCONFIGDIR=$(HOME)/.aspera/$(EXENAME)
APIKEY=$(TOOLCONFIGDIR)/filesapikey
MAINDIR=.
BINDIR=$(MAINDIR)/bin
LIBDIR=$(MAINDIR)/lib
OUT_FOLDER=out
TEST_FOLDER=test.dir
# tool invokation
EXETEST1=$(BINDIR)/$(EXENAME)
EXETEST=$(EXETEST1) -w
GEMNAME=asperalm
GEMVERSION=$(shell $(EXETEST) --version)
GEM_FILENAME=$(GEMNAME)-$(GEMVERSION).gem
GEMFILE=$(OUT_FOLDER)/$(GEM_FILENAME)
GIT_TAG_VERSION_PREFIX='v_'
GIT_TAG_CURRENT=$(GIT_TAG_VERSION_PREFIX)$(GEMVERSION)

SRCZIPBASE=$(GEMNAME)_src
TODAY=$(shell date +%Y%m%d)
ZIPFILE=$(SRCZIPBASE)_$(TODAY).zip
LATEST_TAG=$(shell git describe --tags --abbrev=0)
# these lines do not go to manual samples
EXE_NOMAN=$(EXETEST)

INCL_USAGE=$(OUT_FOLDER)/$(EXENAME)_usage.txt
INCL_COMMANDS=$(OUT_FOLDER)/$(EXENAME)_commands.txt
INCL_ASESSION=$(OUT_FOLDER)/asession_usage.txt

PACKAGE_TITLE=$(shell date)

NODE_PASS=Aspera123_

all:: gem

clean::
	rm -f $(GEMNAME)-*.gem $(SRCZIPBASE)*.zip *.log token.* preview.png aspera_bypass_*.pem sample_file.txt
	rm -f README.pdf README.html README.md $(INCL_COMMANDS) $(INCL_USAGE) $(INCL_ASESSION) $(TEST_CONFIG)
	rm -fr contents t doc out "PKG - "*
	mkdir t out
	rm -f 200KB* *AsperaConnect-ML* sample.conf* .DS_Store 
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
	sed -nEe 's/.*\$$\(EXETEST.?\)/$(EXENAME)/p' Makefile|grep -v 'Sales Engineering'|sed -E -e 's/\$$\(SAMPLE_FILE\)/sample_file.bin/g;s/\$$\(NODEDEST\)/sample_dest_folder/g;s/\$$\(TEST_FOLDER\)/sample_dest_folder/g;s/ibmfaspex.asperasoft.com/faspex.mycompany.com/g;s/(")(url|api_key|username|password|access_key_id|secret_access_key|pass)(":")[^"]*(")/\1\2\3my_\2_here\4/g;s/--(secret|url|password|username)=[^ ]*/--\1=my_\1_here/g;s/Aspera123_/_my_pass_/g'|grep -v 'localhost:9443'|sort -u > $(INCL_COMMANDS)

# depends on all sources, so regenerate always
.PHONY: $(INCL_USAGE)
$(INCL_USAGE):
	$(EXE_NOMAN) -Cnone -h 2> $(INCL_USAGE) || true

.PHONY: $(INCL_ASESSION)
$(INCL_ASESSION):
	$(BINDIR)/asession -h 2> $(INCL_ASESSION) || true

$(ZIPFILE): README.md
	rm -f $(SRCZIPBASE)_*.zip
	zip -r $(ZIPFILE) `git ls-files`

$(GEMFILE): README.md
	gem build asperalm.gemspec
	mv $(GEM_FILENAME) $(OUT_FOLDER)

gem: $(GEMFILE)

install: $(GEMFILE)
	gem install $(GEMFILE)

# create a private/public key pair
# note that the key can also be generated with: ssh-keygen -t rsa -f data/myid -N ''
# amd the pub key can be extracted with: openssl rsa -in data/myid -pubout -out data/myid.pub.pem
$(APIKEY):
	mkdir -p $(TOOLCONFIGDIR)
	openssl genrsa -passout pass:dummypassword -out $(APIKEY).protected 2048
	openssl rsa -passin pass:dummypassword -in $(APIKEY).protected -out $(APIKEY)
	rm -f $(APIKEY).protected

setkey: $(APIKEY)
	$(EXETEST) aspera admin set_client_key ERuzXGuPA @file:$(APIKEY)

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

SAMPLE_FILE=~/Documents/Samples/200KB.1

TEST_SHARE=000_test1
clean::
	rm -fr $(TEST_FOLDER)
$(TEST_FOLDER)/.exists:
	mkdir -p $(TEST_FOLDER)
	@touch $(TEST_FOLDER)/.exists
t/unit:
	bundle exec rake spec
	@touch $@
t/sh1:
	$(EXETEST) shares repository browse /
	@touch $@
t/sh2: $(TEST_FOLDER)/.exists
	$(EXETEST) shares repository upload --to-folder=/$(TEST_SHARE) --sources=@args $(SAMPLE_FILE)
	$(EXETEST) shares repository download --to-folder=$(TEST_FOLDER) --sources=@args /$(TEST_SHARE)/200KB.1
	$(EXETEST) shares repository delete /$(TEST_SHARE)/200KB.1
	@touch $@
tshares: t/sh1 t/sh2 t/unit

t/fp1: $(TEST_FOLDER)/.exists
	$(EXETEST) server browse /
	$(EXETEST) server upload --to-folder=/Upload --sources=@args $(SAMPLE_FILE)
	$(EXETEST) server download --to-folder=$(TEST_FOLDER) --sources=@args /Upload/200KB.1
	$(EXETEST) server download --sources=@args /Upload/200KB.1 --transfer=node
	$(EXETEST) server cp /Upload/200KB.1 /Upload/200KB.2
	$(EXETEST) server mv /Upload/200KB.2 /Upload/to.delete
	$(EXETEST) server delete /Upload/to.delete
	$(EXETEST) server md5sum /Upload/200KB.1
	$(EXETEST) server delete /Upload/200KB.1
	@touch $@
t/fp2:
	$(EXETEST) server mkdir /Upload/123 --logger=stdout
	$(EXETEST) server rm /Upload/123
	@touch $@
t/fp3:
	$(EXETEST) server info
	$(EXETEST) server du /
	$(EXETEST) server df
	@touch $@
t/fp4:
	$(BINDIR)/asession @json:'{"remote_host":"demo.asperasoft.com","remote_user":"asperaweb","ssh_port":33001,"remote_password":"demoaspera","direction":"receive","destination_root":"./test.dir","paths":[{"source":"/aspera-test-dir-tiny/200KB.1"}]}'
	@touch $@
t/serv1:
	$(EXETEST) -N server --url=ssh://10.25.0.8:33001 --username=root --ssh-keys=~/.ssh/id_rsa nodeadmin -- -l
	@touch $@
t/serv_nagios_webapp:
	$(EXETEST) -N server --url=ssh://10.25.0.3 --username=root --ssh-keys=~/.ssh/id_rsa --format=nagios nagios app_services
	@touch $@
t/serv_nagios_transfer:
	$(EXETEST) -N server --url=ssh://eudemo.asperademo.com:33001 --username=asperaweb --password=demoaspera --format=nagios nagios transfer --to-folder=/Upload
	@touch $@
t/serv3:
	$(EXETEST) -N server --url=ssh://10.25.0.3 --username=root --ssh-keys=~/.ssh/id_rsa ctl all:status
	@touch $@
tfasp: t/fp1 t/fp2 t/fp3 t/fp4 t/serv1 t/serv_nagios_webapp t/serv_nagios_transfer t/serv3

t/fx1:
	$(EXETEST) faspex package list
	@touch $@
t/fx2:
	$(EXETEST) faspex package send --delivery-info=@json:'{"title":"'"$(PACKAGE_TITLE)"'","recipients":["laurent.martin.aspera@fr.ibm.com"]}' --sources=@args $(SAMPLE_FILE) 
	@touch $@
t/fx3:
	$(EXETEST) faspex package recv --to-folder=$(TEST_FOLDER) --id=$$($(EXETEST) faspex package list --fields=delivery_id --format=csv --box=sent|tail -n 1) --box=sent
	@touch $@
t/fx4:
	@echo $(EXETEST) faspex recv_publink 'https://ibmfaspex.asperasoft.com/aspera/faspex/external_deliveries/78780?passcode=a003aaf2f53e3869126b908525084db6bebc7031' --insecure=yes
	@touch $@
t/fx5:
	$(EXETEST) faspex source name "Server Files" node br /
	@touch $@
t/fx6:
	$(EXETEST) faspex package recv --to-folder=$(TEST_FOLDER) --id=ALL --once-only=yes
	@touch $@
t/fx_nagios:
	$(EXETEST) faspex nagios_check
	@touch $@
tfaspex: t/fx1 t/fx2 t/fx3 t/fx4 t/fx5 t/fx6 t/fx_nagios

t/cons1:
	$(EXETEST) console transfer current list 
	@touch $@
tconsole: t/cons1

#NODEDEST=/home/faspex/docroot
NODEDEST=/
t/nd1:
	$(EXETEST) node info
	$(EXETEST) node browse / -r
	$(EXETEST) node search / --value=@json:'{"sort":"mtime"}'
	@touch $@
t/nd2: $(TEST_FOLDER)/.exists
	$(EXETEST) node upload --to-folder=$(NODEDEST) --ts=@json:'{"target_rate_cap_kbps":10000}' $(SAMPLE_FILE)
	$(EXETEST) node download --to-folder=$(TEST_FOLDER) --sources=@args $(NODEDEST)200KB.1
	$(EXETEST) node delete $(NODEDEST)200KB.1
	rm -f $(TEST_FOLDER)/200KB.1
	@touch $@
t/nd3:
	$(EXETEST) --no-default node --url=https://eudemo.asperademo.com:9092 --username=node_aspera --password=aspera --insecure=yes upload --to-folder=/Upload --sources=@ts --ts=@json:'{"paths":[{"source":"500M.dat"}],"remote_password":"demoaspera","precalculate_job_size":true}' --transfer=node --transfer-info=@json:'{"url":"https://10.25.0.8:9092","username":"node_xferuser","password":"'$(NODE_PASS)'"}' 
	$(EXETEST) --no-default node --url=https://eudemo.asperademo.com:9092 --username=node_aspera --password=aspera --insecure=yes delete /500M.dat
	@touch $@
t/nd4:
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
t/nd5:
	$(EXETEST) -Pnode_lmdk08 --url=https://localhost:9092 --username=node_xfer --password=$(NODE_PASS) node acc create --value=@json:'{"id":"aoc_1","secret":"'$(NODE_PASS)'","storage":{"type":"local","path":"/"}}'
	sleep 2&&$(EXETEST) -Pnode_lmdk08 --url=https://localhost:9092 --username=node_xfer --password=$(NODE_PASS) node acc delete --id=aoc_1
	@touch $@
t/nd6:
	$(EXETEST) node transfer list
	@touch $@
t/nd_nagios:
	$(EXETEST) node nagios_check
	@touch $@
tnode: t/nd1 t/nd2 t/nd3 t/nd4 t/nd5 t/nd6 t/nd_nagios

t/aocg1:
	$(EXETEST) aspera apiinfo
	@touch $@
t/aocg2:
	$(EXETEST) aspera bearer_token --display=data --scope=user:all
	@touch $@
t/aocg3:
	$(EXETEST) aspera organization
	@touch $@
t/aocg4:
	$(EXETEST) aspera workspace
	@touch $@
t/aocg5:
	$(EXETEST) aspera user info show
	@touch $@
t/aocg6:
	$(EXETEST) aspera user info modify @json:'{"name":"dummy change"}'
	@touch $@
taocgen: t/aocg1 t/aocg2 t/aocg3 t/aocg4 t/aocg5 t/aocg6
t/aocf1:
	$(EXETEST) aspera files browse /
	@touch $@
t/aocffin:
	$(EXETEST) aspera files find / --value='\.partial$$'
	@touch $@
t/aocfmkd:
	$(EXETEST) aspera files mkdir /testfolder
	@touch $@
t/aocfdel:
	$(EXETEST) aspera files rename /testfolder newname
	@touch $@
t/aocf1d:
	$(EXETEST) aspera files delete /newname
	@touch $@
t/aocf5: t/aocf2 # WS: Demo
	$(EXETEST) aspera files transfer --from-folder=/ --to-folder=xxx --sources=@args 200KB.1
	@touch $@
t/aocf2:
	$(EXETEST) aspera files upload --to-folder=/ $(SAMPLE_FILE)
	@touch $@
t/aocf3: $(TEST_FOLDER)/.exists
	@rm -f $(TEST_FOLDER)/200KB.1
	$(EXETEST) aspera files download --to-folder=$(TEST_FOLDER) --transfer=connect --sources=@args /200KB.1
	@rm -f $(TEST_FOLDER)/200KB.1
	@touch $@
t/aocf4: $(TEST_FOLDER)/.exists
	$(EXETEST) aspera files http_node_download --to-folder=$(TEST_FOLDER) --sources=@args /200KB.1
	rm -f 200KB.1
	@touch $@
t/aocf1e:
	$(EXETEST) aspera files v3 info
	@touch $@
t/aocf1f:
	$(EXETEST) aspera files file 18891
	@touch $@
taocf: t/aocf1 t/aocffin t/aocfmkd t/aocfdel t/aocf1d t/aocf5 t/aocf2 t/aocf3 t/aocf4 t/aocf1e t/aocf1f
t/aocp1:
	$(EXETEST) aspera packages send --value=@json:'{"name":"'"$(PACKAGE_TITLE)"'","note":"my note","recipients":["laurent.martin.aspera@fr.ibm.com"]}' --sources=@args $(SAMPLE_FILE)
	$(EXETEST) aspera packages send --value=@json:'{"name":"'"$(PACKAGE_TITLE)"'","recipients":["laurent.martin.l+external@gmail.com"]}' --new-user-option=@json:'{"package_contact":true}' --sources=@args $(SAMPLE_FILE)
	@touch $@
t/aocp2:
	$(EXETEST) aspera packages list
	@touch $@
t/aocp3:
	$(EXETEST) aspera packages recv --id=$$($(EXETEST) aspera packages list --format=csv --fields=id|head -n 1)
	@touch $@
t/aocp4:
	$(EXETEST) aspera packages recv --id=ALL --once-only=yes --lock-port=12345
	@touch $@
t/aocp5:
	$(EXETEST) -N aspera org --link=https://sedemo.ibmaspera.com/packages/public/receive?token=cpDktbNc8aHnyrbI_V49GzFwm5q3jxWnT_cDOjaewrc
	@touch $@
taocp: t/aocp1 t/aocp2 t/aocp3 t/aocp4 t/aocp5
HIDE_SECRET1='AML3clHuHwDArShhcQNVvWGHgU9dtnpgLzRCPsBr7H5JdhrFU2oRs69_tJTEYE-hXDVSW-vQ3-klRnJvxrTkxQ'
t/aoc7:
	$(EXETEST) aspera admin res node v3 events --secret=$(HIDE_SECRET1)
	@touch $@
t/aoc8:
	$(EXETEST) aspera admin resource workspace list
	@touch $@
t/aoc9:
	$(EXETEST) aspera admin resource node --name=eudemo-sedemo --secret=$(NODE_PASS) v3 events
	@touch $@
t/aoc11:
	$(EXETEST) aspera admin resource node --name=eudemo-sedemo --secret=$(NODE_PASS) v3 access_key create --value=@json:'{"id":"testsub1","storage":{"path":"/folder1"}}'
	@touch $@
t/aoc12:
	$(EXETEST) aspera admin resource node --name=eudemo-sedemo --secret=$(NODE_PASS) v3 access_key delete --id=testsub1
	@touch $@
t/aoc9b:
	$(EXETEST) aspera admin resource node --name=eudemo-sedemo --secret=$(NODE_PASS) v4 browse /
	@touch $@
t/aoc10:
	$(EXETEST) aspera admin resource node --name=eudemo-sedemo --secret=$(NODE_PASS) v4 mkdir /folder1
	@touch $@
t/aoc13:
	$(EXETEST) aspera admin resource node --name=eudemo-sedemo --secret=$(NODE_PASS) v4 delete /folder1
	@touch $@
t/aoc14:
	$(EXETEST) aspera admin resource workspace_membership list --fields=ALL --query=@json:'{"page":1,"per_page":50,"embed":"member","inherited":false,"workspace_id":11363,"sort":"name"}'
	@touch $@
t/aoc15:
	$(EXETEST) aspera admin eve --query=@json:'{"page":1,"per_page":2,"q":"*","sort":"-date"}'
	@touch $@
taocadm: t/aoc7 t/aoc8 t/aoc9 t/aoc9b t/aoc10 t/aoc11 t/aoc12 t/aoc13 t/aoc14 t/aoc15 
t/aocat4:
	$(EXETEST) aspera admin ats cluster list
	@touch $@
t/aocat5:
	$(EXETEST) aspera admin ats cluster clouds
	@touch $@
t/aocat6:
	$(EXETEST) aspera admin ats cluster show --cloud=aws --region=eu-west-1 
	@touch $@
t/aocat7:
	$(EXETEST) aspera admin ats cluster show --id=1f412ae7-869a-445c-9c05-02ad16813be2
	@touch $@
t/aocat8:
	$(EXETEST) aspera admin ats access_key create --cloud=softlayer --region=ams --params=@json:'{"id":"testkey2","name":"laurent key","storage":{"type":"softlayer_swift","container":"laurent","credentials":{"api_key":"e5d032e026e0b0a16e890a3d44d11fd1471217b6262e83c7f60529f1ff4b27de","username":"IBMOS303446-9:laurentmartin"},"path":"/"}}'
	@touch $@
t/aocat9:
	$(EXETEST) aspera admin ats access_key create --cloud=aws --region=eu-west-1 --params=@json:'{"id":"testkey3","name":"laurent key AWS","storage":{"type":"aws_s3","bucket":"sedemo-ireland","credentials":{"access_key_id":"AKIAIDSWKOSIM7XUVCJA","secret_access_key":"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"},"path":"/laurent"}}'
	@touch $@
t/aocat10:
	$(EXETEST) aspera admin ats access_key list --fields=name,id,secret
	@touch $@
t/aocat11:
	$(EXETEST) aspera admin ats access_key --id=testkey2 node browse /
	@touch $@
t/aocat13:
	-$(EXETEST) aspera admin ats access_key --id=testkey2 delete
	@touch $@
t/aocat14:
	-$(EXETEST) aspera admin ats access_key --id=testkey3 delete
	@touch $@
taocts: t/aocat4 t/aocat5 t/aocat6 t/aocat7 t/aocat8 t/aocat9 t/aocat10 t/aocat11 t/aocat13 t/aocat14
taoc: taocgen taocf taocp taocadm taocts

t/o1:
	$(EXETEST) orchestrator info
	@touch $@
t/o2:
	$(EXETEST) orchestrator workflow list
	@touch $@
t/o3:
	$(EXETEST) orchestrator workflow status
	@touch $@
t/o4:
	$(EXETEST) orchestrator workflow --id=10 inputs
	@touch $@
t/o5:
	$(EXETEST) orchestrator workflow --id=10 status
	@touch $@
t/o6:
	$(EXETEST) orchestrator workflow --id=10 start --params=@json:'{"Param":"laurent"}'
	@touch $@
t/o7:
	$(EXETEST) orchestrator workflow --id=10 start --params=@json:'{"Param":"laurent"}' --result=ResultStep:Complete_status_message
	@touch $@
t/o8:
	$(EXETEST) orchestrator plugins
	@touch $@
t/o9:
	$(EXETEST) orchestrator processes
	@touch $@

torc: t/o1 t/o2 t/o3 t/o4 t/o5 t/o6 t/o7 t/o8 t/o9

t/at4:
	$(EXETEST) ats cluster list
	@touch $@
t/at5:
	$(EXETEST) ats cluster clouds
	@touch $@
t/at6:
	$(EXETEST) ats cluster show --cloud=aws --region=eu-west-1 
	@touch $@
t/at7:
	$(EXETEST) ats cluster show --id=1f412ae7-869a-445c-9c05-02ad16813be2
	@touch $@
t/at2:
	$(EXETEST) ats api_key instances
	@touch $@
t/at1:
	$(EXETEST) ats api_key list
	@touch $@
t/at3:
	$(EXETEST) ats api_key create
	@touch $@
t/at8:
	$(EXETEST) ats access_key create --cloud=softlayer --region=ams --params=@json:'{"id":"testkey2","name":"laurent key","storage":{"type":"softlayer_swift","container":"laurent","credentials":{"api_key":"e5d032e026e0b0a16e890a3d44d11fd1471217b6262e83c7f60529f1ff4b27de","username":"IBMOS303446-9:laurentmartin"},"path":"/"}}'
	@touch $@
t/at9:
	$(EXETEST) ats access_key create --cloud=aws --region=eu-west-1 --params=@json:'{"id":"testkey3","name":"laurent key AWS","storage":{"type":"aws_s3","bucket":"sedemo-ireland","credentials":{"access_key_id":"AKIAIDSWKOSIM7XUVCJA","secret_access_key":"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"},"path":"/laurent"}}'
	@touch $@
t/at10:
	$(EXETEST) ats access_key list --fields=name,id,secret
	@touch $@
t/at11:
	$(EXETEST) ats access_key --id=testkey2 node browse /
	@touch $@
t/at12:
	$(EXETEST) ats access_key --id=testkey2 cluster
	@touch $@
t/at13:
	$(EXETEST) ats access_key --id=testkey2 delete
	@touch $@
t/at14:
	$(EXETEST) ats access_key --id=testkey3 delete
	@touch $@

tats: t/at4 t/at5 t/at6 t/at7 t/at2 t/at1 t/at3 t/at8 t/at9 t/at10 t/at11 t/at12 t/at13 t/at14

t/co1:
	$(EXETEST) config ascp show
	@touch $@
t/co2:
	$(EXETEST) config ascp products list
	@touch $@
t/co3:
	$(EXETEST) config ascp connect list
	@touch $@
t/co4:
	$(EXETEST) config ascp connect id 'Aspera Connect for Windows' info
	@touch $@
t/co5:
	$(EXETEST) config ascp connect id 'Aspera Connect for Windows' links list
	@touch $@
t/co6:
	$(EXETEST) config ascp connect id 'Aspera Connect for Windows' links id 'Windows Installer' download --to-folder=.
	@touch $@
tcon: t/co1 t/co2 t/co3 t/co4 t/co5 t/co6

t/sy1:
	$(EXETEST) node async list
	@touch $@
t/sy2:
	$(EXETEST) node async show --id=1
	$(EXETEST) node async show --id=ALL
	@touch $@
t/sy3:
	$(EXETEST) node async --id=1 counters 
	@touch $@
t/sy4:
	$(EXETEST) node async --id=1 bandwidth 
	@touch $@
t/sy5:
	$(EXETEST) node async --id=1 files 
	@touch $@
tnsync: t/sy1 t/sy2 t/sy3 t/sy4 t/sy5

TEST_CONFIG=sample.conf
t/conf_id_1:
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id conf_name set param value
	@touch $@
t/conf_id_2:
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id conf_name show
	@touch $@
t/conf_id_3:
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id default set shares conf_name
	@touch $@
t/conf_id_4:
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id conf_name delete
	@touch $@
t/conf_id_5:
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id conf_name initialize @json:'{"p1":"v1","p2":"v2"}'
	@touch $@
t/conf_id_6:
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST1) config id conf_name update --p1=v1 --p2=v2
	@touch $@
t/conf_open:
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config open
	@touch $@
t/conf_list:
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config list
	@touch $@
t/conf_over:
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config overview
	@touch $@
t/conf_help:
	$(EXETEST) -h
	@touch $@
t/conf_open_err:
	printf -- "---\nconfig:\n  version: 0" > $(TEST_CONFIG)
	-MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config open
	@touch $@
t/conf_plugins:
	$(EXETEST) config plugins
	@touch $@
t/conf_export:
	$(EXETEST) config export
	@touch $@
HIDE_CLIENT_ID=BMDiAWLP6g
HIDE_CLIENT_SECRET=opkZrJuN-J8anDxPcPA5CFLsY5CopRvLqBeDV24_8KJgarmuYGkI0ha5zNkBLpZ1-edRwzgHZfhisyQltG-xJ-kiZvvxf3Co
SAMPLE_CONFIG_FILE=todelete.txt
t/conf_wizard_org:
	$(EXETEST) conf flush
	$(EXETEST) conf wiz --url=https://sedemo.ibmaspera.com --config-file=$(SAMPLE_CONFIG_FILE) --client-id=$(HIDE_CLIENT_ID) --client-secret=$(HIDE_CLIENT_SECRET) --pkeypath='' --use-generic-client=no --username=laurent.martin.aspera@fr.ibm.com
	$(EXETEST) conf wiz --url=https://sedemo.ibmaspera.com --config-file=$(SAMPLE_CONFIG_FILE) --pkeypath='' --username=laurent.martin.aspera@fr.ibm.com
	cat $(SAMPLE_CONFIG_FILE)
	rm -f $(SAMPLE_CONFIG_FILE)
	@touch $@
t/conf_wizard_gen:
	$(EXETEST) conf flush
	$(EXETEST) conf wiz --url=https://sedemo.ibmaspera.com --config-file=$(SAMPLE_CONFIG_FILE) --pkeypath='' --username=laurent.martin.aspera@fr.ibm.com
	cat $(SAMPLE_CONFIG_FILE)
	rm -f $(SAMPLE_CONFIG_FILE)
	@touch $@
t/conf_genkey:
	$(EXETEST) config genkey $(TEST_FOLDER)/mykey
	@touch $@
t/conf_smtp:
	$(EXETEST) config email_test aspera.user1@gmail.com
	@touch $@
t/conf_pac:
	$(EXETEST) config proxy_check --fpac=file:///./examples/proxy.pac https://eudemo.asperademo.com
	@touch $@
tconf: t/conf_id_1 t/conf_id_2 t/conf_id_3 t/conf_id_4 t/conf_id_5 t/conf_id_6 t/conf_open t/conf_list t/conf_over t/conf_help t/conf_open_err t/conf_plugins t/conf_export t/conf_wizard_org t/conf_wizard_gen t/conf_genkey t/conf_smtp t/conf_pac

t/shar2_1:
	$(EXETEST) shares2 appinfo
	@touch $@
t/shar2_2:
	$(EXETEST) shares2 userinfo
	@touch $@
t/shar2_3:
	$(EXETEST) shares2 repository browse /
	@touch $@
t/shar2_4:
	$(EXETEST) shares2 organization list
	@touch $@
t/shar2_5:
	$(EXETEST) shares2 project list --organization=Sport
	@touch $@
tshares2: t/shar2_1 t/shar2_2 t/shar2_3 t/shar2_4 t/shar2_5

t/prev1:
	$(EXETEST) preview events --once-only=yes --skip-types=office
	@touch $@
t/prev2:
	$(EXETEST) preview scan --skip-types=office --log-level=info
	@touch $@
t/prev3:
	$(EXETEST) preview test ~/Documents/Samples/anatomic-2k/TG18-CH/TG18-CH-2k-01.dcm --log-level=debug png --video=clips
	@touch $@
t/prev4:
	$(EXETEST) preview test ~/'Documents/Samples/YıçşöğüİÇŞÖĞÜ.pdf' --log-level=debug png --video=clips
	@touch $@

tprev: t/prev1 t/prev2 t/prev3

thot:
	rm -fr source_hot
	mkdir source_hot
	-$(EXETEST) server delete /Upload/target_hot
	$(EXETEST) server mkdir /Upload/target_hot
	echo hello > source_hot/newfile
	$(EXETEST) server upload --to-folder=/Upload/target_hot --lock-port=12345 --ts=@json:'{"EX_ascp_args":["--remove-after-transfer","--remove-empty-directories","--exclude-newer-than=-8","--src-base","source_hot"]}' --sources=@args source_hot
	$(EXETEST) server browse /Upload/target_hot
	ls -al source_hot
	sleep 10
	$(EXETEST) server upload --to-folder=/Upload/target_hot --lock-port=12345 --ts=@json:'{"EX_ascp_args":["--remove-after-transfer","--remove-empty-directories","--exclude-newer-than=-8","--src-base","source_hot"]}' --sources=@args source_hot
	$(EXETEST) server browse /Upload/target_hot
	ls -al source_hot
	rm -fr source_hot
	@touch $@
contents:
	mkdir -p contents
t/sync1: contents
	$(EXETEST) sync start --parameters=@json:'{"sessions":[{"name":"test","reset":true,"remote_dir":"/sync_test","local_dir":"contents","host":"10.25.0.8","user":"user1","private_key_path":"/Users/laurent/.ssh/id_rsa"}]}'
	@touch $@
tsync: t/sync1
t:
	mkdir t
t/sdk1:
	ruby -I $(LIBDIR) $(MAINDIR)/examples/transfer.rb
	@touch $@
tsample: t/sdk1
tests: t tshares tfaspex tconsole tnode taoc tfasp tsync torc tcon tnsync tconf tprev tats tsample tshares2

tnagios: t/fx_nagios t/serv_nagios_webapp t/serv_nagios_transfer t/nd_nagios

t/fxgw:
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
