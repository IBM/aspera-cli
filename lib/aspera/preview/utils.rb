# frozen_string_literal: true

# cspell:ignore ffprobe optipng unoconv
require 'aspera/log'
require 'aspera/assert'
require 'English'
require 'tmpdir'
require 'fileutils'
require 'open3'

module Aspera
  module Preview
    class Utils
      # from bash manual: meta-character need to be escaped
      BASH_SPECIAL_CHARACTERS = "|&;()<> \t#\n"
      # external binaries used
      EXTERNAL_TOOLS = %i[ffmpeg ffprobe convert composite optipng unoconv].freeze
      TEMP_FORMAT = 'img%04d.jpg'
      private_constant :BASH_SPECIAL_CHARACTERS, :EXTERNAL_TOOLS, :TEMP_FORMAT

      class << self
        # returns string with single quotes suitable for bash if there is any bash meta-character
        def shell_quote(argument)
          return argument unless argument.chars.any?{|c|BASH_SPECIAL_CHARACTERS.include?(c)}
          # surround with single quotes, and escape single quotes
          return %Q{'#{argument.gsub("'"){|_s| %q{'"'"'}}}'}
        end

        # check that external tools can be executed
        def check_tools(skip_types=[])
          tools_to_check = EXTERNAL_TOOLS.dup
          tools_to_check.delete(:unoconv) if skip_types.include?(:office)
          # Check for binaries
          tools_to_check.each do |command_sym|
            external_command(command_sym, ['-h'], out: File::NULL)
          rescue Errno::ENOENT => e
            raise "missing #{command_sym} binary: #{e}"
          rescue
            nil
          end
        end

        # execute external command
        # one could use "system", but we would need to redirect stdout/err
        # @return nil
        def external_command(command_sym, command_args)
          Aspera.assert_values(command_sym, EXTERNAL_TOOLS){'command'}
          Environment.secure_execute(exec: command_sym.to_s, args: command_args.map(&:to_s), out: File::NULL, err: File::NULL)
        end

        def external_capture(command_sym, command_args)
          Aspera.assert_values(command_sym, EXTERNAL_TOOLS){'command'}
          return Environment.secure_capture(exec: command_sym.to_s, args: command_args.map(&:to_s))
        end

        def ffmpeg(a)
          Aspera.assert_type(a, Hash)
          # input_file,input_args,output_file,output_args
          a[:gl_p] ||= [
            '-y', # overwrite output without asking
            '-loglevel', 'error' # show only errors and up
          ]
          a[:in_p] ||= []
          a[:out_p] ||= []
          Aspera.assert(%i[gl_p in_f in_p out_f out_p].eql?(a.keys.sort)){"wrong params (#{a.keys.sort})"}
          external_command(:ffmpeg, [a[:gl_p], a[:in_p], '-i', a[:in_f], a[:out_p], a[:out_f]].flatten)
        end

        # @return Float in seconds
        def video_get_duration(input_file)
          return external_capture(:ffprobe, [
            '-loglevel', 'error',
            '-show_entries', 'format=duration',
            '-print_format', 'default=noprint_wrappers=1:nokey=1', # cspell:disable-line
            input_file]).to_f
        end

        def ffmpeg_fmt(temp_folder)
          return File.join(temp_folder, TEMP_FORMAT)
        end

        def get_tmp_num_filepath(temp_folder, file_number)
          return File.join(temp_folder, format(TEMP_FORMAT, file_number))
        end

        def video_dupe_frame(temp_folder, index, count)
          input_file = get_tmp_num_filepath(temp_folder, index)
          1.upto(count) do |i|
            FileUtils.ln_s(input_file, get_tmp_num_filepath(temp_folder, index + i))
          end
        end

        def video_blend_frames(temp_folder, index1, index2)
          img1 = get_tmp_num_filepath(temp_folder, index1)
          img2 = get_tmp_num_filepath(temp_folder, index2)
          count = index2 - index1 - 1
          1.upto(count) do |i|
            percent = i * 100 / (count + 1)
            filename = get_tmp_num_filepath(temp_folder, index1 + i)
            external_command(:composite, ['-blend', percent, img2, img1, filename])
          end
        end

        def video_dump_frame(input_file, offset_seconds, scale, output_file, index=nil)
          output_file = get_tmp_num_filepath(output_file, index) unless index.nil?
          ffmpeg(
            in_f: input_file,
            in_p: ['-ss', offset_seconds],
            out_f: output_file,
            out_p: ['-frames:v', 1, '-filter:v', "scale=#{scale}"])
          return output_file
        end
      end
    end
  end
end
