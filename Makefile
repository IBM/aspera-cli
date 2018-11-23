EXENAME=mlia
TOOLCONFIGDIR=$(HOME)/.aspera/$(EXENAME)
APIKEY=$(TOOLCONFIGDIR)/filesapikey
BINDIR=./bin
OUT_FOLDER=out
TEST_FOLDER=test.dir
EXETEST=$(BINDIR)/$(EXENAME)
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

all:: gem

test:
	bundle exec rake spec

clean::
	rm -f $(GEMNAME)-*.gem $(SRCZIPBASE)*.zip *.log token.* preview.png 
	rm -f README.pdf README.html README.md $(INCL_COMMANDS) $(INCL_USAGE) $(INCL_ASESSION) $(TEST_CONFIG)
	rm -fr contents t doc out "PKG - "*
	mkdir t out
	rm -f 200KB* *AsperaConnect-ML* sample.conf*
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
	sed -n -e 's/.*\$$(EXETEST)/$(EXENAME)/p' Makefile|grep -v 'Sales Engineering'|sed -E -e 's/\$$\(SAMPLE_FILE\)/sample_file.bin/g;s/\$$\(NODEDEST\)/sample_dest_folder/g;s/\$$\(TEST_FOLDER\)/sample_dest_folder/g;s/ibmfaspex.asperasoft.com/faspex.mycompany.com/g;s/(")(url|api_key|username|password|access_key_id|secret_access_key|pass)(":")[^"]*(")/\1\2\3my_\2_here\4/g;s/--(secret|url|password|username)=[^ ]*/--\1=my_\1_here/g;s/Aspera123_/_my_pass_/g'|grep -v 'localhost:9443'|sort -u > $(INCL_COMMANDS)

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
t/sh1:
	$(EXETEST) shares repository browse /
	@touch $@
t/sh2:
	mkdir -p $(TEST_FOLDER)
	$(EXETEST) shares repository upload --to-folder=/$(TEST_SHARE) --sources=@args $(SAMPLE_FILE)
	$(EXETEST) shares repository download --to-folder=$(TEST_FOLDER) --sources=@args /$(TEST_SHARE)/200KB.1
	$(EXETEST) shares repository delete /$(TEST_SHARE)/200KB.1
	@rm -f 200KB.1
	@touch $@
tshares: t/sh1 t/sh2

t/fp1:
	mkdir -p $(TEST_FOLDER)
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

tfasp: t/fp1 t/fp2 t/fp3 t/fp4

t/fx1:
	$(EXETEST) faspex package list
	@touch $@
t/fx2:
	$(EXETEST) faspex package send --delivery-info=@json:'{"title":"my title","recipients":["laurent.martin.aspera@fr.ibm.com"]}' --sources=@args $(SAMPLE_FILE) 
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
tfaspex: t/fx1 t/fx2 t/fx3 t/fx4 t/fx5 t/fx6

t/cons1:
	$(EXETEST) console transfer current list 
	@touch $@
tconsole: t/cons1

#NODEDEST=/home/faspex/docroot
NODEDEST=/
t/nd1:
	$(EXETEST) node info
	$(EXETEST) node browse / -r
	@touch $@
t/nd2:
	mkdir -p $(TEST_FOLDER)
	$(EXETEST) node upload --to-folder=$(NODEDEST) --sources=@args $(SAMPLE_FILE)
	$(EXETEST) node download --to-folder=$(TEST_FOLDER) --sources=@args $(NODEDEST)200KB.1
	$(EXETEST) node delete $(NODEDEST)200KB.1
	rm -f $(TEST_FOLDER)/200KB.1
	@touch $@
