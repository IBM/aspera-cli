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
	$(ASCLI) --log-level=debug -np files --code-get=osbrowser set_client_key ERuzXGuPA @file:$(APIKEY)

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

t1:
	$(ASCLI) shares browse /
t2:
	$(ASCLI) shares upload ~/200KB.1 /n8-sh1
t3:
	$(ASCLI) shares download /n8-sh1/200KB.1 .
	rm -f 200KB.1
t4:
	$(ASCLI) faspex recv_publink https://ibmfaspex.asperasoft.com/aspera/faspex/external_deliveries/78780?passcode=a003aaf2f53e3869126b908525084db6bebc7031
t5:
	$(ASCLI) faspex list
t6:
	$(ASCLI) faspex recv 05b92393-02b7-4900-ab69-fd56721e896c
t7:
	$(ASCLI) faspex --note="my note" --title="my title" --recipient="laurent@asperasoft.com" send ~/200KB.1 
t8:
	$(ASCLI) console transfers list
t9:
	$(ASCLI) node browse /
t10:
	$(ASCLI) node upload ~/200KB.1 /
t11:
	$(ASCLI) node download /200KB.1 .
	rm -f 200KB.1
t12:
	$(ASCLI) files browse /
t13:
	$(ASCLI) files upload ~/200KB.1 /
t14:
	$(ASCLI) files download /200KB.1 .
	rm -f 200KB.1
t15:
	$(ASCLI) files send ~/200KB.1
t16:
	$(ASCLI) files packages
t17:
	$(ASCLI) files recv VleoMSrlA
t18:
	$(ASCLI) files events

tests: t1 t2 t3  t5 t7 t8 t9 t10 t11 filestests

filestests: t12 t13 t14 t15 t16 t17 t18 t4 t6
