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
      private_constant :EXTERNAL_TOOLS, :TEMP_FORMAT, :FFMPEG_DEFAULT_PARAMS

      class << self
        # Check that external tools can be executed
        # @param skip_types [Array<Symbol>] list of tools to skip
        # @return [nil]
        def check_tools(skip_types = [])
          tools_to_check = EXTERNAL_TOOLS.dup
          if skip_types.include?(:office)
            tools_to_check.delete(:unoconv)
            tools_to_check.delete(:soffice)
          end
          # Check for binaries
          tools_to_check.each do |command_sym|
            external_command(command_sym, ['-h'])
          rescue Errno::ENOENT => e
            raise "missing #{command_sym} binary: #{e}"
          rescue
            nil
          end
        end

        # Execute external command
        # @return [nil]
        def external_command(command_sym, command_args)
          Aspera.assert_values(command_sym, EXTERNAL_TOOLS){'command'}
          Environment.secure_execute(command_sym.to_s, *command_args.map(&:to_s), out: File::NULL, err: File::NULL)
          nil
        end

        # Execute external command and get stdout
        # @return [String]
        def external_capture(command_sym, command_args)
          Aspera.assert_values(command_sym, EXTERNAL_TOOLS){'command'}
          Environment.secure_execute(command_sym.to_s, *command_args.map(&:to_s), mode: :capture).first
        end

        # Execute `ffmpeg`
        # @return [nil]
        def ffmpeg(gl_p: FFMPEG_DEFAULT_PARAMS, in_p: [], in_f:, out_p: [], out_f:)
          Aspera.assert_type(gl_p, Array)
          Aspera.assert_type(in_p, Array)
          Aspera.assert_type(out_p, Array)
          external_command(:ffmpeg, gl_p +  in_p + ['-i', in_f] + out_p + [out_f])
        end

        # @return Float in seconds
        def video_get_duration(input_file)
          return external_capture(:ffprobe, [
            '-loglevel', 'error',
            '-show_entries', 'format=duration',
            '-print_format', 'default=noprint_wrappers=1:nokey=1', # cspell:disable-line
            input_file
          ]).to_f
        end

        # File output format, including temp folder
        def ffmpeg_fmt(temp_folder)
          return File.join(temp_folder, TEMP_FORMAT)
        end

        def get_tmp_num_filepath(temp_folder, file_number)
          # Format using {Kernel.format}
          return File.join(temp_folder, format(TEMP_FORMAT, file_number))
        end

        def video_dupe_frame(temp_folder, index, count)
          input_file = get_tmp_num_filepath(temp_folder, index)
          1.upto(count) do |i|
            FileUtils.ln_s(input_file, get_tmp_num_filepath(temp_folder, index + i))
          end
        end

        def video_blend_frames(temp_folder, index_begin, index_end)
          img1 = get_tmp_num_filepath(temp_folder, index_begin)
          img2 = get_tmp_num_filepath(temp_folder, index_end)
          count = index_end - index_begin - 1
          1.upto(count) do |i|
            percent = i * 100 / (count + 1)
            filename = get_tmp_num_filepath(temp_folder, index_begin + i)
            external_command(:magick, ['composite', '-blend', percent, img2, img1, filename])
          end
        end

        # Dump a frame from a video file
        # @param input_file [String] the input file path
        # @param offset_seconds [Integer] the offset in seconds
        # @param scale [String] the scale of the output frame
        # @param output_file [String] the output file path
        # @return [nil]
        def video_dump_frame(input_file, offset_seconds, scale, output_file)
          ffmpeg(
            in_f: input_file,
            in_p: ['-ss', offset_seconds],
            out_f: output_file,
            out_p: ['-frames:v', 1, '-filter:v', "scale=#{scale}"]
          )
        end
      end
    end
  end
end
