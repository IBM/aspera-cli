require 'tmpdir'
require 'fileutils'

module Asperalm
  module Preview
    class Utils
      BASH_EXIT_NOT_FOUND=127
      def self.check_tools(skip_types=[])
        required_tools=%w(ffmpeg ffprobe convert composite optipng libreoffice)
        required_tools.delete('libreoffice') if skip_types.include?(:office)
        Log.log().warn("skip: #{skip_types}")
        # Check for binaries
        required_tools.each do |bin|
          `#{bin} -h 2>&1`
          fail "Error: #{bin} is not in the PATH" if $?.exitstatus.eql?(BASH_EXIT_NOT_FOUND)
        end
      end

      # run command
      # one could use "system", but we would need to redirect stdout/err
      def self.external_command(command_args)
        # build commqnd line, and quote special characters
        command=command_args.map{|i| shell_quote(i.to_s)}.join(' ')
        Log.log.debug("cmd=#{command}".red)
        # capture3: only in ruby2+
        if Open3.respond_to?('capture3') then
          stdout, stderr, exit_status = Open3.capture3(command)
        else
          stderr='<merged with stdout>'
          stdout=%x[#{command} 2>&1]
          exit_status=$?
        end
        if BASH_EXIT_NOT_FOUND.eql?(exit_status)
          fail "Error: #{bin} is not in the PATH"
        end
        unless exit_status.success?
          Log.log.error "Got child status #{exit_status}\ncommandline: #{command}\nstdout: #{stdout}\nstderr: #{stderr}"
          raise "error"
        end
        return exit_status.success?
      end

      def self.ffmpeg(input_file,input_args,output_file,output_args)
        external_command(['ffmpeg','-y','-loglevel','error',input_args,'-i',input_file,output_args,output_file].flatten)
      end

      # from bash manual: metacharacter
      SHELL_SPECIAL_CHARACTERS="|&;()<> \t#"

      # returns string with single quotes suitable for bash if there is any bash metacharacter
      def self.shell_quote(argument)
        return argument unless argument.split('').any?{|c|SHELL_SPECIAL_CHARACTERS.include?(c)}
        return "'"+argument.gsub(/'/){|s| "'\"'\"'"}+"'"
      end

      def self.get_video_duration(input_file)
        cmd = 'ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1'
        `#{cmd} #{shell_quote input_file}`.to_f
      end

      def self.calc_interval(duration, offset_seconds, count)
        (duration - offset_seconds) / count
      end

      def self.mk_tmpdir(input_file)
        maintmp=Options.instance.tmpdir || Dir.tmpdir
        tmpdir=File.join(maintmp,input_file.split('/').last.gsub(/\s/, '_').gsub(/\W/, ''))
        FileUtils.mkdir_p(tmpdir)
        tmpdir
      end

      def self.get_tmp_num_filepath(tmpdir, file_number)
        file_number = file_number.to_s.rjust(4, '0')
        "#{tmpdir}/img#{file_number}.jpg"
      end

      def self.gen_vidutil_dupe_frame(input_file, tmpdir, dupecount)
        img_number = /img([0-9]*)\.jpg/.match(input_file)[1].to_i
        1.upto(dupecount) do |i|
          dupename = get_tmp_num_filepath(tmpdir, (i + img_number))
          `ln -s #{shell_quote input_file} '#{dupename}'`
        end
      end

      def self.gen_vidutil_blend_frames(img1, img2, tmpdir, blendframes)
        img_number = /img([0-9]*)\.jpg/.match(img1)[1].to_i
        1.upto(blendframes) do |i|
          percent = 100 * i / (blendframes + 1)
          filename = get_tmp_num_filepath(tmpdir, img_number + i)
          external_command(['composite','-blend',percent,img2,img1,filename])
        end
      end

      def self.gen_vidutil_dump_frame(input_file, offset_seconds, size, thumb_file_name)
        #-loglevel panic -nostats -loglevel error
        ffmpeg(input_file,
        ['-ss',offset_seconds],
        thumb_file_name,
        ['-frames:v',1,'-filter:v',"scale=#{size}"])
      end
    end # Options
  end # Preview
end # Asperalm
