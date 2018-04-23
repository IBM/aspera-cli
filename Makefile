EXENAME=aslmcli
TOOLCONFIGDIR=$(HOME)/.aspera/$(EXENAME)
APIKEY=$(TOOLCONFIGDIR)/filesapikey
BINDIR=./bin
EXETEST=$(BINDIR)/$(EXENAME)
GEMNAME=asperalm
GEMVERSION=$(shell $(EXETEST) --version)
GEMFILE=$(GEMNAME)-$(GEMVERSION).gem
GIT_TAG_VERSION_PREFIX='v_'
GIT_TAG_CURRENT=$(GIT_TAG_VERSION_PREFIX)$(GEMVERSION)

SRCZIPBASE=$(GEMNAME)_src
TODAY=$(shell date +%Y%m%d)
ZIPFILE=$(SRCZIPBASE)_$(TODAY).zip

EXE_NOMAN=$(EXETEST)

all:: gem

test:
	bundle exec rake spec

clean::
	rm -f $(GEMNAME)-*.gem $(SRCZIPBASE)*.zip *.log token.* preview.png 
	rm -f README.pdf README.html README.md aslmcli_commands.txt aslmcli_usage.txt asession_usage.txt $(TEST_CONFIG)
	rm -fr t doc "PKG - "*
	mkdir t
	rm -f 200KB* AsperaConnect-ML*
	gem uninstall -a -x $(GEMNAME)
cleanupgems:
	gem uninstall -a -x $(gem list|cut -f 1 -d' '|egrep -v 'rdoc|psych|rake|openssl|json|io-console|bigdecimal')

changes:
	git log `git describe --tags --abbrev=0`..HEAD --oneline

doc: README.pdf

README.pdf: README.md
	pandoc --number-sections --resource-path=. --toc -o README.html README.md
	wkhtmltopdf toc README.html README.pdf

README.md: README.erb.md aslmcli_commands.txt aslmcli_usage.txt asession_usage.txt
	COMMANDS=aslmcli_commands.txt USAGE=aslmcli_usage.txt ASESSION=asession_usage.txt ASCLI=$(EXETEST) erb README.erb.md > README.md

aslmcli_commands.txt: Makefile
	sed -n -e 's/.*\$$(EXETEST)/aslmcli/p' Makefile|grep -v 'Sales Engineering'|sed -E -e 's/\$$\(SAMPLE_FILE\)/sample_file.bin/g;s/\$$\(NODEDEST\)/sample_dest_folder/g;s/\$$\(TEST_FOLDER\)/sample_dest_folder/g;s/ibmfaspex.asperasoft.com/faspex.mycompany.com/g;s/(")(url|api_key|username|password)(":")[^"]*(")/\1\2\3my_\2_here\4/g;s/--(secret|url|password|username)=[^ ]*/--\1=my_\1_here/g;'|grep -v 'localhost:9443'|sort -u > aslmcli_commands.txt

# depends on all sources, so regenerate always
.PHONY: aslmcli_usage.txt
aslmcli_usage.txt:
	$(EXE_NOMAN) -Cnone -h 2> aslmcli_usage.txt || true

.PHONY: asession_usage.txt
asession_usage.txt:
	$(BINDIR)/asession -h 2> asession_usage.txt || true

$(ZIPFILE): README.md
	rm -f $(SRCZIPBASE)_*.zip
	zip -r $(ZIPFILE) `git ls-files`

$(GEMFILE): README.md
	gem build asperalm.gemspec

gem: $(GEMFILE)

install: $(GEMFILE)
	gem install $(GEMFILE)

togarage: $(ZIPFILE) README.pdf $(GEMFILE)
	$(EXE_NOMAN) aspera --workspace='Sales Engineering' upload '/Laurent Garage SE/RubyCLI' $(ZIPFILE) README.pdf $(GEMFILE)

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
TEST_FOLDER=./test.dir

clean::
	rm -fr $(TEST_FOLDER)
t/sh1:
	$(EXETEST) shares repository browse /
	@touch $@
t/sh2:
	mkdir -p $(TEST_FOLDER)
	$(EXETEST) shares repository upload $(SAMPLE_FILE) --to-folder=/n8-sh1
	$(EXETEST) shares repository download /n8-sh1/200KB.1 --to-folder=$(TEST_FOLDER)
	$(EXETEST) shares repository delete /n8-sh1/200KB.1
	@rm -f 200KB.1
	@touch $@
tshares: t/sh1 t/sh2

t/fp1:
	mkdir -p $(TEST_FOLDER)
	$(EXETEST) server browse /
	$(EXETEST) server upload $(SAMPLE_FILE) --to-folder=/Upload
	$(EXETEST) server download /Upload/200KB.1 --to-folder=$(TEST_FOLDER)
	$(EXETEST) server cp /Upload/200KB.1 /Upload/200KB.2
	$(EXETEST) server mv /Upload/200KB.2 /Upload/to.delete
	$(EXETEST) server delete /Upload/to.delete
	$(EXETEST) server md5sum /Upload/200KB.1
	$(EXETEST) server delete /Upload/200KB.1
	@touch $@
