# frozen_string_literal: true

require 'English'
require 'tmpdir'
require 'fileutils'
require 'aspera/log'
require 'open3'

module Aspera
  module Preview
    class Utils
      # from bash manual: meta-character need to be escaped
      BASH_SPECIAL_CHARACTERS = "|&;()<> \t#\n"
      # shell exit code when command is not found
      BASH_EXIT_NOT_FOUND = 127
      # external binaries used
      EXPERNAL_TOOLS = %i[ffmpeg ffprobe convert composite optipng unoconv].freeze
      TMPFMT = 'img%04d.jpg'
      private_constant :BASH_SPECIAL_CHARACTERS,:BASH_EXIT_NOT_FOUND,:EXPERNAL_TOOLS,:TMPFMT

      class << self
        # returns string with single quotes suitable for bash if there is any bash metacharacter
        def shell_quote(argument)
          return argument unless argument.chars.any?{|c|BASH_SPECIAL_CHARACTERS.include?(c)}
          return "'" + argument.gsub(/'/){|_s| "'\"'\"'"} + "'"
        end

        # check that external tools can be executed
        def check_tools(skip_types=[])
          EXPERNAL_TOOLS.delete(:unoconv) if skip_types.include?(:office)
          # Check for binaries
          EXPERNAL_TOOLS.each do |command_symb|
            external_command(command_symb,['-h'])
          end
        end

        # execute external command
        # one could use "system", but we would need to redirect stdout/err
        # @return true if su
        def external_command(command_symb,command_args)
          raise "unexpected command #{command_symb}" unless EXPERNAL_TOOLS.include?(command_symb)
          # build command line, and quote special characters
          command = command_args.clone.unshift(command_symb).map{|i| shell_quote(i.to_s)}.join(' ')
          Log.log.debug("cmd=#{command}".blue)
          # capture3: only in ruby2+
          if Open3.respond_to?(:capture3)
            stdout, stderr, exit_status = Open3.capture3(command)
          else
            stderr = '<merged with stdout>'
            stdout = %x(#{command} 2>&1)
            exit_status = $CHILD_STATUS
          end
          if BASH_EXIT_NOT_FOUND.eql?(exit_status)
            raise "Error: #{command_symb} is not in the PATH"
          end
          unless exit_status.success?
            Log.log.error("commandline: #{command}")
            Log.log.error("Error code: #{exit_status}")
            Log.log.error("stdout: #{stdout}")
            Log.log.error("stderr: #{stderr}")
            raise "#{command_symb} error #{exit_status}"
          end
          return {status: exit_status, stdout: stdout}
        end

        def ffmpeg(a)
          raise 'error: hash expected' unless a.is_a?(Hash)
          #input_file,input_args,output_file,output_args
          a[:gl_p] ||= [
            '-y', # overwrite output without asking
            '-loglevel','error' # show only errors and up]
          ]
          a[:in_p] ||= []
          a[:out_p] ||= []
          raise "wrong params (#{a.keys.sort})" unless [:gl_p, :in_f, :in_p, :out_f, :out_p].eql?(a.keys.sort)
          external_command(:ffmpeg,[a[:gl_p],a[:in_p],'-i',a[:in_f],a[:out_p],a[:out_f]].flatten)
        end

        # @return Float in seconds
        def video_get_duration(input_file)
          result = external_command(:ffprobe,[
            '-loglevel','error',
            '-show_entries','format=duration',
            '-print_format','default=noprint_wrappers=1:nokey=1',
            input_file])
          return result[:stdout].to_f
        end

        def ffmpeg_fmt(temp_folder)
          return File.join(temp_folder,TMPFMT)
        end

        def get_tmp_num_filepath(temp_folder, file_number)
          return File.join(temp_folder,format(TMPFMT,file_number))
        end

        def video_dupe_frame(temp_folder, index, count)
          input_file = get_tmp_num_filepath(temp_folder,index)
          1.upto(count) do |i|
            FileUtils.ln_s(input_file,get_tmp_num_filepath(temp_folder,index + i))
          end
        end

        def video_blend_frames(temp_folder, index1, index2)
          img1 = get_tmp_num_filepath(temp_folder,index1)
          img2 = get_tmp_num_filepath(temp_folder,index2)
          count = index2 - index1 - 1
          1.upto(count) do |i|
            percent = 100 * i / (count + 1)
            filename = get_tmp_num_filepath(temp_folder, index1 + i)
            external_command(:composite,['-blend',percent,img2,img1,filename])
          end
        end

        def video_dump_frame(input_file, offset_seconds, scale, output_file, index=nil)
          output_file = get_tmp_num_filepath(output_file,index) unless index.nil?
          ffmpeg(
          in_f: input_file,
          in_p: ['-ss',offset_seconds],
          out_f: output_file,
          out_p: ['-frames:v',1,'-filter:v',"scale=#{scale}"])
          return output_file
        end
      end
    end # Options
  end # Preview
end # Aspera
