# Template makefile to generate PDF from markdown using pandoc

Generate PDF manual using report type from markdown file.

## Usage

1. In a folder, create a markdown file, e.g. `README.md`
1. Set the `DIR_PANDOC` env var to where this library is located:

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

If the source and destination have different base names or path, then it is possible to do:

```makefile
$(eval $(call markdown_to_pdf,source.md,target.pdf))
```

1. Run `make` to generate the PDF file.

The markdown file can include a section like this with `pandoc` defaults:

```xml
<!--
PANDOC_DEFAULTS_BEGIN
metadata:
  subtitle: "subtitle here"
  author: "Johnny Beegood"
PANDOC_DEFAULTS_END
-->
```

## Tables

- A `<br/>` in a table cell breaks the line (`break_replace.lua`).
- PDF column widths: for a pipe table wider than 72 characters, pandoc takes relative widths from the dashes of the
  separator row. With equal dashes (`| --- | --- |`), `table_widths.lua` computes the widths from the cell contents:
  each column gets at least its longest word, the rest is shared by text length. To set the widths yourself, tune the
  dashes, e.g. `| ---- | ------------------ |`.
- Short (MultiMarkdown) subscripts are disabled: `~600 ms` or `~/.ssh` stay as typed, `H~2~O` is still a subscript.

## Diagrams (draw.io)

`drawio.mak` exports each tab of a draw.io file to an image named after the tab, next to the file, with draw.io
desktop (`../../lib/drawio.rb`). An image is exported again only when older than the draw.io file. The
"Text is not SVG - cannot display" link that draw.io appends to SVG files is removed, as librsvg (used for the PDF)
would display it.

```makefile
include $(DIR_PANDOC)/pandoc.mak
DRAWIO_FILE = images/diagrams.drawio
include $(DIR_PANDOC)/drawio.mak
all: diagrams README.pdf
README.pdf: $(DRAWIO_IMAGES)
```

Optional variables, set before the `include`: `DRAWIO_FORMAT` (default: `svg`), `DRAWIO_OPTIONS` (draw.io CLI
options, default: `--scale 2`).