t/fp2:
	$(EXETEST) server mkdir /Upload/123
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
	$(EXETEST) faspex package send $(SAMPLE_FILE) --note="my note" --title="my title" --recipient="laurent.martin.aspera@fr.ibm.com"
	@touch $@
t/fx3:
	$(EXETEST) faspex package recv $$($(EXETEST) faspex package list --fields=delivery_id --format=csv --box=sent|tail -n 1) --box=sent
	@touch $@
t/fx4:
	@echo $(EXETEST) faspex recv_publink 'https://ibmfaspex.asperasoft.com/aspera/faspex/external_deliveries/78780?passcode=a003aaf2f53e3869126b908525084db6bebc7031' --insecure=yes
	@touch $@
tfaspex: t/fx1 t/fx2 t/fx3 t/fx4

t/cons1:
	$(EXETEST) console transfer current list 
	@touch $@
tconsole: t/cons1

#NODEDEST=/home/faspex/docroot
NODEDEST=/
t/nd1:
	$(EXETEST) node browse /
	@touch $@
t/nd2:
	mkdir -p $(TEST_FOLDER)
	$(EXETEST) node upload $(SAMPLE_FILE) --to-folder=$(NODEDEST)
	$(EXETEST) node download $(NODEDEST)200KB.1 --to-folder=$(TEST_FOLDER)
	$(EXETEST) node delete $(NODEDEST)200KB.1
	rm -f $(TEST_FOLDER)/200KB.1
	@touch $@
t/nd3:
	$(EXETEST) --no-default node --url=https://10.25.0.4:9092 --username=node_xferuser --password=Aspera123_ --insecure=yes upload --to-folder=/ 500M.dat --ts=@json:'{"precalculate_job_size":true}' --transfer=node --transfer-node=@json:'{"url":"https://10.25.0.8:9092","username":"node_xferuser","password":"Aspera123_"}' 
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
tnode: t/nd1 t/nd2 t/nd3 t/nd4 t/nd5

t/fs1:
	$(EXETEST) aspera files browse /
	@touch $@
t/fs2:
	$(EXETEST) aspera files upload $(SAMPLE_FILE) --to-folder=/
	@touch $@
t/fs3:
	mkdir -p $(TEST_FOLDER)
	$(EXETEST) aspera files download /200KB.1 --to-folder=$(TEST_FOLDER) --transfer=connect
	rm -f 200KB.1
	@touch $@
t/fs3b:
	mkdir -p $(TEST_FOLDER)
	$(EXETEST) aspera files download /200KB.1 --to-folder=$(TEST_FOLDER) --download=node
	rm -f 200KB.1
	@touch $@
t/fs4:
	$(EXETEST) aspera packages send $(SAMPLE_FILE) --note="my note" --title="my title" --recipient="laurent.martin.aspera@fr.ibm.com"
	@touch $@
t/fs5:
	$(EXETEST) aspera packages list
	@touch $@
t/fs6:
	$(EXETEST) aspera packages recv BJKyUFHhew
	@touch $@
t/fs7:
	$(EXETEST) aspera admin events
	@touch $@
t/fs8:
	$(EXETEST) aspera admin resource workspace list
	@touch $@
t/fs9:
	$(EXETEST) aspera admin resource node --id=7897 do browse / --secret=I5DiMd6oOzMeWP2F2QlOl-VFpARPY8pEimE1xOEXQ7xP_1Gt1mKLeoQ93oEj-WoltJQBJpmfI2jroSCFqFQpdg
	@touch $@

tfiles: t/fs1 t/fs2 t/fs3 t/fs3b t/fs4 t/fs5 t/fs6 t/fs7 t/fs8 t/fs9

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

t/at1a:
	$(EXETEST) ats cluster list
	@touch $@
t/at1b:
	$(EXETEST) ats cluster clouds
	@touch $@
t/at2:
	$(EXETEST) ats cluster show --cloud=aws --region=eu-west-1 
	@touch $@
t/at3:
	$(EXETEST) ats cluster show --id=1f412ae7-869a-445c-9c05-02ad16813be2
	@touch $@
t/at4:
	$(EXETEST) ats account subscriptions
	@touch $@
t/at5:
	$(EXETEST) ats account cache list
	@touch $@
t/at6:
	$(EXETEST) ats account list
	@touch $@
t/at7:
	$(EXETEST) ats key create --cloud=softlayer --region=ams --params=@json:'{"id":"testkey2","name":"laurent key","storage":{"type":"softlayer_swift","container":"laurent","credentials":{"api_key":"e5d032e026e0b0a16e890a3d44d11fd1471217b6262e83c7f60529f1ff4b27de","username":"IBMOS303446-9:laurentmartin"},"path":"/"}}'
	@touch $@
