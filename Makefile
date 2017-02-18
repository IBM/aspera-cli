GEMNAME=asperalm
GEMVERSION=$(shell ruby -e 'require "./lib/asperalm/version.rb";puts Asperalm::VERSION')
GEMFILE=$(GEMNAME)-$(GEMVERSION).gem
TOOLDIR=$(HOME)/.aspera/ascli
APIKEY=$(TOOLDIR)/filesapikey
ASCLI=./bin/ascli
all:: clean gem pack

test:
	bundle exec rake spec

clean:
	rm -f $(GEMNAME)-*.gem FilesApiSampleRuby*.zip *.log token.*
	gem uninstall $(GEMNAME)

pack:
	rm -f FilesApiSampleRuby_*.zip
	zip -r FilesApiSampleRuby_$$(date +%Y%m%d).zip lib data/ascli.yaml src/as_cli.rb 0README.txt Makefile

test:
	ruby FaspManager_test.rb

gem:
	gem build asperalm.gemspec
	gem install $(GEMFILE)

# create a private/public key pair
# note that the key can also be generated with: ssh-keygen -t rsa -f data/myid -N ''
# amd the pub key can be extracted with: openssl rsa -in data/myid -pubout -out data/myid.pub.pem
$(APIKEY):
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
