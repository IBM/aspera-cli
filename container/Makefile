DIR_TOP=../

include $(DIR_TOP)common.mak

all:: build

##################################
# Docker image
DOCKER_TAG_VERSION=$(DCK_REPO):$(GEM_VERSION)
DOCKER_TAG_LATEST=$(DCK_REPO):latest
PROCESS_DOCKER_FILE_TEMPLATE=sed -Ee 's/^\#erb:(.*)/<%\1%>/g' < Dockerfile.tmpl.erb | erb -T 2
DOCKER=podman
# Refer to section "build" in CONTRIBUTING.md
# no dependency: always re-generate
# TODO: get optional gems from 
build: $(OPT_GEMS_FILE) Dockerfile.tmpl.erb
	$(PROCESS_DOCKER_FILE_TEMPLATE) arg_gem=$(GEM_NAME):$(GEM_VERSION) arg_opt="$$(cat $(OPT_GEMS_FILE))" > Dockerfile
	$(DOCKER) build --squash --tag $(DOCKER_TAG_VERSION) --tag $(DOCKER_TAG_LATEST) .
test:
	$(DOCKER) run --tty --interactive --rm $(DOCKER_TAG_VERSION) $(CLI_NAME) -h
# Push build version with both tags (version and latest)
push_version:
	$(DOCKER) push $(DOCKER_TAG_VERSION)
push_latest:
	$(DOCKER) push $(DOCKER_TAG_LATEST)
push: push_version push_latest
$(PATH_GEMFILE):
	cd $(DIR_TOP) && make unsigned_gem
beta_build_target: $(OPT_GEMS_FILE) Dockerfile.tmpl.erb $(PATH_GEMFILE)
	cp $(PATH_GEMFILE) aspera-cli-beta.gem
	$(PROCESS_DOCKER_FILE_TEMPLATE) arg_gem=aspera-cli-beta.gem arg_opt="$$(cat $(OPT_GEMS_FILE))" > Dockerfile
	$(DOCKER) build --squash --tag $(DOCKER_TAG_VERSION) .
beta_build:
	make GEM_VERSION=$(GEM_VERS_BETA) beta_build_target
beta_push:
	make GEM_VERSION=$(GEM_VERS_BETA) push_version
beta_test:
	make GEM_VERSION=$(GEM_VERS_BETA) test
clean::
	rm -f Dockerfile aspera-cli-beta.gem
