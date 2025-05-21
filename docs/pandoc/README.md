# Template makefile to generate PDF from markdown using pandoc

Generate PDF manual using report type from markdown file.

## Usage

1. In a folder, create a markdown file, e.g. `README.md`
1. create a Makefile like this:

```makefile
include .../path_to_this_folder/pandoc.mak
all: README.pdf
clean:
    rm -f README.pdf
```

There is a default target for `Foo.pdf` from `Foo.md`.

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
