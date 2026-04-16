# frozen_string_literal: true

# cspell:words Magick MAGICKCORE ITERM mintty winsize termcap

require 'rainbow'
require 'base64'
require 'io/console'
require 'aspera/log'
require 'aspera/environment'

module Aspera
  module Preview
    module Backend
      # Base decoder that rescales image data to the current terminal geometry.
      class Base
        # @param reserve [Integer] number of terminal rows reserved for non-image output
        # @param double [Boolean] when `true`, render two image rows in one terminal row
        # @param font_ratio [Float] terminal font aspect ratio: height divided by width
        def initialize(reserve:, double:, font_ratio:)
          @reserve = reserve
          @height_ratio = double ? 2.0 : 1.0
          @font_ratio = font_ratio
        end
        Aspera.require_method!(:terminal_pixels)
        # Compute output dimensions that fit inside the terminal while preserving aspect ratio.
        #
        # @param rows [Integer] source image height in pixels
        # @param columns [Integer] source image width in pixels
        # @return [Array<Integer>] scaled width and height for terminal rendering
        def terminal_scaling(rows, columns)
          (term_rows, term_columns) = IO.console.winsize || [24, 80]
          term_rows = [term_rows - @reserve, 2].max
          fit_term_ratio = [term_rows.to_f * @font_ratio / rows.to_f, term_columns.to_f / columns.to_f].min
          [(columns * fit_term_ratio).to_i, (rows * fit_term_ratio * @height_ratio / @font_ratio).to_i]
        end
      end

      class RMagick < Base
        # Initialize the RMagick-backed decoder for a binary image payload.
        #
        # @param blob [String] encoded image binary content
        # @param kwargs [Hash] forwarding options accepted by [`initialize`](lib/aspera/preview/terminal.rb:16)
        def initialize(blob, **kwargs)
          super(**kwargs)
          # Load lazily because this dependency is optional.
          require 'rmagick' # https://rmagick.github.io/index.html
          @image = Magick::ImageList.new.from_blob(blob)
        end

        # Decode the image and return RGB pixels scaled for terminal rendering.
        #
        # @return [Array<Array<Array<Integer>>>] rows of `[red, green, blue]` pixel triplets
        def terminal_pixels
          # ImageMagick channel depth is typically 8 or 16 bits.
          # See: `magick xc: -format "%q" info:`
          shift_for_8_bit = Magick::MAGICKCORE_QUANTUM_DEPTH - 8
          # Extract RGB values and normalize them to 8-bit channels for Rainbow.
          pixel_colors = []
          @image.scale(*terminal_scaling(@image.rows, @image.columns)).each_pixel do |pixel, col, row|
            pixel_rgb = [pixel.red, pixel.green, pixel.blue]
            pixel_rgb = pixel_rgb.map{ |color| color >> shift_for_8_bit} unless shift_for_8_bit.eql?(0)
            # Initialize the destination 2D pixel matrix row by row.
            pixel_colors[row] ||= []
            pixel_colors[row][col] = pixel_rgb
          end
          pixel_colors
        end
      end

      class ChunkyPNG < Base
        # Initialize the ChunkyPNG-backed decoder for a PNG payload.
        #
        # @param blob [String] PNG binary content
        # @param kwargs [Hash] forwarding options accepted by [`initialize`](lib/aspera/preview/terminal.rb:16)
        def initialize(blob, **kwargs)
          super(**kwargs)
          require 'chunky_png'
          @png = ::ChunkyPNG::Image.from_blob(blob)
        end

        # Resize the PNG using nearest-neighbor sampling and return RGB pixel rows.
        #
        # @return [Array<Array<Array<Integer>>>] rows of `[red, green, blue]` pixel triplets
        def terminal_pixels
          src_w = @png.width
          src_h = @png.height
          dst_w, dst_h = terminal_scaling(src_h, src_w)
          dst_w = [dst_w, 1].max
          dst_h = [dst_h, 1].max
          pixel_colors = Array.new(dst_h){Array.new(dst_w)}
          x_ratio = src_w.to_f / dst_w
          y_ratio = src_h.to_f / dst_h
          dst_h.times do |dy|
            sy = (dy * y_ratio).floor
            sy = src_h - 1 if sy >= src_h
            dst_w.times do |dx|
              sx = (dx * x_ratio).floor
              sx = src_w - 1 if sx >= src_w
              rgba = @png.get_pixel(sx, sy)
              # ChunkyPNG stores pixels as 0xRRGGBBAA; extract 8-bit RGB channels.
              pixel_colors[dy][dx] = %i[r g b].map{ |i| ::ChunkyPNG::Color.send(i, rgba)}
            end
          end
          pixel_colors
        end
      end
    end

    # Render an image for terminal output.
    # Uses either colored text blocks or the iTerm2 inline-image protocol when available.
    class Terminal
      # Rainbow only supports 8-bit color values.
      # Environment variables inspected to detect compatible terminal implementations.
      TERM_ENV_VARS = %w[TERM_PROGRAM LC_TERMINAL].freeze
      # Terminal identifiers known to support the iTerm2 inline-image protocol.
      ITERM_NAMES = %w[iTerm WezTerm mintty].freeze
      # Fallback font aspect ratio used to estimate how many image pixels fit in a character cell.
      # Ratio = font height / font width.
      DEFAULT_FONT_RATIO = 32.0 / 14.0
      private_constant :TERM_ENV_VARS, :ITERM_NAMES, :DEFAULT_FONT_RATIO
      class << self
        # Render an image blob for display in the current terminal.
        #
        # @param blob       [String]  The image as a binary string
        # @param text       [Boolean] `true` to display the image as text, `false` to use iTerm2 if supported
        # @param reserve    [Integer] Number of lines to reserve for other text than the image
        # @param double     [Boolean] `true` to use colors on half lines, `false` to use colors on full lines
        # @param font_ratio [Float]   ratio = font height / font width
        # @return [String] The image as text, or the iTerm2 escape sequence
        def build(blob, text: false, reserve: 3, double: true, font_ratio: DEFAULT_FONT_RATIO)
          return '[Image display requires a terminal]' unless Environment.terminal?
          return iterm_display_image(blob) if iterm_supported? && !text
          pixel_colors =
            begin
              Log.log.debug('Trying chunky_png')
              Backend::ChunkyPNG.new(blob, reserve: reserve, double: double, font_ratio: font_ratio).terminal_pixels
            rescue => e
              Log.log.debug(e.message)
              begin
                Log.log.debug('Trying rmagick')
                Backend::RMagick.new(blob, reserve: reserve, double: double, font_ratio: font_ratio).terminal_pixels
              rescue => e
                Log.log.debug(e.message)
                nil
              end
            end
          if pixel_colors.nil?
            return iterm_display_image(blob) if iterm_supported?
            raise 'Cannot decode picture.'
          end
          # Convert decoded pixels into terminal glyphs.
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

        # Build the iTerm2 inline-image escape sequence.
        # https://iterm2.com/documentation-images.html
        #
        # @param blob [String] image binary content
        # @return [String] escape sequence that displays the image inline
        def iterm_display_image(blob)
          # image = Magick::ImageList.new.from_blob(blob)
          # Parameters accepted by the iTerm2 inline-image protocol.
          arguments = {
            inline:              1,
            preserveAspectRatio: 1,
            size:                blob.length
            # width:               image.columns,
            # height:              image.rows
          }.map{ |k, v| "#{k}=#{v}"}.join(';')
          # `\a` is BEL and `\e` is ESC.
          # See: https://github.com/ruby/ruby/blob/master/doc/syntax/literals.rdoc#label-Strings
          # Return the full escape sequence expected by iTerm2-compatible terminals.
          return "\e]1337;File=#{arguments}:#{Base64.strict_encode64(blob)}\a"
        end

        # Detect whether the current terminal supports iTerm2 inline images.
        #
        # @return [Boolean] `true` when the current terminal advertises iTerm2 image support
        def iterm_supported?
          TERM_ENV_VARS.each do |env_var|
            return true if ITERM_NAMES.any?{ |term| ENV[env_var]&.include?(term)}
          end
          false
        end
      end
    end
  end
end
