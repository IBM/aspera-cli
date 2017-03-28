GEMNAME=asperalm
GEMVERSION=$(shell ruby -e 'require "./lib/asperalm/version.rb";puts Asperalm::VERSION')
GEMFILE=$(GEMNAME)-$(GEMVERSION).gem
TOOLCONFIGDIR=$(HOME)/.aspera/aslm
APIKEY=$(TOOLCONFIGDIR)/filesapikey
ASCLI=./bin/aslm

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

key: $(APIKEY)
	$(ASCLI) --log-level=debug -np files --code-get=osbrowser set_client_key ERuzXGuPA @file:$(APIKEY)

# send a package using JWT auth
test_jwt_send:
	$(ASCLI) --log-level=debug files send data/200KB.1

# Faspex API gateway
gw:
	$(ASCLI) --log-level=debug files faspexgw

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
	aslm shares browse /
t2:
	aslm shares upload ~/200KB.1 /projectx
t3:
	aslm shares download /projectx/200KB.1 .
t4:
	aslm faspex recv_publink https://ibmfaspex.asperasoft.com/aspera/faspex/external_deliveries/78780?passcode=a003aaf2f53e3869126b908525084db6bebc7031
t5:
	aslm -nibm faspex list
t6:
	aslm -nibm faspex recv 05b92393-02b7-4900-ab69-fd56721e896c
t7:
	aslm -nibm faspex --note="my note" --title="my title" --recipient="laurent@asperasoft.com" send ~/200KB.1 
t8:
	aslm console transfers list
t9:
	aslm node browse /
t10:
	aslm node upload ~/200KB.1 /tmp
t11:
	aslm node download /tmp/200KB.1 .
t12:
	aslm files browse /
t13:
	aslm files upload ~/200KB.1 /
t14:
	aslm files download /200KB.1 .
t15:
	aslm files send ~/200KB.1
t16:
	aslm files packages
t17:
	aslm files recv VleoMSrlA
t18:
	aslm files events
