# frozen_string_literal: true

# cspell:words Magick MAGICKCORE ITERM mintty winsize termcap

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
      ITERM_NAMES = %w[iTerm WezTerm mintty].freeze
      TERM_ENV_VARS = %w[TERM_PROGRAM LC_TERMINAL].freeze
      private_constant :SHIFT_FOR_8_BIT, :ITERM_NAMES, :TERM_ENV_VARS
      class << self
        def build(blob, reserved_lines: 0, double_precision: true)
          return iterm_display_image(blob) if iterm_supported?
          image = Magick::ImageList.new.from_blob(blob)
          (term_rows, term_columns) = IO.console.winsize
          term_rows -= reserved_lines
          # compute scaling to fit terminal
          fit_term_ratio = [term_rows / image.rows.to_f, term_columns / image.columns.to_f].min
          # TODO: retrieve terminal font ratio using some termcap ?
          font_ratio = 1.7
          height_ratio = double_precision ? 2.0 : 1.0
          image = image.scale((image.columns * fit_term_ratio * font_ratio).to_i, (image.rows * fit_term_ratio * height_ratio).to_i)
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

        # display image in iTerm2
        def iterm_display_image(blob)
          # image = Magick::ImageList.new.from_blob(blob)
          arguments = {
            inline:              1,
            preserveAspectRatio: 1,
            size:                blob.length
            # width:               image.columns,
            # height:              image.rows
          }.map { |k, v| "#{k}=#{v}" }.join(';')
          # \a is BEL, \e is ESC : https://github.com/ruby/ruby/blob/master/doc/syntax/literals.rdoc#label-Strings
          # https://iterm2.com/documentation-images.html
          return "\e]1337;File=#{arguments}:#{Base64.encode64(blob)}\a"
        end

        # @return [Boolean] true if the terminal supports iTerm2 image display
        def iterm_supported?
          TERM_ENV_VARS.each do |env_var|
            return true if ITERM_NAMES.any? { |term| ENV[env_var]&.include?(term) }
          end
          false
        end
      end # class << self
    end # class Terminal
  end # module Preview
end # module Aspera
