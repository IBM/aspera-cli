# See README.md for more information
DIR_PANDOC := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
DEF_COMMON=$(DIR_PANDOC)defaults_common.yaml
DEF_PDF=$(DIR_PANDOC)defaults_pdf.yaml
DEF_HTML=$(DIR_PANDOC)defaults_html.yaml
PANDOC_DEPS=\
$(DIR_PANDOC)break_replace.lua \
$(DEF_COMMON) \
$(DEF_PDF) \
$(DEF_HTML) \
$(DIR_PANDOC)find_admonition.lua \
$(DIR_PANDOC)gfm_admonition.css \
$(DIR_PANDOC)gfm_admonition.lua \
$(DIR_PANDOC)pdf_after_body.tex \
$(DIR_PANDOC)pdf_in_header.tex \
$(DIR_PANDOC)pandoc.mak

define markdown_to_pdf
$(2): $(1) $$(PANDOC_DEPS)
	-sed -n '/PANDOC_META_BEGIN/,/PANDOC_META_END/p' $$< | grep -v PANDOC_META > $$<.pandoc_meta
	set -x &&\
	if git status --porcelain $$< > /dev/null 2>&1 && test -z "$$$$(git status --porcelain $$<)";then \
	  ref="-r $$$$(git log -1 --pretty="format:%cd" --date=unix $$<)";fi &&\
	GFX_DIR=$$(DIR_PANDOC) pandoc \
		--defaults=$$(DEF_COMMON) \
		--defaults=$$(DEF_PDF) \
		--variable=date:"$$$$(/bin/date $$$$ref '+%Y/%m/%d')" \
	    --metadata-file=$$<.pandoc_meta \
		--output=$$@ \
		$$<
	rm -f $$<.pandoc_meta
endef

define markdown_to_html
$(2): $(1) $$(PANDOC_DEPS)
	pandoc \
		--defaults=$$(DEF_COMMON) \
		--defaults=$$(DEF_HTML) \
		--output=$$@ \
		$$<
endef

$(eval $(call markdown_to_pdf,%.md,%.pdf))
