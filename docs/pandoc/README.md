# Template makefile to generate PDF from markdown using pandoc

Generate PDF manual using report type from markdown file.

## Usage

1. In a folder, create a markdown file, e.g. `README.md`
1. Set an env var to where this library is located:

```shell
export DIR_PANDOC=.../path_to_this_folder
```

1. Create a Makefile like this:

```makefile
include $(DIR_PANDOC)/pandoc.mak
all: README.pdf
clean:
    rm -f README.pdf
```

There is a default target for `%.pdf` from `%.md`.

If the source and destination have different basenames or path, then it is possible to do:

```makefile
$(eval $(call markdown_to_pdf,source.md,target.pdf))
```

1. Run `make` to generate the PDF file.

The markdown file can include a section like this with `pandoc` metadata:

```xml
<!--
PANDOC_META_BEGIN
subtitle: "subtitle here"
author: "Johnny Beegood"
PANDOC_META_END
-->
```
