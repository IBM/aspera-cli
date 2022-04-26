# This Makefile expects being run with bash or zsh shell inside the top folder

# DIR_TOP: main folder of this project (with trailing slash)
# if "" (empty) or "./" : execute "make" inside the main folder
# alternatively : $(shell dirname "$(realpath $(firstword $(MAKEFILE_LIST)))")/
DIR_TOP=

include $(DIR_TOP)common.make

all:: signedgem
doc: $(DIR_TOP).gems_checked
	cd $(DIR_DOC) && make
test: gem $(DIR_TOP).gems_checked
	cd $(DIR_TST) && make
clean::
	rm -fr $(DIR_TMP)
	rm -f $(DIR_TOP).gems_checked
	cd $(DIR_DOC) && make clean
	cd $(DIR_TST) && make clean
	rm -f Gemfile.lock
# ensure required ruby gems are installed
$(DIR_TOP).gems_checked: Gemfile
	bundle install
	touch $@

##################################
# Gem build
PATH_GEMFILE=$(DIR_TOP)$(GEMNAME)-$(GEMVERSION).gem
gem: $(PATH_GEMFILE)
# check that the signing key is present
gem_check_signing_key:
	@echo "Checking env var: SIGNING_KEY"
	@if test -z "$$SIGNING_KEY";then echo "Error: Missing env var SIGNING_KEY" 1>&2;exit 1;fi
gem_check_signature:
	tar tf $(PATH_GEMFILE)|grep '\.gz\.sig$$'
	@echo "Ok: gem is signed"
# force rebuild of gem and sign it
signedgem: gemclean gem_check_signing_key gem gem_check_signature
# gem file is generated in top folder
$(PATH_GEMFILE): doc
	gem build $(GEMNAME)
gemclean:
	rm -f $(PATH_GEMFILE)
install: $(PATH_GEMFILE)
	gem install $(PATH_GEMFILE)
installdeps:
	bundle install
clean:: gemclean

##################################
# Gem publish
gempush: all dotag
	gem push $(PATH_GEMFILE)
# in case of big problem on released gem version, it can be deleted from rubygems
yank:
	gem yank aspera -v $(GEMVERSION)

##################################
# GIT
changes:
	@latest_tag=$$(git describe --tags --abbrev=0);\
	echo "Changes since [$$latest_tag]";\
	git log $$latest_tag..HEAD --oneline

##################################
# Docker image
DOCKER_REPO=martinlaurent/ascli
DOCKER_TAG_VERSION=$(DOCKER_REPO):$(GEMVERSION)
DOCKER_TAG_LATEST=$(DOCKER_REPO):latest
docker: $(PATH_GEMFILE)
	docker build --build-arg gemfile=$(PATH_GEMFILE) --tag $(DOCKER_TAG_VERSION) --tag $(DOCKER_TAG_LATEST) $(DIR_TOP).
dockertest:
	docker run --tty --interactive --rm aspera-cli ascli -h
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
