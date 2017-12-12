GEMNAME=asperalm
GEMVERSION=$(shell ruby -e 'require "./lib/asperalm/version.rb";puts Asperalm::VERSION')
GEMFILE=$(GEMNAME)-$(GEMVERSION).gem
EXENAME=aslmcli
TOOLCONFIGDIR=$(HOME)/.aspera/$(EXENAME)
APIKEY=$(TOOLCONFIGDIR)/filesapikey
BINDIR=./bin
EXETEST=$(BINDIR)/$(EXENAME)
GIT_TAG_VERSION_PREFIX='v_'
GIT_TAG_CURRENT=$(GIT_TAG_VERSION_PREFIX)$(GEMVERSION)

SRCZIPBASE=$(GEMNAME)_src
TODAY=$(shell date +%Y%m%d)
ZIPFILE=$(SRCZIPBASE)_$(TODAY).zip

all:: clean pack install

test:
	bundle exec rake spec

clean::
	rm -f $(GEMNAME)-*.gem $(SRCZIPBASE)*.zip *.log token.* README.pdf README.html README.md sample_commands.txt sample_usage.txt $(TEST_CONFIG)
	rm -fr doc "PKG - "*
	rm -f 200KB* AsperaConnect-ML*
	gem uninstall -a -x $(GEMNAME)
cleanupgems:
	gem uninstall -a -x $(gem list|cut -f 1 -d' '|egrep -v 'rdoc|psych|rake|openssl|json|io-console|bigdecimal')
pack: $(ZIPFILE)

doc: README.pdf

README.pdf: README.md
	pandoc -o README.html README.md
	wkhtmltopdf README.html README.pdf

README.md: README.erb.md sample_commands.txt sample_usage.txt
	COMMANDS=sample_commands.txt USAGE=sample_usage.txt erb README.erb.md > README.md

sample_commands.txt: Makefile
	sed -n -e 's/.*\$$(EXETEST)/aslmcli/p' Makefile|grep -v 'Sales Engineering'|sed -E -e 's/\$$\(SAMPLE_FILE\)/sample_file.bin/g;s/\$$\(NODEDEST\)/sample_dest_folder/g;s/\$$\(TEST_FOLDER\)/sample_dest_folder/g;s/ibmfaspex.asperasoft.com/faspex.mycompany.com/g;s/(")(url|api_key|username|password)(":")[^"]*(")/\1\2\3my_\2_here\4/g;s/--(secret|url|password|username)=[^ ]*/--\1=my_\1_here/g;'|grep -v 'localhost:9443' > sample_commands.txt

# depends on all sources, so regenerate always
.PHONY: sample_usage.txt
sample_usage.txt:
	$(EXETEST) -Cnone -h 2> sample_usage.txt || true

$(ZIPFILE): README.md
	rm -f $(SRCZIPBASE)_*.zip
	zip -r $(ZIPFILE) `git ls-files`

$(GEMFILE):
	gem build asperalm.gemspec

gem: $(GEMFILE)

install: $(GEMFILE)
	gem install $(GEMFILE)

togarage: $(ZIPFILE) README.pdf $(GEMFILE)
	$(EXETEST) files --workspace='Sales Engineering' upload '/Laurent Garage SE/RubyCLI' $(ZIPFILE) README.pdf $(GEMFILE)

# create a private/public key pair
# note that the key can also be generated with: ssh-keygen -t rsa -f data/myid -N ''
# amd the pub key can be extracted with: openssl rsa -in data/myid -pubout -out data/myid.pub.pem
$(APIKEY):
	mkdir -p $(TOOLCONFIGDIR)
	openssl genrsa -passout pass:dummypassword -out $(APIKEY).protected 2048
	openssl rsa -passin pass:dummypassword -in $(APIKEY).protected -out $(APIKEY)
	rm -f $(APIKEY).protected

setkey: $(APIKEY)
	$(EXETEST) files admin set_client_key ERuzXGuPA @file:$(APIKEY)

yank:
	gem yank asperalm -v $(GEMVERSION)

gempush:
	git tag -a $(GIT_TAG_CURRENT) -m "gem version $(GEMVERSION) pushed"
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

$(TEST_FOLDER):
	mkdir -p $(TEST_FOLDER)
clean::
	rm -fr $(TEST_FOLDER)
tsh1:
	$(EXETEST) shares repository browse / --insecure=yes
tsh2:
	$(EXETEST) shares repository upload $(SAMPLE_FILE) --to-folder=/n8-sh1 --insecure=yes
tsh3: $(TEST_FOLDER)
	$(EXETEST) shares repository download /n8-sh1/200KB.1 --to-folder=$(TEST_FOLDER) --insecure=yes
	rm -f 200KB.1
	$(EXETEST) shares repository delete /n8-sh1/200KB.1 --insecure=yes
tshares: tsh1 tsh2 tsh3

