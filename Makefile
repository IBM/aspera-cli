GEMNAME=asperalm
GEMVERSION=$(shell ruby -e 'require "./lib/asperalm/version.rb";puts Asperalm::VERSION')
GEMFILE=$(GEMNAME)-$(GEMVERSION).gem
TOOLCONFIGDIR=$(HOME)/.aspera/ascli
APIKEY=$(TOOLCONFIGDIR)/filesapikey
ASCLI=./bin/ascli

SRCZIPBASE=$(GEMNAME)_src
TODAY=$(shell date +%Y%m%d)
ZIPFILE=$(SRCZIPBASE)_$(TODAY).zip

all:: clean gem pack

test:
	bundle exec rake spec

clean:
	rm -f $(GEMNAME)-*.gem $(SRCZIPBASE)*.zip *.log token.*
	gem uninstall $(GEMNAME)

pack: $(ZIPFILE)

$(ZIPFILE):
	rm -f $(SRCZIPBASE)_*.zip
	zip -r $(ZIPFILE) `git ls-files`

asperalm-0.1.0.gem:
	gem build asperalm.gemspec

gem: asperalm-0.1.0.gem
	gem install $(GEMFILE)

togarage: $(ZIPFILE) README.pdf asperalm-0.1.0.gem
	ascli files --workspace='Sales Engineering' upload '/Laurent Garage SE/RubyCLI' $(ZIPFILE) README.pdf asperalm-0.1.0.gem

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

