# frozen_string_literal: true

require 'rmagick' # https://rmagick.github.io/index.html
require 'rainbow'
require 'io/console'
module Aspera
  module Preview
    # Generates a string that can display an image in a terminal
    class Terminal
      # quantum depth is 8 or 16: convert xc: -format "%q" info:
      # Rainbow only supports 8-bit colors
      SHIFT_FOR_8_BIT = Magick::MAGICKCORE_QUANTUM_DEPTH - 8
      private_constant :SHIFT_FOR_8_BIT
      class << self
        def build(blob, reserved_lines: 0, double_precision: true)
          # TODO: retrieve terminal font ratio using some termcap ?
          font_ratio = 1.7
          height_ratio = double_precision ? 2.0 : 1.0
          (term_rows, term_columns) = IO.console.winsize
          term_rows -= reserved_lines
          image = Magick::ImageList.new.from_blob(blob)
          # compute scaling to fit terminal
          chosen_factor = [term_rows / image.rows.to_f, term_columns / image.columns.to_f].min
          image = image.scale((image.columns * chosen_factor * font_ratio).to_i, (image.rows * chosen_factor * height_ratio).to_i)
          # get all pixel colors, adjusted for Rainbow
          pixel_colors = []
          image.each_pixel do |pixel, col, row|
            pixel_rgb = [pixel.red, pixel.green, pixel.blue]
            pixel_rgb = pixel_rgb.map { |color| color >> SHIFT_FOR_8_BIT } unless SHIFT_FOR_8_BIT.eql?(0)
            # init 2-dim array
            pixel_colors[row] ||= []
            pixel_colors[row][col] = pixel_rgb
          end
          # now generate text
          text_pixels = []
          pixel_colors.each_with_index do |row_data, row|
            next if double_precision && row.odd?
            row_data.each_with_index do |pixel_rgb, col|
              text_pixels.push("\n") if col.eql?(0) && !row.eql?(0)
              if double_precision
                text_pixels.push(Rainbow('▄').background(pixel_rgb).foreground(pixel_colors[row + 1][col]))
              else
                text_pixels.push(Rainbow(' ').background(pixel_rgb))
              end
            end
          end
          return text_pixels.join
        end
    end # class << self
    end # class Terminal
  end # module Preview
end # module Aspera
