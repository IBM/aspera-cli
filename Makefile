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

all:: clean gem pack

test:
	bundle exec rake spec

clean:
	rm -f $(GEMNAME)-*.gem $(SRCZIPBASE)*.zip *.log token.* README.pdf README.html
	rm -fr doc
	gem uninstall -a -x $(GEMNAME)

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
	git commit -a -m 'all, from Makefile'
# eq to: git push origin master
push:
	git push

installdeps:
	gem install jwt formatador ruby-progressbar

SAMPLE_FILE=~/Documents/Samples/200KB.1

tsh1:
	$(ASCLI) shares browse /
tsh2:
	$(ASCLI) shares upload $(SAMPLE_FILE) /n8-sh1
tsh3:
	$(ASCLI) shares download /n8-sh1/200KB.1 .
	rm -f 200KB.1
	$(ASCLI) shares delete /n8-sh1/200KB.1
tshares: tsh1 tsh2 tsh3

tfx1:
	$(ASCLI) faspex list
tfx2:
	$(ASCLI) faspex send $(SAMPLE_FILE) --note="my note" --title="my title" --recipient="laurent@asperasoft.com"
tfx3:
	@echo $(ASCLI) faspex recv 05b92393-02b7-4900-ab69-fd56721e896c
tfx4:
	@echo $(ASCLI) faspex recv_publink https://ibmfaspex.asperasoft.com/aspera/faspex/external_deliveries/78780?passcode=a003aaf2f53e3869126b908525084db6bebc7031
tfaspex: tfx1 tfx2  
tfaspex2: tfx3 tfx4
tconsole:
	$(ASCLI) console transfers list
tnd1:
	$(ASCLI) node browse /
tnd2:
	$(ASCLI) node upload $(SAMPLE_FILE) /home/faspex/docroot
tnd3:
	$(ASCLI) node download /home/faspex/docroot/200KB.1 .
	rm -f 200KB.1
	$(ASCLI) node delete /home/faspex/docroot/200KB.1
tnode: tnd1 tnd2 tnd3 

tfs1:
	$(ASCLI) files repo browse /
tfs2:
	$(ASCLI) files repo upload $(SAMPLE_FILE) /
tfs3:
	$(ASCLI) files repo download /200KB.1 .
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
	$(ASCLI) files admin resource node 2374 browse / --secret=laurent

tfiles: tfs1 tfs2 tfs3 tfs4 tfs5 tfs6 tfs7 tfs8 tfs9

tests: tshares tfaspex tconsole tnode tfiles tfaspex2
