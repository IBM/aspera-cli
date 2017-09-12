GEMNAME=asperalm
GEMVERSION=$(shell ruby -e 'require "./lib/asperalm/version.rb";puts Asperalm::VERSION')
GEMFILE=$(GEMNAME)-$(GEMVERSION).gem
CLINAME=aslmcli
TOOLCONFIGDIR=$(HOME)/.aspera/$(CLINAME)
APIKEY=$(TOOLCONFIGDIR)/filesapikey
ASCLI=./bin/$(CLINAME)

SRCZIPBASE=$(GEMNAME)_src
TODAY=$(shell date +%Y%m%d)
ZIPFILE=$(SRCZIPBASE)_$(TODAY).zip

all:: clean pack install

test:
	bundle exec rake spec

clean::
	rm -f $(GEMNAME)-*.gem $(SRCZIPBASE)*.zip *.log token.* README.pdf README.html
	rm -fr doc
	gem uninstall -a -x $(GEMNAME)
cleanupgems:
	gem uninstall -a -x $(gem list|cut -f 1 -d' '|egrep -v 'rdoc|psych|rake|openssl|json|io-console|bigdecimal')
pack: $(ZIPFILE)

doc: README.pdf

README.pdf: README.md
	pandoc -o README.html README.md
	wkhtmltopdf README.html README.pdf

$(ZIPFILE):
	rm -f $(SRCZIPBASE)_*.zip
	zip -r $(ZIPFILE) `git ls-files`

$(GEMFILE):
	gem build asperalm.gemspec

gem: $(GEMFILE)

install: $(GEMFILE)
	gem install $(GEMFILE)

togarage: $(ZIPFILE) README.pdf $(GEMFILE)
	$(ASCLI) files --workspace='Sales Engineering' upload '/Laurent Garage SE/RubyCLI' $(ZIPFILE) README.pdf $(GEMFILE)

# create a private/public key pair
# note that the key can also be generated with: ssh-keygen -t rsa -f data/myid -N ''
# amd the pub key can be extracted with: openssl rsa -in data/myid -pubout -out data/myid.pub.pem
$(APIKEY):
	mkdir -p $(TOOLCONFIGDIR)
	openssl genrsa -passout pass:dummypassword -out $(APIKEY).protected 2048
	openssl rsa -passin pass:dummypassword -in $(APIKEY).protected -out $(APIKEY)
	rm -f $(APIKEY).protected

setkey: $(APIKEY)
	$(ASCLI) --log-level=debug -np files --browser=os set_client_key ERuzXGuPA @file:$(APIKEY)

yank:
	gem yank asperalm -v $(GEMVERSION)

gempush:
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
	$(ASCLI) shares browse / --insecure=yes
tsh2:
	$(ASCLI) shares upload $(SAMPLE_FILE) /n8-sh1 --insecure=yes
tsh3: $(TEST_FOLDER)
	$(ASCLI) shares download /n8-sh1/200KB.1 $(TEST_FOLDER) --insecure=yes
	rm -f 200KB.1
	$(ASCLI) shares delete /n8-sh1/200KB.1 --insecure=yes
tshares: tsh1 tsh2 tsh3

tfp1: $(TEST_FOLDER)
	$(ASCLI) fasp browse /
	$(ASCLI) fasp upload $(SAMPLE_FILE) /Upload
	$(ASCLI) fasp download /Upload/200KB.1 $(TEST_FOLDER)
	$(ASCLI) fasp cp /Upload/200KB.1 /Upload/200KB.2
	$(ASCLI) fasp mv /Upload/200KB.2 /Upload/to.delete
	$(ASCLI) fasp delete /Upload/to.delete
	$(ASCLI) fasp md5sum /Upload/200KB.1
	$(ASCLI) fasp delete /Upload/200KB.1
tfp2:
	$(ASCLI) fasp mkdir /Upload/123
	$(ASCLI) fasp rm /Upload/123
tfp3:
	$(ASCLI) fasp info
	$(ASCLI) fasp du /
	$(ASCLI) fasp df
	

tfasp: tfp1 tfp2 tfp3

tfx1:
	$(ASCLI) faspex package list --insecure=yes
tfx2:
	$(ASCLI) faspex package send $(SAMPLE_FILE) --insecure=yes --note="my note" --title="my title" --recipient="laurent@asperasoft.com"
tfx3:
	@echo $(ASCLI) faspex package recv 05b92393-02b7-4900-ab69-fd56721e896c --insecure=yes
tfx4:
	@echo $(ASCLI) faspex recv_publink 'https://ibmfaspex.asperasoft.com/aspera/faspex/external_deliveries/78780?passcode=a003aaf2f53e3869126b908525084db6bebc7031' --insecure=yes
