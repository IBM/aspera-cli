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
      # provides image pixels scaled to terminal
      class Base
        def initialize(reserve:, double:, font_ratio:)
          @reserve = reserve
          @height_ratio = double ? 2.0 : 1.0
          @font_ratio = font_ratio
        end
        Aspera.require_method!(:terminal_pixels)
        # compute scaling to fit terminal
        def terminal_scaling(rows, columns)
          (term_rows, term_columns) = IO.console.winsize || [24, 80]
          term_rows = [term_rows - @reserve, 2].max
          fit_term_ratio = [term_rows.to_f * @font_ratio / rows.to_f, term_columns.to_f / columns.to_f].min
          [(columns * fit_term_ratio).to_i, (rows * fit_term_ratio * @height_ratio / @font_ratio).to_i]
        end
      end

      class RMagick < Base
        def initialize(blob, **kwargs)
          super(**kwargs)
          # do not require statically, as the package is optional
          require 'rmagick' # https://rmagick.github.io/index.html
          @image = Magick::ImageList.new.from_blob(blob)
        end

        def terminal_pixels
          # quantum depth is 8 or 16, see: `magick xc: -format "%q" info:`
          shift_for_8_bit = Magick::MAGICKCORE_QUANTUM_DEPTH - 8
          # get all pixel colors, adjusted for Rainbow
          pixel_colors = []
          @image.scale(*terminal_scaling(@image.rows, @image.columns)).each_pixel do |pixel, col, row|
            pixel_rgb = [pixel.red, pixel.green, pixel.blue]
            pixel_rgb = pixel_rgb.map{ |color| color >> shift_for_8_bit} unless shift_for_8_bit.eql?(0)
            # init 2-dim array
            pixel_colors[row] ||= []
            pixel_colors[row][col] = pixel_rgb
          end
          pixel_colors
        end
      end

      class ChunkyPNG < Base
        def initialize(blob, **kwargs)
          super(**kwargs)
          require 'chunky_png'
          @png = ::ChunkyPNG::Image.from_blob(blob)
        end

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
              # ChunkyPNG stores as 0xRRGGBBAA; extract 8-bit channels
              pixel_colors[dy][dx] = %i[r g b].map{ |i| ::ChunkyPNG::Color.send(i, rgba)}
            end
          end
          pixel_colors
        end
      end
    end

    # Display a picture in the terminal.
    # Either use coloured characters or iTerm2 protocol.
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
          }.map{ |k, v| "#{k}=#{v}"}.join(';')
          # \a is BEL, \e is ESC : https://github.com/ruby/ruby/blob/master/doc/syntax/literals.rdoc#label-Strings
          # escape sequence for iTerm2 image display
          return "\e]1337;File=#{arguments}:#{Base64.strict_encode64(blob)}\a"
        end

        # @return [Boolean] true if the terminal supports iTerm2 image display
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
