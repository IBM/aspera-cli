# See README.md for more information
DIR_PANDOC := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
DOC_GENERATOR := $(DIR_PANDOC)../../lib/pandoc.rb
PANDOC_DEPS := $(shell ruby $(DOC_GENERATOR) deps) $(DIR_PANDOC)pandoc.mak $(DOC_GENERATOR)

define markdown_to_pdf
$(2): $(1) $$(PANDOC_DEPS)
	$(DOC_GENERATOR) pdf $$< $$@
endef

define markdown_to_html
$(2): $(1) $$(PANDOC_DEPS)
	$(DOC_GENERATOR) html $$< $$@
endef

$(eval $(call markdown_to_pdf,%.md,%.pdf))
