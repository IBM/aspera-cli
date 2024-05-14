# frozen_string_literal: true

# cspell:words Magick MAGICKCORE ITERM mintty winsize termcap

require 'rainbow'
require 'io/console'
require 'aspera/log'
module Aspera
  module Preview
    # Display a picture in the terminal, either using coloured characters or iTerm2
    class Terminal
      # Rainbow only supports 8-bit colors
      # env vars to detect terminal type
      TERM_ENV_VARS = %w[TERM_PROGRAM LC_TERMINAL].freeze
      # terminal names that support iTerm2 image display
      ITERM_NAMES = %w[iTerm WezTerm mintty].freeze
      # TODO: retrieve terminal font ratio using some termcap ?
      # ratio = font height / font width
      DEFAULT_FONT_RATIO = 32.0 / 14.0
      private_constant :TERM_ENV_VARS, :ITERM_NAMES, :DEFAULT_FONT_RATIO
      class << self
        # @return [String] the image as text, or the iTerm2 escape sequence
        # @param blob [String] the image as a binary string
        # @param reserve [Integer] number of lines to reserve for other text than the image
        # @param text [Boolean] true to display the image as text, false to use iTerm2
        # @param double [Boolean] true to use colors on half lines, false to use colors on full lines
        # @param font_ratio [Float] ratio = font height / font width
        def build(blob, reserve: 3, text: false, double: true, font_ratio: DEFAULT_FONT_RATIO)
          return iterm_display_image(blob) if iterm_supported? && !text
          begin
            # do not require statically, as the package is optional
            require 'rmagick' # https://rmagick.github.io/index.html
          rescue LoadError => e
            Log.log.error('Install missing gem: gem install rmagick')
            # fallback to iterm, if supported
            return iterm_display_image(blob) if iterm_supported?
            Log.log.error('Cant display picture.')
            raise e
          end
          image = Magick::ImageList.new.from_blob(blob)
          (term_rows, term_columns) = IO.console.winsize
          term_rows -= reserve
          # compute scaling to fit terminal
          fit_term_ratio = [term_rows.to_f * font_ratio / image.rows.to_f, term_columns.to_f / image.columns.to_f].min
          height_ratio = double ? 2.0 : 1.0
          image = image.scale((image.columns * fit_term_ratio).to_i, (image.rows * fit_term_ratio * height_ratio / font_ratio).to_i)
          # quantum depth is 8 or 16, see: `convert xc: -format "%q" info:`
          shift_for_8_bit = Magick::MAGICKCORE_QUANTUM_DEPTH - 8
          # get all pixel colors, adjusted for Rainbow
          pixel_colors = []
          image.each_pixel do |pixel, col, row|
            pixel_rgb = [pixel.red, pixel.green, pixel.blue]
            pixel_rgb = pixel_rgb.map { |color| color >> shift_for_8_bit } unless shift_for_8_bit.eql?(0)
            # init 2-dim array
            pixel_colors[row] ||= []
            pixel_colors[row][col] = pixel_rgb
          end
          # now generate text
          text_pixels = []
          pixel_colors.each_with_index do |row_data, row|
            next if double && (row.odd? || row.eql?(pixel_colors.length - 1))
            row_data.each_with_index do |pixel_rgb, col|
              text_pixels.push("\n") if col.eql?(0) && !row.eql?(0)
              if double
                text_pixels.push(Rainbow('▄').background(pixel_rgb).foreground(pixel_colors[row + 1][col]))
              else
                text_pixels.push(Rainbow(' ').background(pixel_rgb))
              end
            end
          end
          return text_pixels.join
        end

        # display image in iTerm2
        # https://iterm2.com/documentation-images.html
        def iterm_display_image(blob)
          # image = Magick::ImageList.new.from_blob(blob)
          # parameters for iTerm2 image display
          arguments = {
            inline:              1,
            preserveAspectRatio: 1,
            size:                blob.length
            # width:               image.columns,
            # height:              image.rows
          }.map { |k, v| "#{k}=#{v}" }.join(';')
          # \a is BEL, \e is ESC : https://github.com/ruby/ruby/blob/master/doc/syntax/literals.rdoc#label-Strings
          # escape sequence for iTerm2 image display
          return "\e]1337;File=#{arguments}:#{Base64.encode64(blob)}\a"
        end

        # @return [Boolean] true if the terminal supports iTerm2 image display
        def iterm_supported?
          TERM_ENV_VARS.each do |env_var|
            return true if ITERM_NAMES.any? { |term| ENV[env_var]&.include?(term) }
          end
          false
        end
      end
    end
  end
end