tfaspex: tfx1 tfx2  
tfaspex2: tfx3 tfx4

tconsole:
	$(ASCLI) console transfers list  --insecure=yes
NODEDEST=/home/faspex/docroot
NODEDEST=/
tnd1:
	$(ASCLI) node browse / --insecure=yes
tnd2:
	$(ASCLI) node upload $(SAMPLE_FILE) $(NODEDEST) --insecure=yes
tnd3: $(TEST_FOLDER)
	$(ASCLI) node download $(NODEDEST)/200KB.1 $(TEST_FOLDER) --insecure=yes
	$(ASCLI) node delete $(NODEDEST)/200KB.1 --insecure=yes
	rm -f $(TEST_FOLDER)/200KB.1
tnode: tnd1 tnd2 tnd3 

tfs1:
	$(ASCLI) files repo browse /
tfs2:
	$(ASCLI) files repo upload $(SAMPLE_FILE) /
tfs3: $(TEST_FOLDER)
	$(ASCLI) files repo download /200KB.1 $(TEST_FOLDER) --transfer=connect
	rm -f 200KB.1
tfs3b: $(TEST_FOLDER)
	$(ASCLI) files repo download /200KB.1 $(TEST_FOLDER) --download=node
	rm -f 200KB.1
tfs4:
	$(ASCLI) files package send $(SAMPLE_FILE) --note="my note" --title="my title" --recipient="laurent@asperasoft.com"
tfs5:
	$(ASCLI) files package list
tfs6:
	$(ASCLI) files package recv VleoMSrlA
tfs7:
	$(ASCLI) files admin events
tfs8:
	$(ASCLI) files admin resource workspace list
tfs9:
	$(ASCLI) files admin resource node id 4586 browse / --secret=Aspera123_

tfiles: tfs1 tfs2 tfs3 tfs3b tfs4 tfs5 tfs6 tfs7 tfs8 tfs9

to1:
	$(ASCLI) orchestrator info

to2:
	$(ASCLI) orchestrator workflow list

to3:
	$(ASCLI) orchestrator workflow status

to4:
	$(ASCLI) orchestrator workflow id 10 inputs

to5:
	$(ASCLI) orchestrator workflow id 10 status

to6:
	$(ASCLI) orchestrator workflow id 10 start --params=@json:'{"Param":"laurent"}'

to7:
	$(ASCLI) orchestrator workflow id 10 start --params=@json:'{"Param":"laurent"}' --result=ResultStep:Complete_status_message

to8:
	$(ASCLI) orchestrator plugins
to9:
	$(ASCLI) orchestrator processes

torc: to1 to2 to3 to4 to5 to6 to7 to8 to9

tat1:
	$(ASCLI) ats server list
tat2:
	$(ASCLI) ats server id gk7f5356-f4ea-kj83-ddfW-7da4ed99f8eb
tat3:
	$(ASCLI) ats server by_name --cloud=SOFTLAYER --region=ams
tat4:
	$(ASCLI) ats subscriptions
tat5:
	$(ASCLI) ats api_key repository list
tat6:
	$(ASCLI) ats api_key list
tat7:
	$(ASCLI) ats access_key create --cloud=softlayer --region=ams --params=@json:'{"id":"testkey","name":"laurent key","storage":{"type":"softlayer_swift","container":"laurent","credentials":{"api_key":"e5d032e026e0b0a16e890a3d44d11fd1471217b6262e83c7f60529f1ff4b27de","username":"IBMOS303446-9:laurentmartin"},"path":"/"}}'
tat8:
	$(ASCLI) ats access_key list --fields=name,id,secret
tat9:
	$(ASCLI) ats access_key id testkey node browse /
tat10:
	$(ASCLI) ats access_key id testkey server
tat11:
	$(ASCLI) ats access_key id testkey delete

tats: tat1 tat2 tat3 tat4 tat5 tat6 tat7 tat8 tat9 tat10 tat11

tco1:
	$(ASCLI) connect status

tco2:
	$(ASCLI) connect list

tco3:
	$(ASCLI) connect id 'Aspera Connect for Windows' info

tco4:
	$(ASCLI) connect id 'Aspera Connect for Windows' links list

tco5:
	$(ASCLI) connect id 'Aspera Connect for Windows' links id 'Windows Installer' download .

tcon: tco1 tco2 tco3 tco4 tco5

tests: tshares tfaspex tconsole tnode tfiles tfaspex2 tfasp torc tats tcon

tfxgw:
	$(ASCLI) --config-name=/NONE --url=https://localhost:9443/aspera/faspex --username=unused --password=unused faspex package send ~/200KB.1 --insecure=yes --note="my note" --title="my title" --recipient="laurent@asperasoft.com"