t/nd3:
	$(EXETEST) --no-default node --url=https://10.25.0.4:9092 --username=node_xferuser --password=Aspera123_ --insecure=yes upload --to-folder=/ --sources=@ts --ts=@json:'{"paths":[{"source":"500M.dat"}],"precalculate_job_size":true}' --transfer=node --transfer-info=@json:'{"url":"https://10.25.0.8:9092","username":"node_xferuser","password":"Aspera123_"}' 
	$(EXETEST) --no-default node --url=https://10.25.0.4:9092 --username=node_xferuser --password=Aspera123_ --insecure=yes delete /500M.dat
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
	$(EXETEST) -Pnode_lmdk08 --url=https://localhost:9092 --username=node_xfer node acc create --value=@json:'{"id":"aoc_1","secret":"Aspera123_","storage":{"type":"local","path":"/"}}'
	sleep 2&&$(EXETEST) -Pnode_lmdk08 --url=https://localhost:9092 --username=node_xfer node acc delete --id=aoc_1
	@touch $@
t/nd6:
	$(EXETEST) node transfer list
	@touch $@
tnode: t/nd1 t/nd2 t/nd3 t/nd4 t/nd5 t/nd6

t/aocf1:
	$(EXETEST) aspera files browse /
	@touch $@
t/aocf2:
	$(EXETEST) aspera files upload --to-folder=/ $(SAMPLE_FILE)
	@touch $@
t/aocf3:
	mkdir -p $(TEST_FOLDER)
	$(EXETEST) aspera files download --to-folder=$(TEST_FOLDER) --transfer=connect --sources=@args /200KB.1
	rm -f 200KB.1
	@touch $@
t/aocf4:
	mkdir -p $(TEST_FOLDER)
	$(EXETEST) aspera files http_node_download --to-folder=$(TEST_FOLDER) --sources=@args /200KB.1
	rm -f 200KB.1
	@touch $@
t/aocf5:
	$(EXETEST) aspera files transfer --from-folder=/ --to-folder=xxx --sources=@args 200KB.1
	@touch $@
t/aocp1:
	$(EXETEST) aspera packages send --value=@json:'{"name":"my title","note":"my note","recipients":["laurent.martin.aspera@fr.ibm.com"]}' --sources=@args $(SAMPLE_FILE)
	$(EXETEST) aspera packages send --value=@json:'{"name":"my title","recipients":["laurent.martin.l+external@gmail.com"]}' --new-user-option=@json:'{"package_contact":true}' --sources=@args $(SAMPLE_FILE)
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
t/aoc7:
	$(EXETEST) aspera admin res node v3 events --secret='AML3clHuHwDArShhcQNVvWGHgU9dtnpgLzRCPsBr7H5JdhrFU2oRs69_tJTEYE-hXDVSW-vQ3-klRnJvxrTkxQ'
	@touch $@
t/aoc8:
	$(EXETEST) aspera admin resource workspace list
	@touch $@
t/aoc9:
	$(EXETEST) aspera admin resource node --name=eudemo --secret=Aspera123_ v3 events
	$(EXETEST) aspera admin resource node --name=eudemo --secret=Aspera123_ v4 browse /
	@touch $@
t/aoc10:
	$(EXETEST) aspera admin resource node --name=eudemo --secret=Aspera123_ v4 mkdir /folder1
	@touch $@
t/aoc11:
	$(EXETEST) aspera admin resource node --name=eudemo --secret=Aspera123_ v4 access_key create --value=@json:'{"id":"testsub1","storage":{"path":"/folder1"}}'
	@touch $@
t/aoc12:
	$(EXETEST) aspera admin resource node --name=eudemo --secret=Aspera123_ v4 access_key delete --eid=testsub1
	@touch $@
t/aoc13:
	$(EXETEST) aspera admin resource node --name=eudemo --secret=Aspera123_ v4 delete /folder1
	@touch $@
t/aoc14:
	$(EXETEST) aspera admin resource workspace_membership list --fields=ALL --query=@json:'{"page":1,"per_page":50,"embed":"member","inherited":false,"workspace_id":11363,"sort":"name"}'
	@touch $@
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

tfsat: t/aocat4 t/aocat5 t/aocat6 t/aocat7 t/aocat8 t/aocat9 t/aocat10 t/aocat11 t/aocat13 t/aocat14
tfiles: t/aocf1 t/aocf2 t/aocf3 t/aocf4 t/aocf5 t/aocp1 t/aocp2 t/aocp3 t/aocp4 t/aoc7 t/aoc8 t/aoc9 t/aoc10 t/aoc11 t/aoc12 t/aoc13 t/aoc14 tfsat

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

