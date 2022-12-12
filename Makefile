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

##################################
# Gem build
$(PATH_GEMFILE): $(DIR_TOP).gems_checked
	gem build $(GEMNAME)
# check that the signing key is present
gem_check_signing_key:
	@echo "Checking env var: SIGNING_KEY"
	@if test -z "$$SIGNING_KEY";then echo "Error: Missing env var SIGNING_KEY" 1>&2;exit 1;fi
# force rebuild of gem and sign it, then check signature
signed_gem: gemclean gem_check_signing_key $(PATH_GEMFILE)
	@tar tf $(PATH_GEMFILE)|grep '\.gz\.sig$$'
	@echo "Ok: gem is signed"
# build gem without signature for development and test
unsigned_gem: $(PATH_GEMFILE)
gemclean:
	rm -f $(PATH_GEMFILE)
install: $(PATH_GEMFILE)
	gem install $(PATH_GEMFILE)
clean:: gemclean

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
DOCKER_TAG_VERSION=$(DOCKER_REPO):$(GEMVERS)
DOCKER_TAG_LATEST=$(DOCKER_REPO):latest
$(DIR_TMP)sdk.zip: $(DIR_TMP).exists
	curl -L https://ibm.biz/aspera_transfer_sdk -o $(DIR_TMP)sdk.zip
docker: $(PATH_GEMFILE) $(DIR_TMP)sdk.zip
	docker build --build-arg gemfile=$(PATH_GEMFILE) --build-arg sdkfile=$(DIR_TMP)sdk.zip --tag $(DOCKER_TAG_VERSION) --tag $(DOCKER_TAG_LATEST) $(DIR_TOP).
dockertest:
	docker run --tty --interactive --rm $(DOCKER_TAG_LATEST) ascli -h
dpush:
	docker push $(DOCKER_TAG_VERSION)
	docker push $(DOCKER_TAG_LATEST)
##################################
# Single executable using https://github.com/pmq20/ruby-packer
CLIEXEC=$(EXENAME).exe
single:$(CLIEXEC)
$(CLIEXEC):
	rubyc -o $(CLIEXEC) $(EXETESTB)
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
