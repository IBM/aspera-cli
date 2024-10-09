# See README.md for more information
ifndef DIR_PANDOC
$(error The macro DIR_PANDOC is not set. Please set it and try again.)
endif
PANDOC_DEPS=\
$(DIR_PANDOC)manual_pandoc_defaults.yaml \
$(DIR_PANDOC)manual_include_in_header.tex \
$(DIR_PANDOC)manual_include_after_body.tex \
$(DIR_PANDOC)pandoc.mak
%.pdf: %.md $(PANDOC_DEPS)
	GFX_DIR=$(DIR_PANDOC) pandoc \
	  --defaults=$(DIR_PANDOC)manual_pandoc_defaults.yaml \
	  --variable=date:$$(date '+%Y/%m/%d') \
	  --variable=subtitle:"$(PANDOC_SUBTITLE)" \
	  --output=$@ \
	  $<
