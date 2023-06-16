# frozen_string_literal: true

require 'rmagick' # https://rmagick.github.io/index.html
require 'rainbow'
require 'io/console'
module Aspera
  module Preview
    # function conversion_type returns one of the types: CONVERSION_TYPES
    class Terminal
      class << self
        def build(blob, reserved_lines: 0)
          # TODO: retrieve terminal ratio using
          font_ratio = 1.7
          (term_rows, term_columns) = IO.console.winsize
          term_rows -= reserved_lines
          image = Magick::ImageList.new.from_blob(blob)
          chosen_factor = [term_rows / image.rows.to_f, term_columns / image.columns.to_f].min
          image = image.scale((image.columns * chosen_factor * font_ratio).to_i, (image.rows * chosen_factor).to_i)
          text_pixels = []
          image.each_pixel do |pixel, col, row|
            text_pixels.push("\n") if col.eql?(0) && !row.eql?(0)
            pixel_rgb = [pixel.red, pixel.green, pixel.blue].map do |color|
              # quantum depth is 8 or 16: convert xc: -format "%q" info:
              # Rainbow only supports 8-bit colors
              color >> (Magick::MAGICKCORE_QUANTUM_DEPTH - 8)
            end
            text_pixels.push(Rainbow(' ').background(pixel_rgb))
          end
          return text_pixels.join
        end
    end # class << self
    end # class Terminal
  end # module Preview
end # module Aspera
