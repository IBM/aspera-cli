require 'fileutils'
require 'open3'
require 'singleton'
require 'tmpdir'
require 'yaml'

module Asperalm
  # generate preview and thumbnail for one file only
  # gen_combi_ methods are found by name gen_combi_<out format>_<source type>
  # gen_video_ methods are found by name gen_video_<flavor>
  # gen_vidutil_ methods are utility methods
  class PreviewGenerator
    include Singleton
    # values for option_video_style
    def self.video_styles; [:reencode,:clips,:preview];end

    # values for option_overwrite
    def self.overwrite_policies; [:always,:never,:mtime];end

    # values for out_format
    def self.preview_formats; ['png','mp4'];end

    @@SUPPORTED_TYPES=[
      :image,
      :video,
      :office,
      :pdf,
      :plaintext
    ]
    attr_accessor :option_overwrite
    attr_accessor :option_video_style
    attr_accessor :option_vid_offset_seconds
    attr_accessor :option_vid_size
    attr_accessor :option_vid_framecount
    attr_accessor :option_vid_blendframes
    attr_accessor :option_vid_framepause
    attr_accessor :option_vid_fps
    attr_accessor :option_vid_mp4_size_reencode
    attr_accessor :option_clips_offset_seconds
    attr_accessor :option_clips_size
    attr_accessor :option_clips_length
    attr_accessor :option_clips_count
    attr_accessor :option_thumb_mp4_size
    attr_accessor :option_thumb_img_size
    attr_accessor :option_thumb_offset_fraction

    def option_skip_types=(value)
      @skip_types=[]
      value.split(',').each do |v|
        s=v.to_sym
        raise "not supported: #{v}" unless @@SUPPORTED_TYPES.include?(s)
        @skip_types.push(s)
      end
    end

    def option_skip_types()
      return @skip_types.map{|i|i.to_s}.join(',')
    end

    private

    BASH_EXIT_NOT_FOUND=127

    def initialize
      @skip_types=[]
      @extension_to_type={}
      YAML.load_file(__FILE__.gsub(/\.rb$/,'_formats.yml')).each do |type,extensions|
        extensions.each do |extension|
          @extension_to_type[extension]=type
        end
      end
    end

    def check_tools
      required_tools=%w(ffmpeg ffprobe convert composite optipng libreoffice)
      required_tools.delete('libreoffice') if @skip_types.include?(:office)
      Log.log().warn("skip: #{@skip_types}")
      # Check for binaries
      required_tools.each do |bin|
        `#{bin} -h 2>&1`
        fail "Error: #{bin} is not in the PATH" if $?.exitstatus.eql?(BASH_EXIT_NOT_FOUND)
      end
    end

    # run command
    # one could use "system", but we would need to redirect stdout/err
    def external_command(command_args)
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
      if $?.exitstatus.eql?(BASH_EXIT_NOT_FOUND)
        fail "Error: #{bin} is not in the PATH"
      end
      unless exit_status.success?
        Log.log.error "Got child status #{exit_status}\ncommandline: #{command}\nstdout: #{stdout}\nstderr: #{stderr}"
        raise "error"
      end
      return exit_status.success?
    end

    def ffmpeg(input_file,input_args,output_file,output_args)
      external_command(['ffmpeg','-y','-loglevel','error',input_args,'-i',input_file,output_args,output_file].flatten)
    end

    # from bash manual: metacharacter
    SHELL_META_CHARACTERS="|&;()<> \t"

    # returns string with single quotes suitable for bash if there is any bash metacharacter
    def shell_quote(argument)
      return argument unless argument.split('').any?{|c|SHELL_META_CHARACTERS.include?(c)}
      return "'"+argument.gsub(/'/){|s| "'\"'\"'"}+"'"
    end

    def get_video_duration(original_filepath)
      cmd = 'ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1'
      `#{cmd} #{shell_quote original_filepath}`.to_f
    end

    def calc_interval(duration, offset_seconds, count)
      (duration - offset_seconds) / count
    end

    def mk_tmpdir(original_filepath)
      maintmp=@option_tmpdir || Dir.tmpdir
      tmpdir=File.join(maintmp,original_filepath.split('/').last.gsub(/\s/, '_').gsub(/\W/, ''))
      FileUtils.mkdir_p(tmpdir)
      tmpdir
    end

    def get_tmp_num_filepath(tmpdir, file_number)
      file_number = file_number.to_s.rjust(4, '0')
      "#{tmpdir}/img#{file_number}.jpg"
    end

    def gen_vidutil_dupe_frame(original_filepath, tmpdir, dupecount)
      img_number = /img([0-9]*)\.jpg/.match(original_filepath)[1].to_i
      1.upto(dupecount) do |i|
        dupename = get_tmp_num_filepath(tmpdir, (i + img_number))
        `ln -s #{shell_quote original_filepath} '#{dupename}'`
      end
    end

    def gen_vidutil_blend_frames(img1, img2, tmpdir, blendframes)
      img_number = /img([0-9]*)\.jpg/.match(img1)[1].to_i
      1.upto(blendframes) do |i|
        percent = 100 * i / (blendframes + 1)
        filename = get_tmp_num_filepath(tmpdir, img_number + i)
        external_command(['composite','-blend',percent,img2,img1,filename])
      end
    end

    def gen_vidutil_dump_frame(original_filepath, offset_seconds, size, thumb_file_name)
      #-loglevel panic -nostats -loglevel error
      ffmpeg(original_filepath,
      ['-ss',offset_seconds],
      thumb_file_name,
      ['-frames:v',1,'-filter:v',"scale=#{size}"])
    end

    def gen_video_preview(original_filepath, output_file)
      duration = get_video_duration(original_filepath)
      offset_seconds = @option_vid_offset_seconds.to_i
      framecount = @option_vid_framecount.to_i
      interval = calc_interval(duration,offset_seconds,framecount)
      tmpdir = mk_tmpdir(original_filepath)
      previous = ''
      file_number = 1
      1.upto(framecount) do |i|
        filename = get_tmp_num_filepath(tmpdir, file_number)
        gen_vidutil_dump_frame(original_filepath, offset_seconds, @option_vid_size, filename)
        gen_vidutil_dupe_frame(filename, tmpdir, @option_vid_framepause)
        gen_vidutil_blend_frames(previous, filename, tmpdir,@option_vid_blendframes) if i > 1
        previous = get_tmp_num_filepath(tmpdir, file_number + @option_vid_framepause)
        file_number += @option_vid_framepause + @option_vid_blendframes + 1
        offset_seconds+=interval
      end
      ffmpeg(tmpdir+'/img%04d.jpg',
      ['-framerate',@option_vid_fps],
      output_file,
      ['-filter:v',"scale='trunc(iw/2)*2:trunc(ih/2)*2'",'-codec:v','libx264','-r',30,'-pix_fmt','yuv420p'])
      FileUtils.rm_rf(tmpdir)
    end

    def gen_video_clips(original_filepath, output_file)
      # dump clips
      duration = get_video_duration(original_filepath)
      interval = calc_interval(duration,@option_clips_offset_seconds,@option_clips_count)
      tmpdir = mk_tmpdir(original_filepath)
      offset_seconds = @option_clips_offset_seconds.to_i
      filelist = File.join(tmpdir,'files.txt')
      File.open(filelist, 'w+') do |f|
        1.upto(@option_clips_count) do |i|
          file_number = i.to_s.rjust(4, '0')
          output_file="#{tmpdir}/img#{file_number}.mp4"
          # dump clip
          #-loglevel panic -nostats  -filter:v 'scale=400:trunc(ow*a/2)*2'
          ffmpeg(original_filepath,
          ['-ss',0.9*offset_seconds],
          output_file,
          ['-ss',0.1*offset_seconds,'-t',@option_clips_length,'-filter:v',"scale=#{@option_clips_size}",'-codec:a','copy'])
          f.puts("file 'img#{file_number}.mp4'")
          offset_seconds += interval
        end
      end
      # concat clips
      ffmpeg(filelist,
      ['-f','concat'],
      output_file,
      ['-codec','copy'])
      FileUtils.rm_rf(tmpdir)
    end

    def gen_video_reencode(original_filepath, output_file)
      # limit to 60 seconds and 360 px wide
      ffmpeg(original_filepath,
      [],
      output_file,
      ['-t','60','-codec:v','libx264','-profile:v','high',
        '-pix_fmt','yuv420p','-preset','slow','-b:v','500k',
        '-maxrate','500k','-bufsize','1000k',
        '-filter:v',"scale=#{@option_vid_mp4_size_reencode}",
        '-threads','0','-codec:a','libmp3lame','-ac','2','-b:a','128k',
        '-movflags','faststart'])
    end

    def gen_combi_mp4_video(original_filepath,output_file)
      self.method("gen_video_#{@option_video_style}").call(original_filepath,output_file)
    end

    def gen_combi_png_pdf(original_filepath, out_filepath)
      external_command(['convert','-size',"x#{@option_thumb_img_size}",'-background','white','-flatten',"#{original_filepath}[0]",out_filepath])
    end

    def gen_combi_png_office(original_filepath, out_filepath)
      tmpdir=mk_tmpdir(original_filepath)
      external_command(['libreoffice','--display',':42','--headless','--invisible','--convert-to','pdf',
        '--outdir',tmpdir,original_filepath])
      pdf_file=File.join(tmpdir,File.basename(original_filepath,File.extname(original_filepath))+'.pdf')
      gen_combi_png_pdf(pdf_file,out_filepath)
      #File.delete(pdf_file)
      FileUtils.rm_rf(tmpdir)
    end

    def gen_combi_png_image(original_filepath, output_path)
      external_command(['convert',original_filepath+'[0]','-auto-orient',
        '-thumbnail',"#{@option_thumb_img_size}x#{@option_thumb_img_size}>",
        '-quality',95,'+dither','-posterize',40,output_path])
      external_command(['optipng',output_path])
    end

    def gen_combi_png_txt(original_filepath, output_path)
      external_command(['convert','-size',"x#{@option_thumb_img_size}>",
        '-background','white',original_filepath+'[0]',output_path])
    end

    def gen_combi_png_video(original_filepath, output_path)
      gen_vidutil_dump_frame(original_filepath,get_video_duration(original_filepath)*@option_thumb_offset_fraction,@option_thumb_mp4_size, output_path)
    end

    public

    # returns processing method if file needs preview (re-)generation
    # return nil if type is not known or if do not need generation based on overwrite policy
    def generation_method(source_extension,out_format,preview_exists,preview_newer_than_original)
      # get type
      source_type=@extension_to_type[source_extension]
      # is this a known file extension ?
      return nil if source_type.nil?
      # shall we skip it ?
      return nil if @skip_types.include?(source_type.to_sym)
      # what about overwrite policy ?
      return nil if preview_exists and
      (@option_overwrite.eql?(:never) or
      (@option_overwrite.eql?(:mtime) and preview_newer_than_original))
      method_name="gen_combi_#{out_format}_#{source_type}"
      return nil unless self.class.method_defined?(method_name)
      # might return nil if no such method
      return self.method(method_name)
    end
    
    # create preview from file
    def generate(gene_method,original_filepath,preview_filepath)
      gene_method.call(original_filepath,preview_filepath)
    end
  end
end
