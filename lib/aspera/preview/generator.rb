# frozen_string_literal: true

# ffmpeg options:
# spellchecker:ignore soffice pauseframes libx264 trunc bufsize muxer apng libmp3lame maxrate posterize movflags faststart
# spellchecker:ignore palettegen paletteuse pointsize bordercolor repage lanczos unoconv optipng reencode conv transframes

require 'aspera/preview/options'
require 'aspera/preview/utils'
require 'aspera/preview/file_types'
require 'aspera/log'
require 'aspera/assert'

module Aspera
  module Preview
    # Generates one preview file for one format for one file at a time.
    class Generator
      # Values for preview_format: output format.
      PREVIEW_FORMATS = %i[png mp4].freeze

      # List of valid ffmpeg option keys for reencode configuration.
      FFMPEG_OPTIONS_LIST = %w[in out].freeze

      # CLI needs to know conversion type to know if need skip it.
      # One of CONVERSION_TYPES.
      attr_reader :conversion_type, :destination

      # Node API MIME types are from: http://svn.apache.org/repos/asf/httpd/httpd/trunk/docs/conf/mime.types.
      # The resulting preview file type is taken from destination file extension.
      # Conversion methods are provided by private methods: convert_<conversion_type>_to_<preview_format>.
      #   -> conversion_type is one of FileTypes::CONVERSION_TYPES.
      #   -> preview_format is one of Generator::PREVIEW_FORMATS.
      # The conversion video->mp4 is implemented in methods: convert_video_to_mp4_using_<video_conversion>.
      #  -> conversion method is one of Generator::VIDEO_CONVERSION_METHODS.
      # @param src [String] Source file path.
      # @param dst [String] Destination file path.
      # @param options [Options] All conversion options.
      # @param main_temp_dir [String] Main temp folder, sub folder will be created for generation.
      # @param mime [String, nil] Optional MIME type as provided by node api (or nil).
      def initialize(src, dst, options, main_temp_dir, mime: nil)
        # Source file path
        @source = src
        # Destination file path
        @destination = dst
        @options = options
        # temp folder name based on source file
        @temp_folder = File.join(main_temp_dir, @source.split('/').last.gsub(/\s/, '_').gsub(/\W/, ''))
        # Extract preview format from extension of target file.
        @preview_format_sym = File.extname(@destination).gsub(/^\./, '').to_sym
        conversion_type = FileTypes.instance.conversion_type(@source, mime)
        @processing_method = "convert_#{conversion_type}_to_#{@preview_format_sym}"
        if conversion_type.eql?(:video)
          case @preview_format_sym
          when :mp4
            @processing_method = "#{@processing_method}_using_#{@options.video_conversion}"
          when :png
            @processing_method = "#{@processing_method}_using_#{@options.video_png_conv}"
          end
        end
        @processing_method = @processing_method.to_sym
        Log.log.debug{"method: #{@processing_method}"}
        Aspera.assert(respond_to?(@processing_method, true)){"no processing known for #{conversion_type} -> #{@preview_format_sym}"}
      end

      # Creates preview as specified in constructor.
      def generate
        Log.log.debug{"#{@source}->#{@destination} (#{@processing_method})"}
        begin
          send(@processing_method)
          # Check that generated size does not exceed maximum.
          result_size = File.size(@destination)
          Log.log.warn{"preview size exceeds maximum allowed #{result_size} > #{@options.max_size}"} if result_size > @options.max_size
        ensure
          FileUtils.rm_rf(@temp_folder)
        end
      end

      # Path to error image corresponding to preview type.
      # @return [String] The path to the error image.
      def error_asset
        File.expand_path(@preview_format_sym.eql?(:mp4) ? 'video_error.png' : 'image_error.png', File.dirname(__FILE__))
      end

      private

      # Creates a unique temp folder for file.
      # @return [String] The temporary folder path.
      def this_tmpdir
        FileUtils.mkdir_p(@temp_folder)
        return @temp_folder
      end

      # Calculates offset in seconds for video frame extraction.
      # @param duration [Float] Duration of video in seconds.
      # @param start_offset [Numeric] Start offset of parts in seconds.
      # @param total_count [Integer] Total count of parts.
      # @param index [Integer] Index of part (starts at 1).
      # @return [Float] Offset in seconds suitable for ffmpeg -ss option.
      def get_offset(duration, start_offset, total_count, index)
        Aspera.assert_type(duration, Float){'duration'}
        return start_offset + ((index - 1) * (duration - start_offset) / total_count)
      end

      # Converts video to MP4 using blend method.
      # Extracts key frames and blends them with transitions.
      def convert_video_to_mp4_using_blend
        p_duration = Utils.video_get_duration(@source)
        p_start_offset = @options.video_start_sec.to_i
        p_key_frame_count = @options.blend_keyframes.to_i
        last_keyframe = nil
        current_index = 1
        frame_rate_hz = 30
        1.upto(p_key_frame_count) do |i|
          Utils.video_dump_frame(
            @source,
            get_offset(p_duration, p_start_offset, p_key_frame_count, i),
            @options.video_scale,
            Utils.get_tmp_num_filepath(this_tmpdir, current_index)
          )
          Utils.video_dupe_frame(this_tmpdir, current_index, @options.blend_pauseframes)
          Utils.video_blend_frames(this_tmpdir, last_keyframe, current_index) unless last_keyframe.nil?
          # Go to last dupe frame.
          last_keyframe = current_index + @options.blend_pauseframes
          # Go after last dupe frame and keep space to blend.
          current_index = last_keyframe + 1 + @options.blend_transframes
        end
        Utils.ffmpeg(
          in_f: Utils.ffmpeg_fmt(this_tmpdir),
          in_p: ['-framerate', @options.blend_fps],
          out_f: @destination,
          out_p: [
            '-filter:v', "scale='trunc(iw/2)*2:trunc(ih/2)*2'",
            '-codec:v', 'libx264',
            '-r', frame_rate_hz,
            '-pix_fmt', 'yuv420p'
          ]
        )
      end

      # Converts video to MP4 using clips method.
      # Generates n clips starting at offset and concatenates them.
      def convert_video_to_mp4_using_clips
        p_duration = Utils.video_get_duration(@source)
        file_list_file = File.join(this_tmpdir, 'clip_files.txt')
        File.open(file_list_file, 'w+') do |f|
          1.upto(@options.clips_count.to_i) do |i|
            offset_seconds = get_offset(p_duration, @options.video_start_sec.to_i, @options.clips_count.to_i, i)
            tmp_file_name = format('clip%04d.mp4', i)
            Utils.ffmpeg(
              in_f: @source,
              in_p: ['-ss', offset_seconds * 0.9],
              out_f: File.join(this_tmpdir, tmp_file_name),
              out_p: [
                '-ss', offset_seconds * 0.1,
                '-t', @options.clips_length,
                '-filter:v', "scale=#{@options.video_scale}",
                '-codec:a', 'libmp3lame'
              ]
            )
            f.puts("file '#{tmp_file_name}'")
          end
        end
        # Concat clips.
        Utils.ffmpeg(
          in_f: file_list_file,
          in_p: ['-f', 'concat'],
          out_f: @destination,
          out_p: ['-codec', 'copy']
        )
        File.delete(file_list_file)
      end

      # Converts video to MP4 using re-encoding method.
      # Performs a simple re-encoding with configurable ffmpeg options.
      def convert_video_to_mp4_using_reencode
        options = @options.reencode_ffmpeg
        Aspera.assert_type(options, Hash){'reencode_ffmpeg'}
        options.each do |k, v|
          Aspera.assert_values(k, FFMPEG_OPTIONS_LIST){'key'}
          Aspera.assert_type(v, Array){k}
        end
        Utils.ffmpeg(
          in_f: @source,
          in_p: options['in'] || ['-ss', @options.video_start_sec.to_i * 0.9],
          out_f: @destination,
          out_p: options['out'] || [
            '-t', 60,
            '-codec:v', 'libx264',
            '-profile:v', 'high',
            '-pix_fmt', 'yuv420p',
            '-preset', 'slow',
            '-b:v', '500k',
            '-maxrate', '500k',
            '-bufsize', '1000k',
            '-filter:v', "scale=#{@options.video_scale}",
            '-threads', '0',
            '-codec:a', 'libmp3lame',
            '-ac', '2',
            '-b:a', '128k',
            '-movflags', 'faststart'
          ]
        )
      end

      # Converts video to PNG using fixed frame method.
      # Generates a static thumbnail at a specific time offset.
      def convert_video_to_png_using_fixed
        Utils.video_dump_frame(
          @source,
          Utils.video_get_duration(@source) * @options.thumb_vid_fraction,
          @options.thumb_vid_scale,
          @destination
        )
      end

      # Converts video to animated PNG (APNG).
      # Creates an animated thumbnail with looping.
      # @see https://trac.ffmpeg.org/wiki/SponsoringPrograms/GSoC/2015#AnimatedPortableNetworkGraphicsAPNG
      def convert_video_to_png_using_animated
        p_duration = Utils.video_get_duration(@source)
        p_start_offset = @options.video_start_sec.to_i
        p_max_duration = @options.clips_length.to_i
        # If video is shorter than start offset + duration, adjust to capture from start.
        if p_duration <= (p_start_offset + p_max_duration)
          p_start_offset = 0
          p_max_duration = p_duration
        end
        Utils.ffmpeg(
          in_f: @source,
          in_p: [
            '-ss', p_start_offset,
            '-t', p_max_duration
          ],
          out_f: @destination,
          out_p: [
            '-vf', 'fps=5,scale=120:-1:flags=lanczos',
            '-plays', 0, # Loop forever (0 = infinite loop for APNG).
            '-f', 'apng'
          ]
        )
      end

      # Converts office document to PNG.
      # First converts to PDF, then to PNG image.
      def convert_office_to_png
        tmp_pdf_file = File.join(this_tmpdir, "#{File.basename(@source, File.extname(@source))}.pdf")
        case @options.office_conversion
        when :unoconv
          Utils.external_command(:unoconv, [
            '-f', 'pdf',
            '-o', tmp_pdf_file,
            @source
          ])
        when :soffice
          Utils.external_command(:soffice, [
            '--headless',
            '--convert-to', 'pdf',
            '--outdir', File.dirname(tmp_pdf_file),
            @source
          ])
          # soffice creates the file with the source name, so we need to rename it if needed.
          generated_pdf = File.join(File.dirname(tmp_pdf_file), "#{File.basename(@source, File.extname(@source))}.pdf")
          FileUtils.mv(generated_pdf, tmp_pdf_file) if generated_pdf != tmp_pdf_file
        else Aspera.error_unexpected_value(@options.office_conversion){'office_conversion'}
        end
        convert_pdf_to_png(tmp_pdf_file)
      end

      # Converts PDF to PNG image.
      # @param source_file_path [String, nil] Optional source file path, defaults to @source.
      def convert_pdf_to_png(source_file_path = nil)
        source_file_path ||= @source
        Utils.external_command(:magick, [
          'convert',
          '-size', "x#{@options.thumb_img_size}",
          '-background', 'white',
          '-flatten',
          "#{source_file_path}[0]",
          @destination
        ])
      end

      # Converts image to PNG thumbnail.
      # Applies auto-orientation, resizing, and optimization.
      def convert_image_to_png
        Utils.external_command(:magick, [
          'convert',
          '-auto-orient',
          '-thumbnail', "#{@options.thumb_img_size}x#{@options.thumb_img_size}>",
          '-quality', 95,
          '+dither',
          '-posterize', 40,
          "#{@source}[0]",
          @destination
        ])
        Utils.external_command(:optipng, [@destination])
      end

      # Converts plain text to PNG image.
      # Renders first 100 lines of text file as an image.
      def convert_plaintext_to_png
        # Get 100 first lines of text file.
        first_lines = File.foreach(@source).first(100).join
        Utils.external_command(:magick, [
          'convert',
          '-size', "#{@options.thumb_img_size}x#{@options.thumb_img_size}",
          'xc:white', # Define canvas with background color (xc, or canvas) of preceding size.
          '-font', @options.thumb_text_font,
          '-pointsize', 12,
          '-fill', 'black', # Font color.
          '-annotate', '+0+0', first_lines,
          '-trim', # Avoid large blank regions.
          '-bordercolor', 'white',
          '-border', 8,
          '+repage',
          @destination
        ])
      end
    end
  end
end
