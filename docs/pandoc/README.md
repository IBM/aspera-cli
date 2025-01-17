# Template makefile to generate PDF from markdown using pandoc

## Usage

1. In a folder, create a markdown file, e.g. `README.md`
1. create a Makefile like this:

```makefile
include $(HOME)/path_to_this_folder/pandoc.mak
all: README.pdf
clean:
    rm -f README.pdf
```

1. Run `make` to generate the PDF file.

The markdownfile can include a section like this with pandoc metadata:

```xml
<!--
PANDOC_META_BEGIN
subtitle: "subtitle here"
PANDOC_META_END
-->
```
