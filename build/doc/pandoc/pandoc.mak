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
TEX_ADD_SUFFIX=.pandoc_add.tex
META_ADD_SUFFIX=.pandoc_meta.yaml

define markdown_to_pdf
$(2): $(1) $$(PANDOC_DEPS)
	-sed -n '/PANDOC_META_BEGIN/,/PANDOC_META_END/p' $$< | grep -v PANDOC_META > $$<$(META_ADD_SUFFIX)
	echo '\\graphicspath{{$(DIR_PANDOC)}}' > $$<$(TEX_ADD_SUFFIX)
	set -x &&\
	if git status --porcelain $$< > /dev/null 2>&1 && test -z "$$$$(git status --porcelain $$<)";then \
	  ref="-r $$$$(git log -1 --pretty="format:%cd" --date=unix $$<)";fi &&\
	  pandoc \
	    --include-in-header=$$<$(TEX_ADD_SUFFIX) \
		--defaults=$$(DEF_COMMON) \
		--defaults=$$(DEF_PDF) \
		--variable=date:"$$$$(/bin/date $$$$ref '+%Y/%m/%d')" \
	    --metadata-file=$$<$(META_ADD_SUFFIX) \
		--output=$$@ \
		$$<
	rm -f $$<$(META_ADD_SUFFIX) $$<$(TEX_ADD_SUFFIX)
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
