# This Makefile expects being run with bash or zsh shell inside the top folder

# DIR_TOP: main folder of this project (with trailing slash)
# if "" (empty) or "./" : execute "make" inside the main folder
# alternatively : $(shell dirname "$(realpath $(firstword $(MAKEFILE_LIST)))")/
DIR_TOP=

include $(DIR_TOP)common.mak

GEMSPEC_FILE=$(DIR_TOP)$(GEM_NAME).gemspec

all:: $(DIR_TOP).gems_checked doc signed_gem
doc:
	cd $(DIR_DOC) && make
test: unsigned_gem
	cd $(DIR_TST) && make
test_full: doc test
clean::
	rm -fr $(DIR_TMP)
	cd $(DIR_DOC) && make clean
	cd $(DIR_TST) && make clean
	rm -f Gemfile.lock
clean_doc::
	cd $(DIR_DOC) && make clean_doc
##################################
# Gem build
$(PATH_GEMFILE): $(DIR_TOP).gems_checked
	gem build $(GEMSPEC_FILE)
	gem specification $(PATH_GEMFILE) version
# check that the signing key is present
gem_check_signing_key:
	@echo "Checking env var: SIGNING_KEY"
	@if test -z "$$SIGNING_KEY";then echo "Error: Missing env var SIGNING_KEY" 1>&2;exit 1;fi
	@if test ! -e "$$SIGNING_KEY";then echo "Error: No such file: $$SIGNING_KEY" 1>&2;exit 1;fi
# force rebuild of gem and sign it, then check signature
signed_gem: clean_gem gem_check_signing_key $(PATH_GEMFILE)
	@tar tf $(PATH_GEMFILE)|grep '\.gz\.sig$$'
	@echo "Ok: gem is signed"
# build gem without signature for development and test
unsigned_gem: $(PATH_GEMFILE)
clean_gem:
	rm -f $(PATH_GEMFILE)
	rm -f $(DIR_TOP)$(GEM_NAME)-*.gem
clean_gems: clean
	if ls $$(gem env gemdir)/gems/* > /dev/null 2>&1; then gem uninstall -axI $$(ls $$(gem env gemdir)/gems/|sed -e 's/-[0-9].*$$//'|sort -u);fi
install: $(PATH_GEMFILE)
	gem install $(PATH_GEMFILE)
clean:: clean_gem
##################################
# Gem certificate
# updates the existing certificate, keeping the maintainer email
update-cert: gem_check_signing_key
	cert_chain=$(DIR_TOP)$$(sed -nEe "s/ *spec.cert_chain.+'(.+)'.*/\1/p" < $(GEMSPEC_FILE))&&\
	gem cert \
	--re-sign \
	--certificate $$cert_chain \
	--private-key $$SIGNING_KEY \
	--days 1100
# creates a new certificate, taking the maintainer email from gemspec
new-cert: gem_check_signing_key
	maintainer_email=$$(sed -nEe "s/ *spec.email.+'(.+)'.*/\1/p" < $(GEMSPEC_FILE))&&\
	gem cert \
	--build $$maintainer_email \
	--private-key $$SIGNING_KEY \
	--days 1100
	cert_chain=$(DIR_TOP)$$(sed -nEe "s/ *spec.cert_chain.+'(.+)'.*/\1/p" < $(GEMSPEC_FILE))&&\
	mv gem-public_cert.pem $$cert_chain
show-cert:
	cert_chain=$(DIR_TOP)$$(sed -nEe "s/ *spec.cert_chain.+'(.+)'.*/\1/p" < $(GEMSPEC_FILE))&&\
	openssl x509 -noout -text -in $$cert_chain|head -n 13
check-cert-key: $(DIR_TMP).exists gem_check_signing_key
	@cert_chain=$(DIR_TOP)$$(sed -nEe "s/ *spec.cert_chain.+'(.+)'.*/\1/p" < $(GEMSPEC_FILE))&&\
	openssl x509 -noout -pubkey -in $$cert_chain > $(DIR_TMP)cert.pub
	@openssl rsa -pubout -passin pass:_value_ -in $$SIGNING_KEY > $(DIR_TMP)sign.pub
	@if cmp -s $(DIR_TMP)cert.pub $(DIR_TMP)sign.pub;then echo "Ok: certificate and key match";else echo "Error: certificate and key do not match" 1>&2;exit 1;fi
