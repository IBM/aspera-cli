# This Makefile expects being run with bash or zsh shell inside the top folder

# DIR_TOP: main folder of this project (with trailing slash)
# if "" (empty) or "./" : execute "make" inside the main folder
# alternatively : $(shell dirname "$(realpath $(firstword $(MAKEFILE_LIST)))")/
DIR_TOP=

include $(DIR_TOP)common.make

all:: gem doc

doc: $(DIR_TOP).gems_checked
	cd $(DIR_DOC) && make
clean::
	cd $(DIR_DOC) && make clean
test: gem $(DIR_TOP).gems_checked
	cd $(DIR_TST) && make
clean::
	cd $(DIR_TST) && make clean
	rm -f $(DIR_TOP).gems_checked
# ensure required ruby gems are installed
$(DIR_TOP).gems_checked: Gemfile
	bundle install
	touch $@

##################################
# Gem build
PATH_GEMFILE=$(DIR_TOP)$(GEMNAME)-$(GEMVERSION).gem

gem: $(PATH_GEMFILE)

# gem file is generated in top folder
$(PATH_GEMFILE): $(GEMSPEC) $(DIR_LIB)aspera/fasp/transfer_spec.rb
	gem build $(GEMNAME)
clean::
	rm -f $(PATH_GEMFILE)
install: $(PATH_GEMFILE)
	gem install $(PATH_GEMFILE)
cleanupgems:
	gem uninstall -a -x $$(gem list|cut -f 1 -d' '|egrep -v 'rdoc|psych|rake|openssl|json|io-console|bigdecimal')
installdeps:
	gem install $$(sed -nEe "/^[^#].*add_[^_]+_dependency/ s/[^']+'([^']+)'.*/\1/p" < $(GEMNAME).gemspec )
$(DIR_LIB)aspera/fasp/transfer_spec.rb: $(DIR_LIB)aspera/fasp/transfer_spec.rb.erb
	RUBYLIB=$(DIR_LIB) erb -T - -U -r aspera/fasp/parameters $(DIR_LIB)aspera/fasp/transfer_spec.rb.erb > $@
##################################
# Gem publish
gempush: all dotag
	gem push $(PATH_GEMFILE)
# in case of big problem on released gem version, it can be deleted from rubygems
yank:
	gem yank aspera -v $(GEMVERSION)

##################################
# GIT
GIT_TAG_VERSION_PREFIX='v_'
GIT_TAG_CURRENT=$(GIT_TAG_VERSION_PREFIX)$(GEMVERSION)

dotag:
	git tag -a $(GIT_TAG_CURRENT) -m "gem version $(GEMVERSION) pushed"
deltag:
	git tag --delete $(GIT_TAG_CURRENT)
commit:
	git commit -a
# eq to: git push origin master
push:
	git push
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
