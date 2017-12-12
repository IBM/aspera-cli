require 'fileutils'
require 'open3'
require 'singleton'
require 'tmpdir'

module Asperalm
  # generate preview and thumnail for one file only
  class PreviewGenerator
    include Singleton
    def self.video_styles; [:reencode,:clips,:preview];end

    def self.overwrite_policies; [:always,:never,:attributes];end

    attr_accessor :option_overwrite
    attr_accessor :option_video_style

    private

    def initialize
      conf_folder=File.dirname(__FILE__)+'/../../etc'
      @formats = YAML.load_file(conf_folder+'/file_formats.yml')
      @config = YAML.load_file(conf_folder+'/asp_thumb.yml')
      @option_overwrite=:always
      @option_video_style=:reencode
      # Check for binaries
      %w(ffmpeg ffprobe convert optipng composite).each do |bin|
        fail "Error: #{bin} is not in the PATH" if `which #{bin}`.length == 0
      end
    end

    # run command
    def rcmd(command_args)
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
      unless exit_status.success?
        Log.log.error "Got child status #{exit_status}\ncommandline: #{command}\nstdout: #{stdout}\nstderr: #{stderr}"
        raise "error"
      end
      return exit_status.success?
    end

    def ffmpeg(input_file,input_args,output_file,output_args)
      rcmd(['ffmpeg','-y','-loglevel','error'].push(*input_args).push('-i',input_file).push(*output_args).push(output_file))
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
      maintmp=@config['tmpdir'] || Dir.tmpdir
      tmpdir=File.join(maintmp,original_filepath.split('/').last.gsub(/\s/, '_').gsub(/\W/, ''))
      FileUtils.mkdir_p(tmpdir)
      tmpdir
    end

    def get_tmp_num_filepath(tmpdir, file_number)
      file_number = file_number.to_s.rjust(4, '0')
      "#{tmpdir}/img#{file_number}.jpg"
    end

    def genx_mp4_video_preview_dupe_frame(original_filepath, tmpdir, dupecount)
      img_number = /img([0-9]*)\.jpg/.match(original_filepath)[1].to_i
      1.upto(dupecount) do |i|
        dupename = get_tmp_num_filepath(tmpdir, (i + img_number))
        `ln -s #{shell_quote original_filepath} '#{dupename}'`
      end
    end

    def genx_mp4_video_preview_blend_frames(img1, img2, tmpdir, blendframes)
      img_number = /img([0-9]*)\.jpg/.match(img1)[1].to_i
      1.upto(blendframes) do |i|
        percent = 100 * i / (blendframes + 1)
        filename = get_tmp_num_filepath(tmpdir, img_number + i)
        rcmd(['composite','-blend',percent,img2,img1,filename])
      end
    end

    def dump_frame(original_filepath, offset_seconds, size, thumb_file_name)
      #-loglevel panic -nostats -loglevel error
      ffmpeg(original_filepath,
      ['-ss',offset_seconds],
      thumb_file_name,
      ['-frames:v',1,'-filter:v',"scale=#{size}"])
    end

    def genx_mp4_video_preview(original_filepath, output_file)
      duration = get_video_duration(original_filepath)
      offset_seconds = @config['vid_offset_seconds'].to_i
      framecount = @config['vid_framecount'].to_i
      interval = calc_interval(duration,offset_seconds,framecount)
      tmpdir = mk_tmpdir(original_filepath)
      previous = ''
      file_number = 1
      1.upto(framecount) do |i|
        filename = get_tmp_num_filepath(tmpdir, file_number)
        dump_frame(original_filepath, offset_seconds, @config['vid_size'], filename)
        genx_mp4_video_preview_dupe_frame(filename, tmpdir, @config['vid_framepause'])
        genx_mp4_video_preview_blend_frames(previous, filename, tmpdir,@config['vid_blendframes']) if i > 1
        previous = get_tmp_num_filepath(tmpdir, file_number + @config['vid_framepause'])
        file_number += @config['vid_framepause'] + @config['vid_blendframes'] + 1
        offset_seconds+=interval
      end
      ffmpeg(tmpdir+'/img%04d.jpg',
      ['-framerate',@config['vid_fps']],
      output_file,
      ['-filter:v',"scale='trunc(iw/2)*2:trunc(ih/2)*2'",'-codec:v','libx264','-r',30,'-pix_fmt','yuv420p'])
      FileUtils.rm_rf(tmpdir)
    end

    def genx_mp4_video_clips(original_filepath, output_file)
      # dump clips
      duration = get_video_duration(original_filepath)
      interval = calc_interval(duration,@config['clips_offset_seconds'],@config['clips_count'])
      tmpdir = mk_tmpdir(original_filepath)
      offset_seconds = @config['clips_offset_seconds'].to_i
      filelist = File.join(tmpdir,'files.txt')
      File.open(filelist, 'w+') do |f|
        1.upto(@config['clips_count']) do |i|
          file_number = i.to_s.rjust(4, '0')
          output_file="#{tmpdir}/img#{file_number}.mp4"
          # dump clip
          #-loglevel panic -nostats  -filter:v 'scale=400:trunc(ow*a/2)*2'
          ffmpeg(original_filepath,
          ['-ss',0.9*offset_seconds],
          output_file,
          ['-ss',0.1*offset_seconds,'-t',@config['clips_length'],'-filter:v','scale='+@config['clips_size'],'-codec:a','copy'])
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

    def genx_mp4_video_reencode(original_filepath, output_file)
      # limit to 60 seconds and 360 px wide
      ffmpeg(original_filepath,
      [],
      output_file,
      ['-t','60','-codec:v','libx264','-profile:v','high',
        '-pix_fmt','yuv420p','-preset','slow','-b:v','500k',
        '-maxrate','500k','-bufsize','1000k',
        '-filter:v','scale='+@config['vid_mp4_size_reencode'],
        '-threads','0','-codec:a','libmp3lame','-ac','2','-b:a','128k',
        '-movflags','faststart'])
    end

    def genx_mp4_video(original_filepath,output_file)
      self.method('genx_mp4_video_'+@option_video_style.to_s).call(original_filepath,output_file)
    end

    def genx_png_pdf(original_filepath, out_filepath)
      rcmd(['convert','-size','x'+@config['thumb_img_size'],'-background','white','-flatten',original_filepath+'[0]',out_filepath])
    end

    def genx_png_office(original_filepath, out_filepath)
      tmpdir=mk_tmpdir(original_filepath)
      rcmd(['libreoffice','--display',':42','--headless','--invisible','--convert-to','pdf',
        '--outdir',tmpdir,original_filepath])
      pdf_file=File.join(tmpdir,File.basename(original_filepath,File.extname(original_filepath))+'.pdf')
      genx_png_pdf(pdf_file,out_filepath)
      #File.delete(pdf_file)
      FileUtils.rm_rf(tmpdir)
    end

    def genx_png_image(original_filepath, output_path)
      rcmd(['convert',original_filepath+'[0]','-auto-orient',
        '-thumbnail',@config['thumb_img_size']+'x'+@config['thumb_img_size']+'>',
        '-quality',95,'+dither','-posterize',40,output_path])
      rcmd(['optipng',output_path])
    end

    def genx_png_txt(original_filepath, output_path)
      rcmd(['convert','-size','x'+@config['thumb_img_size']+'>',
        '-background','white',original_filepath+'[0]',output_path])
    end

    def genx_png_video(original_filepath, output_path)
      dump_frame(original_filepath,get_video_duration(original_filepath)*@config['thumb_offset_fraction'],@config['thumb_mp4_size'], output_path)
    end

    public

    # create preview from file, returning true
    # as long as at least one file is created
    def preview_from_file(original_filepath, id, previews_folder)
      preview_dir = File.join(previews_folder, "#{id}.asp-preview")
      FileUtils.mkdir_p(preview_dir)
      ['png','mp4'].each do |out_format|
        preview_file_path = File.join(preview_dir, 'preview.'+out_format)
        if @option_overwrite.eql?(:always) or !File.exists?(preview_file_path)
          @formats.each do |source_type,extensions|
            if extensions.include?(File.extname(original_filepath).downcase)
              gen_method="genx_#{out_format}_#{source_type}"
              if !self.method(gen_method).nil?
                self.method(gen_method).call(original_filepath,preview_file_path)
              end
            end
          end
        end
      end
    end
  end
end