##################################
# Gem publish
release: all
	gem push $(PATH_GEMFILE)
version:
	@echo $(GEM_VERSION)
# in case of big problem on released gem version, it can be deleted from rubygems
# gem yank -v $(GEM_VERSION) $(GEM_NAME) 

##################################
# GIT
changes:
	@latest_tag=$$(git describe --tags --abbrev=0);\
	echo "Changes since [$$latest_tag]";\
	git log $$latest_tag..HEAD --oneline

##################################
# Docker image
DOCKER_REPO=$(shell cat $(DIR_DOC)docker_repository.txt)
DOCKER_IMG_VERSION=$(GEM_VERSION)
DOCKER_TAG_VERSION=$(DOCKER_REPO):$(DOCKER_IMG_VERSION)
DOCKER_TAG_LATEST=$(DOCKER_REPO):latest
LOCAL_SDK_FILE=$(DIR_TMP)sdk.zip
SDK_URL=https://ibm.biz/aspera_transfer_sdk
PROCESS_DOCKER_FILE_TEMPLATE=sed -Ee 's/^\#erb:(.*)/<%\1%>/' < Dockerfile.tmpl.erb | erb -T 2
$(LOCAL_SDK_FILE): $(DIR_TMP).exists
	curl -L $(SDK_URL) -o $(LOCAL_SDK_FILE)
# Refer to section "build" in CONTRIBUTING.md
# no dependency: always re-generate
dockerfile_release:
	$(PROCESS_DOCKER_FILE_TEMPLATE) arg_gem=$(GEM_NAME):$(GEM_VERSION) arg_sdk=$(LOCAL_SDK_FILE) > Dockerfile
docker: dockerfile_release $(LOCAL_SDK_FILE)
	docker build --squash --tag $(DOCKER_TAG_VERSION) --tag $(DOCKER_TAG_LATEST) .
dockerfile_beta:
	$(PROCESS_DOCKER_FILE_TEMPLATE) arg_gem=$(PATH_GEMFILE) arg_sdk=$(LOCAL_SDK_FILE) > Dockerfile
docker_beta: dockerfile_beta $(LOCAL_SDK_FILE) $(PATH_GEMFILE)
	docker build --squash --tag $(DOCKER_TAG_VERSION) .
docker_test:
	docker run --tty --interactive --rm $(DOCKER_TAG_VERSION) ascli -h
docker_push: docker_push_version docker_push_latest
docker_push_version:
	docker push $(DOCKER_TAG_VERSION)
docker_push_latest:
	docker push $(DOCKER_TAG_LATEST)
clean::
	rm -f Dockerfile
##################################
# Single executable using https://github.com/pmq20/ruby-packer
CLI_EXECUTABLE=$(DIR_TMP)$(CLI_NAME).$(shell uname -ms|tr ' ' '-')
RUBY_PACKER=$(DIR_TOP)examples/rubyc
single:$(CLI_EXECUTABLE)
$(CLI_EXECUTABLE):
	@set -e && for v in '' -ruby -ruby-api;do\
		echo "Version ($$v): $$($(RUBY_PACKER) -$$v-version)";\
	done
	$(RUBY_PACKER) -o $(CLI_EXECUTABLE) $(CLI_PATH)
clean::
	rm -f $(CLI_EXECUTABLE)
##################################
# utils
# https://github.com/Yelp/detect-secrets
scan_init:
	detect-secrets scan --exclude-files '^.secrets.baseline$$' --exclude-secrets '_here_' --exclude-secrets '^my_' --exclude-secrets '^your ' --exclude-secrets demoaspera
scan:
	detect-secrets scan --baseline .secrets.baseline
tidy:
	rubocop $(DIR_LIB).
# cspell:ignore pubkey gemdir oneline demoaspera firstword noout pubout