tfp1: $(TEST_FOLDER)
	$(EXETEST) server browse /
	$(EXETEST) server upload $(SAMPLE_FILE) --to-folder=/Upload
	$(EXETEST) server download /Upload/200KB.1 --to-folder=$(TEST_FOLDER)
	$(EXETEST) server cp /Upload/200KB.1 /Upload/200KB.2
	$(EXETEST) server mv /Upload/200KB.2 /Upload/to.delete
	$(EXETEST) server delete /Upload/to.delete
	$(EXETEST) server md5sum /Upload/200KB.1
	$(EXETEST) server delete /Upload/200KB.1
tfp2:
	$(EXETEST) server mkdir /Upload/123
	$(EXETEST) server rm /Upload/123
tfp3:
	$(EXETEST) server info
	$(EXETEST) server du /
	$(EXETEST) server df
tfp4:
	$(BINDIR)/asfasp --ts=@json:'{"remote_host":"demo.asperasoft.com","remote_user":"asperaweb","ssh_port":33001,"password":"demoaspera","direction":"receive","destination_root":"./test.dir","paths":[{"source":"/aspera-test-dir-tiny/200KB.1"}]}'

tfasp: tfp1 tfp2 tfp3 tfp4

tfx1:
	$(EXETEST) faspex package list --insecure=yes
tfx2:
	$(EXETEST) faspex package send $(SAMPLE_FILE) --insecure=yes --note="my note" --title="my title" --recipient="laurent@asperasoft.com"
tfx3:
	$(EXETEST) faspex package recv $$($(EXETEST) faspex package list --fields=delivery_id --format=csv --box=sent|tail -n 1) --box=sent
tfx4:
	@echo $(EXETEST) faspex recv_publink 'https://ibmfaspex.asperasoft.com/aspera/faspex/external_deliveries/78780?passcode=a003aaf2f53e3869126b908525084db6bebc7031' --insecure=yes
tfaspex: tfx1 tfx2 tfx3 tfx4

tconsole:
	$(EXETEST) console transfers list  --insecure=yes
NODEDEST=/home/faspex/docroot
NODEDEST=/
tnd1:
	$(EXETEST) node browse / --insecure=yes
tnd2:
	$(EXETEST) node upload $(SAMPLE_FILE) --to-folder=$(NODEDEST) --insecure=yes
tnd3: $(TEST_FOLDER)
	$(EXETEST) node download $(NODEDEST)/200KB.1 --to-folder=$(TEST_FOLDER) --insecure=yes
	$(EXETEST) node delete $(NODEDEST)/200KB.1 --insecure=yes
	rm -f $(TEST_FOLDER)/200KB.1
tnd4:
	$(EXETEST) -N node --url=https://10.25.0.4:9092 --username=node_xferuser --password=Aspera123_ upload --to-folder=/ 500M.dat --ts=@json:'{"precalculate_job_size":true}' --transfer=node --transfer-node=@json:'{"url":"https://10.25.0.8:9092","username":"node_xferuser","password":"Aspera123_"}' 
	$(EXETEST) -N node --url=https://10.25.0.4:9092 --username=node_xferuser --password=Aspera123_ delete /500M.dat
tnode: tnd1 tnd2 tnd3 tnd4

tfs1:
	$(EXETEST) files repo browse /
tfs2:
	$(EXETEST) files repo upload $(SAMPLE_FILE) --to-folder=/
tfs3: $(TEST_FOLDER)
	$(EXETEST) files repo download /200KB.1 --to-folder=$(TEST_FOLDER) --transfer=connect
	rm -f 200KB.1
tfs3b: $(TEST_FOLDER)
	$(EXETEST) files repo download /200KB.1 --to-folder=$(TEST_FOLDER) --download=node
	rm -f 200KB.1
tfs4:
	$(EXETEST) files package send $(SAMPLE_FILE) --note="my note" --title="my title" --recipient="laurent@asperasoft.com"
tfs5:
	$(EXETEST) files package list
tfs6:
	$(EXETEST) files package recv VleoMSrlA
tfs7:
	$(EXETEST) files admin events
tfs8:
	$(EXETEST) files admin resource workspace list
tfs9:
	$(EXETEST) files admin resource node id 5560 do browse / --secret=Aspera123_

tfiles: tfs1 tfs2 tfs3 tfs3b tfs4 tfs5 tfs6 tfs7 tfs8 tfs9

to1:
	$(EXETEST) orchestrator info

to2:
	$(EXETEST) orchestrator workflow list

to3:
	$(EXETEST) orchestrator workflow status

to4:
	$(EXETEST) orchestrator workflow id 10 inputs

to5:
	$(EXETEST) orchestrator workflow id 10 status

to6:
	$(EXETEST) orchestrator workflow id 10 start --params=@json:'{"Param":"laurent"}'

to7:
	$(EXETEST) orchestrator workflow id 10 start --params=@json:'{"Param":"laurent"}' --result=ResultStep:Complete_status_message

