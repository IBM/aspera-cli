# frozen_string_literal: true

# cspell:ignore ffprobe optipng unoconv soffice
require 'aspera/log'
require 'aspera/assert'
require 'English'
require 'tmpdir'
require 'fileutils'
require 'open3'

module Aspera
  module Preview
    class Utils
      # External binaries used
      EXTERNAL_TOOLS = %i[ffmpeg ffprobe magick optipng unoconv soffice].freeze
      # File name format for temporary files, used by both ffmpeg and ruby(Kernel.format)
      TEMP_FORMAT = 'img%04d.jpg'
      # default parameters for ffmpeg
      FFMPEG_DEFAULT_PARAMS = [
        '-y', # overwrite output without asking
        '-loglevel', 'error' # show only errors and up
      ].freeze
      # Preferred H.264 encoders in order: best quality/compatibility first.
      H264_ENCODER_PREFERENCE = %w[libx264 libopenh264 h264_nvenc h264_amf h264_qsv h264_vaapi h264_v4l2m2m].freeze
      private_constant :EXTERNAL_TOOLS, :TEMP_FORMAT, :FFMPEG_DEFAULT_PARAMS, :H264_ENCODER_PREFERENCE

      class << self
        # @param tool [Symbol] either `unoconv` or `soffice`
        attr_accessor :office_tool

        # Return the first H.264 encoder available in the local ffmpeg installation.
        # Result is memoized after the first call.
        # @return [String] encoder name (e.g. 'libx264', 'libopenh264')
        # @raise [RuntimeError] if no supported H.264 encoder is found
        def available_h264_encoder
          return @available_h264_encoder if defined?(@available_h264_encoder)
          stdout, = execute(:ffmpeg, '-encoders', mode: :capture, exception: false)
          available = stdout.lines.grep(/h264/i).map { |l| l.split[1] }
          @available_h264_encoder = H264_ENCODER_PREFERENCE.find { |enc| available.include?(enc) }
          Aspera.assert(@available_h264_encoder) { "No supported H.264 encoder found in ffmpeg. Available: #{available.join(', ')}" }
          @available_h264_encoder
        end

        # Check that external tools can be executed.
        # @param skip_types [Array<Symbol>] list of tools to skip
        # @raise [RuntimeError] if a required tool binary is missing
        # @return [nil]
        def check_tools(skip_types = [])
          tools_to_check = EXTERNAL_TOOLS.dup
          tools_to_check.delete(:unoconv) if skip_types.include?(:office) || office_tool.eql?(:soffice)
          tools_to_check.delete(:soffice) if skip_types.include?(:office) || office_tool.eql?(:unoconv)
          # Check for binaries
          tools_to_check.each do |command_sym|
            silent_execute(command_sym, '-h')
          rescue Errno::ENOENT => e
            raise "missing #{command_sym} binary: #{e}"
          rescue
            nil
          end
        end

        # Execute external command, verify it is in the supported list.
        # @param args [Array] command name followed by CLI arguments
        # @param kwargs [Hash] execution options passed to {Environment.secure_execute}
        # @raise [Aspera::AssertError] if the command is not in {EXTERNAL_TOOLS}
        # @return [Array<String>] captured stdout and stderr lines depending on mode
        def execute(*args, **kwargs)
          Aspera.assert_values(args.first, EXTERNAL_TOOLS) { 'command' }
          Environment.secure_execute(*args, **kwargs)
        end

        # Execute external command, capturing and discarding output unless it fails.
        # On failure, the captured stderr is included in the raised exception message.
        # @param args [Array] command name followed by CLI arguments
        # @return [nil]
        def silent_execute(*args)
          execute(*args, mode: :capture)
          nil
        end

        # Execute `ffmpeg`, capturing output.
        # On failure, the ffmpeg stderr is logged at debug level and re-raised.
        # @param in [Array] input file path followed by input options
        # @param out [Array] output file path followed by output options
        # @param global [Array<String>] global options for ffmpeg
        # @return [nil]
        def ffmpeg(in:, out:, global: FFMPEG_DEFAULT_PARAMS)
          Aspera.assert_type(global, Array)
          # NOTE: cannot use just "in", as it is a reserved word in ruby
          in_args = binding.local_variable_get(:in).dup
          out_args = out.dup
          Aspera.assert_type(in_args, Array)
          Aspera.assert_type(out_args, Array)
          in_file = in_args.shift
          out_file = out_args.shift
          execute(:ffmpeg, *global, *in_args, '-i', in_file, *out_args, out_file, mode: :capture)
          nil
        end

        # Get duration of a video file using `ffprobe`.
        # @param input_file [String] path to video file
        # @return [Float] duration in seconds
        def video_get_duration(input_file)
          return execute(
            :ffprobe,
            '-loglevel', 'error',
            '-show_entries', 'format=duration',
            '-print_format', 'default=noprint_wrappers=1:nokey=1', # cspell:disable-line
            input_file,
            mode: :capture
          ).first.to_f
        end

        # File output pattern for ffmpeg, including temp folder.
        # @param temp_folder [String] path to temp folder
        # @return [String] file path pattern
        def ffmpeg_fmt(temp_folder)
          return File.join(temp_folder, TEMP_FORMAT)
        end

        # Get numbered temporary file path.
        # @param temp_folder [String] path to temp folder
        # @param file_number [Integer] frame index
        # @return [String] file path
        def get_tmp_num_filepath(temp_folder, file_number)
          return File.join(temp_folder, format(TEMP_FORMAT, file_number))
        end

        # Duplicate a video frame by creating symlinks.
        # @param temp_folder [String] path to temp folder
        # @param index [Integer] frame index to duplicate
        # @param count [Integer] number of duplicate frames to create
        # @return [nil]
        def video_dupe_frame(temp_folder, index, count)
          input_file = get_tmp_num_filepath(temp_folder, index)
          1.upto(count) do |i|
            FileUtils.ln_s(input_file, get_tmp_num_filepath(temp_folder, index + i))
          end
          nil
        end

        # Blend transition frames between two keyframes using ImageMagick.
        # @param temp_folder [String] path to temp folder
        # @param index_begin [Integer] starting frame index
        # @param index_end [Integer] ending frame index
        # @return [nil]
        def video_blend_frames(temp_folder, index_begin, index_end)
          img1 = get_tmp_num_filepath(temp_folder, index_begin)
          img2 = get_tmp_num_filepath(temp_folder, index_end)
          count = index_end - index_begin - 1
          1.upto(count) do |i|
            percent = i * 100 / (count + 1)
            filename = get_tmp_num_filepath(temp_folder, index_begin + i)
            silent_execute(:magick, 'composite', '-blend', percent, img2, img1, filename)
          end
          nil
        end

        # Dump a frame from a video file
        # @param input_file [String] the input file path
        # @param offset_seconds [Integer] the offset in seconds
        # @param scale [String] the scale of the output frame
        # @param output_file [String] the output file path
        # @return [nil]
        def video_dump_frame(input_file, offset_seconds, scale, output_file)
          ffmpeg(
            in:  [input_file, '-ss', offset_seconds],
            out: [output_file, '-frames:v', 1, '-filter:v', "scale='#{scale}'"]
          )
        end

        # Parse the output of `magick identify -list font` command
        # @param output [String] the output from `magick -list font`
        # @return [Hash] with keys :path and :fonts
        #   :path [String] the path to the type.xml file
        #   :fonts [Array<Hash>] array of font hashes with keys:
        #     :name, :family, :style, :stretch, :weight, :metrics, :glyphs, :index
        def parse_magick_fonts(output)
          result = {path: nil, fonts: []}
          current_font = nil
          output.each_line do |line|
            line = line.strip
            # Parse the Path line
            if line.start_with?('Path:')
              result[:path] = line.sub(/^Path:\s*/, '')
            # Parse Font name
            elsif line.start_with?('Font:')
              # Save previous font if exists
              result[:fonts] << current_font if current_font
              # Start new font
              current_font = {name: line.sub(/^Font:\s*/, '')}
            # Parse font properties
            elsif current_font && line.include?(':')
              key, value = line.split(':', 2)
              key = key.strip.gsub(/\s+/, '_').to_sym
              value = value.strip
              # Convert numeric values
              value = value.to_i if key == :weight || key == :index
              current_font[key] = value
            end
          end
          # Don't forget the last font
          result[:fonts] << current_font if current_font
          result
        end
      end
    end
  end
end
