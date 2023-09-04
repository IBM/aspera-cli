# This Makefile expects being run with bash or zsh shell inside the top folder

# DIR_TOP: main folder of this project (with trailing slash)
# if "" (empty) or "./" : execute "make" inside the main folder
# alternatively : $(shell dirname "$(realpath $(firstword $(MAKEFILE_LIST)))")/
DIR_TOP=

include $(DIR_TOP)common.mak

all:: doc signed_gem
doc:
	cd $(DIR_DOC) && make
test: unsigned_gem
	cd $(DIR_TST) && make
fulltest: doc test
clean::
	rm -fr $(DIR_TMP)
	cd $(DIR_DOC) && make clean
	cd $(DIR_TST) && make clean
	rm -f Gemfile.lock
delgen::
	cd $(DIR_DOC) && make delgen
##################################
# Gem build
$(PATH_GEMFILE): $(DIR_TOP).gems_checked
	gem build $(GEMNAME)
# check that the signing key is present
gem_check_signing_key:
	@echo "Checking env var: SIGNING_KEY"
	@if test -z "$$SIGNING_KEY";then echo "Error: Missing env var SIGNING_KEY" 1>&2;exit 1;fi
	@if test ! -e "$$SIGNING_KEY";then echo "Error: No such file: $$SIGNING_KEY" 1>&2;exit 1;fi
# force rebuild of gem and sign it, then check signature
signed_gem: gemclean gem_check_signing_key $(PATH_GEMFILE)
	@tar tf $(PATH_GEMFILE)|grep '\.gz\.sig$$'
	@echo "Ok: gem is signed"
# build gem without signature for development and test
unsigned_gem: $(PATH_GEMFILE)
gemclean:
	rm -f $(PATH_GEMFILE)
	rm -f $(DIR_TOP)$(GEMNAME)-*.gem
install: $(PATH_GEMFILE)
	gem install $(PATH_GEMFILE)
clean:: gemclean
##################################
# Gem certificate
# updates the existing certificate, keeping the maintainer email
update-cert: gem_check_signing_key
	cert_chain=$(DIR_TOP)$$(sed -nEe "s/ *spec.cert_chain.+'(.+)'.*/\1/p" < $(DIR_TOP)aspera-cli.gemspec)&&\
	gem cert \
	--re-sign \
	--certificate $$cert_chain \
	--private-key $$SIGNING_KEY \
	--days 1100
# creates a new certificate, taking the maintainer email from gemspec
new-cert: gem_check_signing_key
	maintainer_email=$$(sed -nEe "s/ *spec.email.+'(.+)'.*/\1/p" < $(DIR_TOP)aspera-cli.gemspec)&&\
	gem cert \
	--build $$maintainer_email \
	--private-key $$SIGNING_KEY \
	--days 1100
	cert_chain=$(DIR_TOP)$$(sed -nEe "s/ *spec.cert_chain.+'(.+)'.*/\1/p" < $(DIR_TOP)aspera-cli.gemspec)&&\
	mv gem-public_cert.pem $$cert_chain
show-cert:
	cert_chain=$(DIR_TOP)$$(sed -nEe "s/ *spec.cert_chain.+'(.+)'.*/\1/p" < $(DIR_TOP)aspera-cli.gemspec)&&\
	openssl x509 -noout -text -in $$cert_chain|head -n 13
check-cert-key: $(DIR_TMP).exists gem_check_signing_key
	@cert_chain=$(DIR_TOP)$$(sed -nEe "s/ *spec.cert_chain.+'(.+)'.*/\1/p" < $(DIR_TOP)aspera-cli.gemspec)&&\
	openssl x509 -noout -pubkey -in $$cert_chain > $(DIR_TMP)cert.pub
	@openssl rsa -pubout -passin pass:_value_ -in $$SIGNING_KEY > $(DIR_TMP)sign.pub
	@if cmp -s $(DIR_TMP)cert.pub $(DIR_TMP)sign.pub;then echo "Ok: certificate and key match";else echo "Error: certificate and key do not match" 1>&2;exit 1;fi
##################################
# Gem publish
release: all
	gem push $(PATH_GEMFILE)
version:
	@echo $(GEMVERS)
# in case of big problem on released gem version, it can be deleted from rubygems
# gem yank -v $(GEMVERS) $(GEMNAME) 

##################################
# GIT
changes:
	@latest_tag=$$(git describe --tags --abbrev=0);\
	echo "Changes since [$$latest_tag]";\
	git log $$latest_tag..HEAD --oneline

##################################
# Docker image
DOCKER_REPO=martinlaurent/ascli
DOCKER_IMG_VERSION=$(GEMVERS)
DOCKER_TAG_VERSION=$(DOCKER_REPO):$(DOCKER_IMG_VERSION)
DOCKER_TAG_LATEST=$(DOCKER_REPO):latest
LOCAL_SDK_FILE=$(DIR_TMP)sdk.zip
SDK_URL=https://ibm.biz/aspera_transfer_sdk
$(LOCAL_SDK_FILE): $(DIR_TMP).exists
	curl -L $(SDK_URL) -o $(LOCAL_SDK_FILE)
# Refer to section "build" in CONTRIBUTING.md
# no dependency: always re-generate
dockerfilerel:
	erb -T 2 \
		arg_gem=$(GEMNAME):$(GEMVERS) \
		arg_sdk=$(LOCAL_SDK_FILE) \
		Dockerfile.tmpl.erb > Dockerfile
docker: dockerfilerel $(LOCAL_SDK_FILE)
	docker build --squash --tag $(DOCKER_TAG_VERSION) .
	docker tag $(DOCKER_TAG_VERSION) $(DOCKER_TAG_LATEST)
dockerfilebeta:
	erb -T 2 \
		arg_gem=$(PATH_GEMFILE) \
		arg_sdk=$(LOCAL_SDK_FILE) \
		Dockerfile.tmpl.erb > Dockerfile
dockerbeta: dockerfilebeta $(LOCAL_SDK_FILE) $(PATH_GEMFILE)
	docker build --squash --tag $(DOCKER_TAG_VERSION) .
dockertest:
	docker run --tty --interactive --rm $(DOCKER_TAG_VERSION) ascli -h
dpush: dpushversion dpushlatest
dpushversion:
	docker push $(DOCKER_TAG_VERSION)
dpushlatest:
	docker push $(DOCKER_TAG_LATEST)
clean::
	rm -f Dockerfile
##################################
# Single executable using https://github.com/pmq20/ruby-packer
CLIEXEC=$(EXENAME).exe
RUBY_PACKER=$(DIR_TOP)examples/rubyc
single:$(CLIEXEC)
.PHONY: check-ruby-packer
check-ruby-packer:
	@set -e && for v in '' -ruby -ruby-api;do\
		echo "Version ($$v): $$($(RUBY_PACKER) -$$v-version)";\
	done
$(CLIEXEC): check-ruby-packer
	$(RUBY_PACKER) -o $(CLIEXEC) $(EXETESTB)
clean::
	rm -f $(CLIEXEC)
##################################
# utils
# https://github.com/Yelp/detect-secrets
scaninit:
	detect-secrets scan --exclude-files '^.secrets.baseline$$' --exclude-secrets '_here_' --exclude-secrets '^my_' --exclude-secrets '^your ' --exclude-secrets demoaspera
scan:
	detect-secrets scan --baseline .secrets.baseline
tidy:
	rubocop $(DIR_LIB).
