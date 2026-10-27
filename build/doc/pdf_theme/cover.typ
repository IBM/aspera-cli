// Background of the cover and last pages, for PDF with Typst, see gfm2pdf-toolchain (themes)
#let cover-background = {
  place(top, image("cover_top.png", width: 100%))
  place(bottom, image("cover_bottom.png", width: 100%))
}
