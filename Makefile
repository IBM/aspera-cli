# This Makefile expects being run with bash or zsh shell inside the top folder
# cspell:ignore pubkey gemdir oneline demoaspera firstword noout pubout semgrep

# DIR_TOP: main folder of this project (with trailing slash)
# if "" (empty) or "./" : execute "make" inside the main folder
# alternatively : $(shell dirname "$(realpath $(firstword $(MAKEFILE_LIST)))")/
DIR_TOP=

include $(DIR_TOP)common.mak

all:: doc signed_gem

clean::
	rm -fr $(DIR_TOP).vscode/*.log

#clean::
#	cd package/container && rake clean
beta:
	cd $(ASPERA_CLI_TEST_PRIVATE) && make beta
##################################
# Documentation
.PHONY: doc clean_doc
doc:
	cd $(DIR_DOC) && make
clean::
	cd $(DIR_DOC) && make clean
clean_doc::
	cd $(DIR_DOC) && make clean_doc
##################################
# Tests
.PHONY: test test_full
test: unsigned_gem
	cd $(DIR_TST) && make
test_full:
	make clean_gems
	make test
	make install_optional_gems
	cd $(DIR_TST) && make full
clean::
	cd $(DIR_TST) && make clean
##################################
# Gem build
.PHONY: signed_gem unsigned_gem beta_gem clean_gem install clean_gems clean_optional_gems install_dev_gems install_optional_gems
$(PATH_GEMFILE): ensure_gems_installed
	gem build $(GEMSPEC)
	gem specification $(PATH_GEMFILE) version
# force rebuild of gem and sign it, then check signature
signed_gem: gem_check_signing_key clean_gem ensure_gems_installed $(PATH_GEMFILE)
	@tar tf $(PATH_GEMFILE)|grep '\.gz\.sig$$'
	@echo "Ok: gem is signed"
# build gem without signature for development and test
unsigned_gem: $(PATH_GEMFILE)
beta_gem:
	make GEM_VERSION=$(GEM_VERS_BETA) unsigned_gem
# Delete generated gem
clean_gem:
	rm -f $(PATH_GEMFILE)
	rm -f $(DIR_TOP)$(GEM_NAME)-*.gem
install: $(PATH_GEMFILE)
	gem install $(PATH_GEMFILE)
# Delete all gems installed in Ruby
clean_gems: clean_gems_installed
	if ls $$(gem env gemdir)/gems/* > /dev/null 2>&1; then gem uninstall -axI $$(ls $$(gem env gemdir)/gems/|sed -e 's/-[0-9].*$$//'|sort -u);fi
# gems that require native build are made optional
clean_optional_gems:
	bundle config set without optional
	bundle install
	bundle clean --force
# install dev gems and 
# remove ascli and asession from ruby gem bin folder, so that the one from dev is used
# rm -f $$(gem env gemdir)/bin/as{cli,ession}
install_dev_gems:
	gem install bundler
	bundle config set with development
	bundle install
# install optional gems and 
install_optional_gems: install_dev_gems
	bundle config set with optional
	bundle install
clean:: clean_gem
	rm -fr $(DIR_TOP).bundle
# transfer SDK stub generate
PROTO_PATH=$(DIR_TMP)protos/
GRPC_DEST=$(DIR_LIB)
grpc:
	mkdir -p $(PROTO_PATH)
	$(BLD_TOOL) -r build_tools -e BuildTools.download_proto_file $(PROTO_PATH)
	grpc_tools_ruby_protoc\
	  --proto_path=$(PROTO_PATH)\
	  --ruby_out=$(GRPC_DEST)\
	  --grpc_out=$(GRPC_DEST)\
	  $(PROTO_PATH)transferd.proto

##################################
# Gem publish
# in case of big problem on released gem version, it can be deleted from rubygems
# gem yank -v $(GEM_VERSION) $(GEM_NAME) 
release: all
	gem push $(PATH_GEMFILE)

##################################
# tools
# https://github.com/Yelp/detect-secrets
changes:
	@latest_tag=$$(git describe --tags --abbrev=0);\
	echo "Changes since [$$latest_tag]";\
	PAGER= git log $$latest_tag..HEAD --oneline
scan_init:
	detect-secrets scan --exclude-files '^.secrets.baseline$$' --exclude-secrets '_here_' --exclude-secrets '^my_' --exclude-secrets '^your ' --exclude-secrets demoaspera
scan:
	detect-secrets scan --baseline .secrets.baseline
tidy:
	rubocop $(DIR_LIB).
reek:
	reek -c $(DIR_TOP).reek.yml
semgrep:
	semgrep scan --config auto
checkversions: clean_gems install_optional_gems
	bundle outdated
