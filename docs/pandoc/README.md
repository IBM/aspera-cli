# Template makefile to generate PDF from markdown using pandoc

## Usage

1. In a folder, create a markdown file, e.g. README.md
1. create a Makefile like this:

```makefile
DIR_PANDOC=$(HOME)/path_to_this_folder/
include $(DIR_PANDOC)pandoc.mak
PANDOC_SUBTITLE=My Subtitle
all: README.pdf
clean:
    rm -f README.pdf
```

> **Note:** The variable `DIR_PANDOC` should point to the folder where the file `pandoc.mak` is located and end with a `/`.

1. Run `make` to generate the PDF file.