t/at8:
	$(EXETEST) ats key create --cloud=aws --region=eu-west-1 --params=@json:'{"id":"testkey3","name":"laurent key AWS","storage":{"type":"aws_s3","bucket":"sedemo-ireland","credentials":{"access_key_id":"AKIAIDSWKOSIM7XUVCJA","secret_access_key":"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"},"path":"/laurent"}}'
	@touch $@
t/at9:
	$(EXETEST) ats key list --fields=name,id,secret
	@touch $@
t/at10:
	$(EXETEST) ats key --id=testkey2 node browse /
	@touch $@
t/at11:
	$(EXETEST) ats key --id=testkey2 cluster
	@touch $@
t/at12:
	$(EXETEST) ats key --id=testkey2 delete
	@touch $@
t/at13:
	$(EXETEST) ats key --id=testkey3 delete
	@touch $@

tats: t/at1a t/at1b t/at2 t/at3 t/at4 t/at5 t/at6 t/at7 t/at8 t/at9 t/at10 t/at11 t/at12 t/at13

t/co1:
	$(EXETEST) client location
	@touch $@
t/co2:
	$(EXETEST) client connect list
	@touch $@
t/co3:
	$(EXETEST) client connect id 'Aspera Connect for Windows' info
	@touch $@
t/co4:
	$(EXETEST) client connect id 'Aspera Connect for Windows' links list
	@touch $@
t/co5:
	$(EXETEST) client connect id 'Aspera Connect for Windows' links id 'Windows Installer' download --to-folder=.
	@touch $@
tcon: t/co1 t/co2 t/co3 t/co4 t/co5

t/sy1:
	$(EXETEST) node async list
	@touch $@
t/sy2:
	$(EXETEST) node async --id=1 summary 
	@touch $@
t/sy3:
	$(EXETEST) node async --id=1 counters 
	@touch $@
tsync: t/sy1 t/sy2 t/sy3

TEST_CONFIG=sample.conf
t/conf1:
	ASLMCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id conf_name set param value
	@touch $@
t/conf2:
	ASLMCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id conf_name show
	@touch $@
t/conf3:
	ASLMCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config list
	@touch $@
t/conf4:
	ASLMCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config overview
	@touch $@
t/conf5:
	ASLMCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id default set shares conf_name
	@touch $@
t/conf6:
	ASLMCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id conf_name delete
	@touch $@
t/conf7:
	ASLMCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id conf_name initialize @json:'{"p1":"v1","p2":"v2"}'
	@touch $@
t/conf8:
	ASLMCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id conf_name update --p1=v1 --p2=v2
	@touch $@
t/conf9:
	ASLMCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config open
	@touch $@

tconf: t/conf1 t/conf2 t/conf3 t/conf4 t/conf5 t/conf6 t/conf7 t/conf8 t/conf9

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
	$(EXETEST) preview events --skip-types=office
	@touch $@
t/prev2:
	$(EXETEST) preview scan --skip-types=office --log-level=info
	@touch $@
t/prev3:
	$(EXETEST) preview test ~/Documents/Samples/anatomic-2k/TG18-CH/TG18-CH-2k-01.dcm --log-level=debug png --video=clips

tprev: t/prev1 t/prev2 t/prev3

t:
	mkdir t

tests: t tshares tfaspex tconsole tnode tfiles tfasp torc tats tcon tsync tconf tshares2 tprev

t/fxgw:
	$(EXETEST) faspex package send --load-params=reset --url=https://localhost:9443/aspera/faspex --username=unused --password=unused --insecure=yes --note="my note" --title="my title" --recipient="laurent.martin.aspera@fr.ibm.com" ~/200KB.1
	@touch $@

NODE_USER=node_admin
NODE_PASS=Aspera123_
setupprev:
	asconfigurator -x "user;user_name,xfer;file_restriction,|*;token_encryption_key,1234"
	asconfigurator -x "server;activity_logging,true;activity_event_logging,true"
	$(EXE_NOMAN) node access_key id testkey delete --no-default --url=https://localhost:9092 --username=node_xfer --password=Aspera123_
	$(EXE_NOMAN) node access_key create @json:'{"id":"testkey","name":"the test key","secret":"secret","storage":{"type":"local", "path":"/Users/xfer/docroot"}}' --no-default --url=https://localhost:9092 --username=node_xfer --password=Aspera123_ 
	$(EXE_NOMAN) config id test_preview update --url=https://localhost:9092 --username=testkey --password=secret
	$(EXE_NOMAN) config id default set preview test_preview

# ruby -e 'require "yaml";YAML.load_file("lib/asperalm/preview_generator_formats.yml").each {|k,v|puts v};'|while read x;do touch /Users/xfer/docroot/sample${x};done