to8:
	$(EXETEST) orchestrator plugins
to9:
	$(EXETEST) orchestrator processes

torc: to1 to2 to3 to4 to5 to6 to7 to8 to9

tat1a:
	$(EXETEST) ats server list provisioned
tat1b:
	$(EXETEST) ats server list clouds
tat2:
	$(EXETEST) ats server list instance --cloud=aws --region=eu-west-1 
tat3:
	$(EXETEST) ats server id gk7f5356-f4ea-kj83-ddfW-7da4ed99f8eb
tat4:
	$(EXETEST) ats subscriptions
tat5:
	$(EXETEST) ats api_key repository list
tat6:
	$(EXETEST) ats api_key list
tat7:
	$(EXETEST) ats access_key create --cloud=softlayer --region=ams --params=@json:'{"id":"testkey2","name":"laurent key","storage":{"type":"softlayer_swift","container":"laurent","credentials":{"api_key":"e5d032e026e0b0a16e890a3d44d11fd1471217b6262e83c7f60529f1ff4b27de","username":"IBMOS303446-9:laurentmartin"},"path":"/"}}'
tat8:
	$(EXETEST) ats access_key create --cloud=aws --region=eu-west-1 --params=@json:'{"id":"testkey3","name":"laurent key AWS","storage":{"type":"aws_s3","bucket":"sedemo-ireland","credentials":{"access_key_id":"AKIAIDSWKOSIM7XUVCJA","secret_access_key":"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"},"path":"/laurent"}}'
tat9:
	$(EXETEST) ats access_key list --fields=name,id,secret
tat10:
	$(EXETEST) ats access_key id testkey2 node browse /
tat11:
	$(EXETEST) ats access_key id testkey2 server
tat12:
	$(EXETEST) ats access_key id testkey2 delete
tat13:
	$(EXETEST) ats access_key id testkey3 delete

tats: tat1a tat1b tat2 tat3 tat4 tat5 tat6 tat7 tat8 tat9 tat10 tat11 tat12 tat13

tco1:
	$(EXETEST) client location

tco2:
	$(EXETEST) client connect list

tco3:
	$(EXETEST) client connect id 'Aspera Connect for Windows' info

tco4:
	$(EXETEST) client connect id 'Aspera Connect for Windows' links list

tco5:
	$(EXETEST) client connect id 'Aspera Connect for Windows' links id 'Windows Installer' download --to-folder=.

tcon: tco1 tco2 tco3 tco4 tco5

tsy1:
	$(EXETEST) node async list
tsy2:
	$(EXETEST) node async id 1 summary 
tsy3:
	$(EXETEST) node async id 1 counters 
tsync: tsy1 tsy2 tsy3

TEST_CONFIG=sample.conf
tconf1:
	ASLMCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id conf_name set param value
tconf2:
	ASLMCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id conf_name show
tconf3:
	ASLMCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config list
tconf4:
	ASLMCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config overview
tconf5:
	ASLMCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id default set shares conf_name
tconf6:
	ASLMCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id conf_name delete
tconf7:
	ASLMCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETEST) config id conf_name initialize @json:'{"p1":"v1","p2":"v2"}'

tconf: tconf1 tconf2 tconf3 tconf4 tconf5 tconf6 tconf7

tshar2_1:
	$(EXETEST) shares2 appinfo
tshar2_2:
	$(EXETEST) shares2 userinfo
tshar2_3:
	$(EXETEST) shares2 repository browse /
tshar2_4:
	$(EXETEST) shares2 organization list
tshar2_5:
	$(EXETEST) shares2 project list --organization=Sport

tshares2: tshar2_1 tshar2_2 tshar2_3 tshar2_4 tshar2_5

tests: tshares tfaspex tconsole tnode tfiles tfasp torc tats tcon tsync tconf tshares2

tfxgw:
	$(EXETEST) faspex package send --load-params=reset --url=https://localhost:9443/aspera/faspex --username=unused --password=unused --insecure=yes --note="my note" --title="my title" --recipient="laurent@asperasoft.com" ~/200KB.1


tprev:
	$(EXETEST) preview --url=https://localhost:9092 --username=testkey --password=secret
NODE_USER=node_admin
NODE_PASS=Aspera123_
setupprev:
	$(EXETEST) -N --url=https://localhost:9092 --username=node_xfer --password=Aspera123_ node access_key id testkey delete
	$(EXETEST) -N --url=https://localhost:9092 --username=node_xfer --password=Aspera123_ node access_key create @json:'{"id":"testkey","name":"the test key","secret":"secret","storage":{"type":"local", "path":"/Users/xfer/docroot"}}'
	$(EXETEST) -N --url=https://localhost:9092 --username=testkey --password=secret config id test_preview update
	$(EXETEST) config id default set preview test_preview
	$(EXETEST) preview events

