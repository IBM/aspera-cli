DIR_TOP=../

include $(DIR_TOP)common.mak

all:: build

##################################
# Container image
TAG_VERSION=$(DCK_REPO):$(GEM_VERSION)
TAG_LATEST=$(DCK_REPO):latest
PROCESS_TEMPLATE=sed -Ee 's/^\#erb:(.*)/<%\1%>/g' < Dockerfile.tmpl.erb | erb -T 2
TOOL=podman
OPT_GEMS=$(shell $(DIR_DOC)get_group.rb $(DIR_TOP)Gemfile optional)
# Refer to section "build" in CONTRIBUTING.md
# no dependency: always re-generate
# TODO: get optional gems from 
build: Dockerfile.tmpl.erb
	$(PROCESS_TEMPLATE) arg_gem=$(GEM_NAME):$(GEM_VERSION) arg_opt="$(OPT_GEMS)" > Dockerfile
	$(TOOL) build --squash --tag $(TAG_VERSION) --tag $(TAG_LATEST) .
test:
	$(TOOL) run --tty --interactive --rm $(TAG_VERSION) $(CLI_NAME) -v
# Push build version with both tags (version and latest)
push_version:
	$(TOOL) push $(TAG_VERSION)
push_latest:
	$(TOOL) push $(TAG_LATEST)
push: push_version push_latest
$(PATH_GEMFILE):
	cd $(DIR_TOP) && make unsigned_gem
beta_build_target: Dockerfile.tmpl.erb $(PATH_GEMFILE)
	cp $(PATH_GEMFILE) aspera-cli-beta.gem
	$(PROCESS_TEMPLATE) arg_gem=aspera-cli-beta.gem arg_opt="$(OPT_GEMS)" > Dockerfile
	$(TOOL) build --squash --tag $(TAG_VERSION) .
beta_build:
	echo $(GEM_VERS_BETA) > $(DIR_TMP)/beta.txt
	make GEM_VERSION=$(GEM_VERS_BETA) beta_build_target
beta_push:
	make GEM_VERSION=$$(cat $(DIR_TMP)/beta.txt) push_version
beta_test:
	make GEM_VERSION=$$(cat $(DIR_TMP)/beta.txt) test
clean::
	rm -f Dockerfile aspera-cli-beta.gem $(DIR_TMP)/beta.txt
info:
	@echo "Repo: $(DCK_REPO)"