t/at1:
	$(EXETEST) ats credential subscriptions
	@touch $@
t/at2:
	$(EXETEST) ats credential cache list
	@touch $@
t/at3:
	$(EXETEST) ats credential list
	@touch $@
t/at3b:
	$(EXETEST) ats credential info
	@touch $@
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

tats: t/at1 t/at2 t/at3 t/at3b t/at4 t/at5 t/at6 t/at7 t/at8 t/at9 t/at10 t/at11 t/at12 t/at13 t/at14

t/co1:
	$(EXETEST) client current
	@touch $@
t/co2:
	$(EXETEST) client available
	@touch $@
t/co3:
	$(EXETEST) client connect list
	@touch $@
t/co4:
	$(EXETEST) client connect id 'Aspera Connect for Windows' info
	@touch $@
t/co5:
	$(EXETEST) client connect id 'Aspera Connect for Windows' links list
	@touch $@
t/co6:
	$(EXETEST) client connect id 'Aspera Connect for Windows' links id 'Windows Installer' download --to-folder=.
	@touch $@
tcon: t/co1 t/co2 t/co3 t/co4 t/co5 t/co6

t/sy1:
	$(EXETEST) node async list
	@touch $@
t/sy2:
	$(EXETEST) node async --id=1 summary 
	@touch $@
t/sy3:
	$(EXETEST) node async --id=1 counters 
	@touch $@
tnsync: t/sy1 t/sy2 t/sy3

TEST_CONFIG=sample.conf
t/conf1:
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id conf_name set param value
	@touch $@
t/conf2:
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id conf_name show
	@touch $@
t/conf3:
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config list
	@touch $@
t/conf4:
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config overview
	@touch $@
t/conf5:
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id default set shares conf_name
	@touch $@
t/conf6:
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id conf_name delete
	@touch $@
t/conf7:
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id conf_name initialize @json:'{"p1":"v1","p2":"v2"}'
	@touch $@
t/conf8:
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id conf_name update --p1=v1 --p2=v2
	@touch $@
t/conf9:
	MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config open
	@touch $@
t/conf10:
	$(EXETEST) -h
	@touch $@
t/conf11:
	printf -- "---\nconfig:\n  version: 0" > $(TEST_CONFIG)
	-MLIA_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config open
	@touch $@

tconf: t/conf1 t/conf2 t/conf3 t/conf4 t/conf5 t/conf6 t/conf7 t/conf8 t/conf9 t/conf10 t/conf11

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

tests: t tshares tfaspex tconsole tnode tfiles tfasp tsync torc tats tcon tnsync tconf tprev tshares2

t/fxgw:
	$(EXETEST) aspera faspex
	@touch $@

NODE_USER=node_admin
NODE_PASS=Aspera123_
setupprev:
	asconfigurator -x "user;user_name,xfer;file_restriction,|*;token_encryption_key,1234"
	asconfigurator -x "server;activity_logging,true;activity_event_logging,true"
	sudo asnodeadmin --reload
	-$(EXE_NOMAN) node access_key --id=testkey delete --no-default --url=https://localhost:9092 --username=node_xfer --password=Aspera123_
	$(EXE_NOMAN) node access_key create --value=@json:'{"id":"testkey","name":"the test key","secret":"secret","storage":{"type":"local", "path":"/Users/xfer/docroot"}}' --no-default --url=https://localhost:9092 --username=node_xfer --password=Aspera123_ 
	$(EXE_NOMAN) config id test_preview update --url=https://localhost:9092 --username=testkey --password=secret
	$(EXE_NOMAN) config id default set preview test_preview

# ruby -e 'require "yaml";YAML.load_file("lib/asperalm/preview_generator_formats.yml").each {|k,v|puts v};'|while read x;do touch /Users/xfer/docroot/sample${x};done

preparelocal:
	sudo asnodeadmin -a -u node_xfer -p Aspera123_ -x xfer
	sudo asconfigurator -x "user;user_name,xfer;file_restriction,|*;absolute,"
	sudo asnodeadmin --reload
