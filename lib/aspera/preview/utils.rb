require 'tmpdir'
require 'fileutils'
require 'aspera/log'
require 'open3'

module Aspera
  module Preview
    class Utils
      # from bash manual: meta-character need to be escaped
      BASH_SPECIAL_CHARACTERS="|&;()<> \t#\n"
      BASH_EXIT_NOT_FOUND=127
      private_constant :BASH_SPECIAL_CHARACTERS,:BASH_EXIT_NOT_FOUND
      # returns string with single quotes suitable for bash if there is any bash metacharacter
      def self.shell_quote(argument)
        return argument unless argument.split('').any?{|c|BASH_SPECIAL_CHARACTERS.include?(c)}
        return "'"+argument.gsub(/'/){|s| "'\"'\"'"}+"'"
      end

      # check that external tools can be executed
      def self.check_tools(skip_types=[])
        required_tools=%w(ffmpeg ffprobe convert composite optipng libreoffice)
        required_tools.delete('libreoffice') if skip_types.include?(:office)
        # Check for binaries
        required_tools.each do |bin|
          `#{bin} -h 2>&1`
          raise "Error: #{bin} is not in the PATH" if $?.exitstatus.eql?(BASH_EXIT_NOT_FOUND)
        end
      end

      # execute external command
      # one could use "system", but we would need to redirect stdout/err
      # @return true if su
      def self.external_command(command_args,stdout_return=nil)
        # build command line, and quote special characters
        command=command_args.map{|i| shell_quote(i.to_s)}.join(' ')
        Log.log.debug("cmd=#{command}".blue)
        # capture3: only in ruby2+
        if Open3.respond_to?('capture3') then
          stdout, stderr, exit_status = Open3.capture3(command)
        else
          stderr='<merged with stdout>'
          stdout=%x[#{command} 2>&1]
          exit_status=$?
        end
        if BASH_EXIT_NOT_FOUND.eql?(exit_status)
          raise "Error: #{bin} is not in the PATH"
        end
        unless exit_status.success?
          Log.log.error("commandline: #{command}")
          Log.log.error("Error code: #{exit_status}")
          Log.log.error("stdout: #{stdout}")
          Log.log.error("stderr: #{stderr}")
          raise "command returned error"
        end
        stdout_return.replace(stdout) unless stdout_return.nil?
        return exit_status.success?
      end

      def self.ffmpeg(a)
        raise "error: hash expected" unless a.is_a?(Hash)
        #input_file,input_args,output_file,output_args
        a[:gl_p]||=[
          '-y', # overwrite output without asking
          '-loglevel','error', # show only errors and up]
        ]
        a[:in_p]||=[]
        a[:out_p]||=[]
        raise "wrong params (#{a.keys.sort})" unless [:gl_p, :in_f, :in_p, :out_f, :out_p].eql?(a.keys.sort)
        external_command(['ffmpeg',a[:gl_p],a[:in_p],'-i',a[:in_f],a[:out_p],a[:out_f]].flatten)
      end

      def self.video_get_duration(input_file)
        result = String.new
        external_command(['ffprobe',
          '-loglevel','error',
          '-show_entries','format=duration',
          '-print_format','default=noprint_wrappers=1:nokey=1',
          input_file],result)
        result.to_f
      end

      TMPFMT='img%04d.jpg'

      def self.ffmpeg_fmt(temp_folder)
        return File.join(temp_folder,TMPFMT)
      end

      def self.get_tmp_num_filepath(temp_folder, file_number)
        return File.join(temp_folder,sprintf(TMPFMT,file_number))
      end

      def self.video_dupe_frame(temp_folder, index, count)
        input_file=get_tmp_num_filepath(temp_folder,index)
        1.upto(count) do |i|
          FileUtils.ln_s(input_file,get_tmp_num_filepath(temp_folder,index+i))
        end
      end

      def self.video_blend_frames(temp_folder, index1, index2)
        img1=get_tmp_num_filepath(temp_folder,index1)
        img2=get_tmp_num_filepath(temp_folder,index2)
        count=index2-index1-1
        1.upto(count) do |i|
          percent = 100 * i / (count + 1)
          filename = get_tmp_num_filepath(temp_folder, index1 + i)
          external_command(['composite','-blend',percent,img2,img1,filename])
        end
      end

      def self.video_dump_frame(input_file, offset_seconds, scale, output_file, index=nil)
        output_file=get_tmp_num_filepath(output_file,index) unless index.nil?
        ffmpeg(
        in_f: input_file,
        in_p: ['-ss',offset_seconds],
        out_f: output_file,
        out_p: ['-frames:v',1,'-filter:v',"scale=#{scale}"])
        return output_file
      end

      def message_to_png(message)
        # convert -size 400x  -background '#666666' -fill '#ffffff'  -interword-spacing 10 -kerning 4 -pointsize 10 -gravity West -size x22 label:"Lorem dolor sit amet" -flatten xxx.png
        external_command(['convert',
        ])
      end
    end # Options
  end # Preview
end # Aspera
