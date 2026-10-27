# PDF theme

Theme of [gfm2pdf-toolchain](https://github.com/laurent-martin/gfm2pdf-toolchain) for the PDF documents of
`aspera-cli` and of other IBM Aspera projects: images at the top and bottom of the cover and last pages, and fonts
IBM Plex Sans and IBM Plex Mono.

A project selects it with the env var or `make` variable `GFM2PDF_THEME`, e.g.:

```shell
export GFM2PDF_THEME=$ASPERA_CLI_HOME/build/doc/pdf_theme
```
