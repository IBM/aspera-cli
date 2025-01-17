# See README.md for more information
DIR_PANDOC := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
PANDOC_DEPS=\
$(DIR_PANDOC)manual_pandoc_defaults.yaml \
$(DIR_PANDOC)manual_include_in_header.tex \
$(DIR_PANDOC)manual_include_after_body.tex \
$(DIR_PANDOC)pandoc.mak
define markdown_to_pdf
$(2): $(1) $$(PANDOC_DEPS)
	-sed -n '/PANDOC_META_BEGIN/,/PANDOC_META_END/p' $$< | grep -v PANDOC_META > $$<.pandoc_meta
	set -x &&\
	if git status --porcelain $$< > /dev/null 2>&1 && test -z "$$$$(git status --porcelain $$<)";then \
	  ref="-r $$$$(git log -1 --pretty="format:%cd" --date=unix $$<)";fi &&\
	GFX_DIR=$$(DIR_PANDOC) pandoc \
		--defaults=$$(DIR_PANDOC)manual_pandoc_defaults.yaml \
		--variable=date:"$$$$(date $$$$ref '+%Y/%m/%d')" \
	    --metadata-file=$$<.pandoc_meta \
		--output=$$@ \
		$$<
	rm -f $$<.pandoc_meta
endef
$(eval $(call markdown_to_pdf,%.md,%.pdf))
