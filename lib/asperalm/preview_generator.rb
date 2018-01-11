require 'fileutils'
require 'open3'
require 'singleton'
require 'tmpdir'
require 'yaml'

# option: using gem mimemagic

# option : do not match extensions
# option : do not match mime type
# option : use mimemagic gem to get mime type instead of node api
module Asperalm
  # generate preview and thumbnail for one file only
  # gen_combi_ methods are found by name gen_combi_<out format>_<source type>
  # gen_video_ methods are found by name gen_video_<flavor>
  # gen_vidutil_ methods are utility methods
  # node api mime types are from: http://svn.apache.org/repos/asf/httpd/httpd/trunk/docs/conf/mime.types
  class PreviewGenerator
    include Singleton
    # values for option_video_style
    def self.video_styles; [:reencode,:clips,:preview];end

    # values for preview_format, those are the ones for which there is a transformation method:
    # gen_combi_<preview_format>_<source_type>
    def self.preview_formats; ['png','mp4'];end

    # supported "source_type" to identify type of file
    def self.source_types;[
        :image,
        :video,
        :office,
        :pdf,
        :plaintext
      ];end

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
    attr_accessor :option_validate_mime

    private

    BASH_EXIT_NOT_FOUND=127

    def initialize
    end

    def check_tools(skip_types=[])
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
      if BASH_EXIT_NOT_FOUND.eql?(exit_status)
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
    SHELL_SPECIAL_CHARACTERS="|&;()<> \t#"

    # returns string with single quotes suitable for bash if there is any bash metacharacter
    def shell_quote(argument)
      return argument unless argument.split('').any?{|c|SHELL_SPECIAL_CHARACTERS.include?(c)}
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

    def gen_combi_png_office(original_filepath, out_filepath)
      tmpdir=mk_tmpdir(original_filepath)
      external_command(['libreoffice','--display',':42','--headless','--invisible','--convert-to','pdf',
        '--outdir',tmpdir,original_filepath])
      pdf_file=File.join(tmpdir,File.basename(original_filepath,File.extname(original_filepath))+'.pdf')
      gen_combi_png_pdf(pdf_file,out_filepath)
      #File.delete(pdf_file)
      FileUtils.rm_rf(tmpdir)
    end

    def gen_combi_png_pdf(original_filepath, out_filepath)
      external_command(['convert',
        '-size',"x#{@option_thumb_img_size}",
        '-background','white',
        '-flatten',
        "#{original_filepath}[0]",
        out_filepath])
    end

    def gen_combi_png_image(original_filepath, output_path)
      external_command(['convert',
        '-auto-orient',
        '-thumbnail',"#{@option_thumb_img_size}x#{@option_thumb_img_size}>",
        '-quality',95,
        '+dither',
        '-posterize',40,
        "#{original_filepath}[0]",
        output_path])
      external_command(['optipng',output_path])
    end

    # text to png
    def gen_combi_png_plaintext(original_filepath, output_path)
      external_command(['convert',
        '-size',"#{@option_thumb_img_size}x#{@option_thumb_img_size}",
        'xc:white',
        '-font','Courier',
        '-pointsize',12,
        '-fill','black',
        '-annotate','+15+15',"@#{original_filepath}",
        '-trim',
        '-bordercolor','#FFF','-border',10,
        '+repage',
        output_path])
    end

    def gen_combi_png_video(original_filepath, output_path)
      gen_vidutil_dump_frame(original_filepath,get_video_duration(original_filepath)*@option_thumb_offset_fraction,@option_thumb_mp4_size, output_path)
    end

    def processing_method_symb(preview_format,source_type)
      "gen_combi_#{preview_format}_#{source_type}".to_sym
    end

    public

    # 1- set the :source_type if recognized
    # 2- returns true if there is a processing method
    def is_supported?(preview_info)
      # does it match a supported type ?
      infos=SUPPORTED_FILE_TYPES.select do |p|
        case p[:match]
        when :mime_exact
          next preview_info[:content_type].eql?(p[:value])
        when :extension
          next preview_info[:extension].eql?(p[:value])
        else raise "INTERNAL ERROR"
        end
        false
      end
      return false if infos.empty?
      preview_info[:source_type]=infos.first[:preview_type]
      return respond_to?(processing_method_symb(preview_info[:preview_format],preview_info[:source_type]),true)
    end

    # create preview from file
    def generate(preview_info)
      Log.log.info("#{preview_info[:src]}->#{preview_info[:dest]}")
      method_symb=processing_method_symb(preview_info[:preview_format],preview_info[:source_type])
      # gene_method,preview_info[:src],preview_filepath
      if @option_validate_mime.eql?(:yes)
        require 'mimemagic'
        require 'mimemagic/overlay'
        magic_mime_type=MimeMagic.by_magic(File.open(preview_info[:src]))
        if ! magic_mime_type.eql?(preview_info[:content_type])
          Log.log.warn("non matching types: node=#{preview_info[:content_type]}, magic=#{magic_mime_type}")
        end
      end
      self.send(method_symb,preview_info[:src],preview_info[:dest])
    end

    private
    # define how files are processed based on mime type or extension
    # this is a way to add support for extensions that are otherwise not known by node api
    # :mime_exact : mime type must be exact value
    # :extension : by file extension (in case mime type is not recognized)
    SUPPORTED_FILE_TYPES=[
      {:preview_type=>:pdf, :match=>:mime_exact, :value=>'application/pdf'},
      {:preview_type=>:plaintext, :match=>:mime_exact, :value=>'text/plain'},
      {:preview_type=>:plaintext, :match=>:mime_exact, :value=>'application/json'},
      {:preview_type=>:plaintext, :match=>:mime_exact, :value=>'application/xml'},
      {:preview_type=>:video, :match=>:mime_exact, :value=>'video/x-msvideo'},
      {:preview_type=>:video, :match=>:mime_exact, :value=>'video/x-ms-wmv'},
      {:preview_type=>:video, :match=>:mime_exact, :value=>'video/x-matroska'},
      {:preview_type=>:video, :match=>:mime_exact, :value=>'video/x-m4v'},
      {:preview_type=>:video, :match=>:mime_exact, :value=>'video/x-flv'},
      {:preview_type=>:video, :match=>:mime_exact, :value=>'video/quicktime'},
      {:preview_type=>:video, :match=>:mime_exact, :value=>'video/mpeg'},
      {:preview_type=>:video, :match=>:mime_exact, :value=>'video/mp4'},
      {:preview_type=>:video, :match=>:mime_exact, :value=>'video/h264'},
      {:preview_type=>:video, :match=>:mime_exact, :value=>'video/h263'},
      {:preview_type=>:video, :match=>:mime_exact, :value=>'video/h261'},
      {:preview_type=>:video, :match=>:mime_exact, :value=>'audio/ogg'},
      {:preview_type=>:video, :match=>:extension, :value=>'divx'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'text/plain'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'text/html'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'text/csv'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'image/x-pict'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'image/x-freehand'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'image/x-cmx'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'image/vnd.dxf'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'image/cgm'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/x-mspublisher'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/x-abiword'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.wordperfect'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.sun.xml.writer.template'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.sun.xml.writer'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.sun.xml.math'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.sun.xml.impress.template'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.sun.xml.impress'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.sun.xml.draw.template'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.sun.xml.draw'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.sun.xml.calc.template'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.sun.xml.calc'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.palm'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.openxmlformats-officedocument.wordprocessingml.template'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.openxmlformats-officedocument.wordprocessingml.document'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.openxmlformats-officedocument.spreadsheetml.template'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.openxmlformats-officedocument.presentationml.template'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.openxmlformats-officedocument.presentationml.slideshow'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.openxmlformats-officedocument.presentationml.presentation'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.oasis.opendocument.text-template'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.oasis.opendocument.text'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.oasis.opendocument.spreadsheet-template'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.oasis.opendocument.spreadsheet'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.oasis.opendocument.presentation-template'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.oasis.opendocument.presentation'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.oasis.opendocument.graphics-template'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.oasis.opendocument.graphics'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.oasis.opendocument.formula'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.oasis.opendocument.chart'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.ms-works'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.ms-word.template.macroenabled.12'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.ms-word.document.macroenabled.12'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.ms-powerpoint.template.macroenabled.12'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.ms-powerpoint.presentation.macroenabled.12'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.ms-powerpoint'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.ms-excel.template.macroenabled.12'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.ms-excel.sheet.macroenabled.12'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.ms-excel.sheet.binary.macroenabled.12'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.ms-excel'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/vnd.lotus-wordpro'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/rtf'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/msword'},
      {:preview_type=>:office, :match=>:mime_exact, :value=>'application/mac-binhex40'},
      {:preview_type=>:office, :match=>:extension, :value=>'zabw'},
      {:preview_type=>:office, :match=>:extension, :value=>'xlk'},
      {:preview_type=>:office, :match=>:extension, :value=>'wq2'},
      {:preview_type=>:office, :match=>:extension, :value=>'wq1'},
      {:preview_type=>:office, :match=>:extension, :value=>'wpg'},
      {:preview_type=>:office, :match=>:extension, :value=>'wn'},
      {:preview_type=>:office, :match=>:extension, :value=>'wk3'},
      {:preview_type=>:office, :match=>:extension, :value=>'wk1'},
      {:preview_type=>:office, :match=>:extension, :value=>'wb2'},
      {:preview_type=>:office, :match=>:extension, :value=>'vsdx'},
      {:preview_type=>:office, :match=>:extension, :value=>'vdx'},
      {:preview_type=>:office, :match=>:extension, :value=>'vds'},
      {:preview_type=>:office, :match=>:extension, :value=>'uot'},
      {:preview_type=>:office, :match=>:extension, :value=>'uos'},
      {:preview_type=>:office, :match=>:extension, :value=>'uop'},
      {:preview_type=>:office, :match=>:extension, :value=>'uof'},
      {:preview_type=>:office, :match=>:extension, :value=>'sylk'},
      {:preview_type=>:office, :match=>:extension, :value=>'svm'},
      {:preview_type=>:office, :match=>:extension, :value=>'slk'},
      {:preview_type=>:office, :match=>:extension, :value=>'sgv'},
      {:preview_type=>:office, :match=>:extension, :value=>'sgf'},
      {:preview_type=>:office, :match=>:extension, :value=>'pmd'},
      {:preview_type=>:office, :match=>:extension, :value=>'pm6'},
      {:preview_type=>:office, :match=>:extension, :value=>'pm'},
      {:preview_type=>:office, :match=>:extension, :value=>'pages'},
      {:preview_type=>:office, :match=>:extension, :value=>'numbers'},
      {:preview_type=>:office, :match=>:extension, :value=>'mwd'},
      {:preview_type=>:office, :match=>:extension, :value=>'mw'},
      {:preview_type=>:office, :match=>:extension, :value=>'mml'},
      {:preview_type=>:office, :match=>:extension, :value=>'met'},
      {:preview_type=>:office, :match=>:extension, :value=>'mcw'},
      {:preview_type=>:office, :match=>:extension, :value=>'key'},
      {:preview_type=>:office, :match=>:extension, :value=>'hpw'},
      {:preview_type=>:office, :match=>:extension, :value=>'fodt'},
      {:preview_type=>:office, :match=>:extension, :value=>'fods'},
      {:preview_type=>:office, :match=>:extension, :value=>'fodp'},
      {:preview_type=>:office, :match=>:extension, :value=>'fodg'},
      {:preview_type=>:office, :match=>:extension, :value=>'fb2'},
      {:preview_type=>:office, :match=>:extension, :value=>'dummy'},
      {:preview_type=>:office, :match=>:extension, :value=>'dif'},
      {:preview_type=>:office, :match=>:extension, :value=>'dbf'},
      {:preview_type=>:office, :match=>:extension, :value=>'cwk'},
      {:preview_type=>:office, :match=>:extension, :value=>'cdr'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'video/x-mng'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'text/troff'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/x-xwindowdump'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/x-xpixmap'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/x-xbitmap'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/x-tga'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/x-rgb'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/x-portable-pixmap'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/x-portable-graymap'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/x-portable-bitmap'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/x-portable-anymap'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/x-pcx'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/x-mrsid-image'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/x-icon'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/webp'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/vnd.wap.wbmp'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/vnd.ms-photo'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/vnd.fpx'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/vnd.djvu'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/vnd.adobe.photoshop'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/tiff'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/svg+xml'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/sgi'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/png'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/jpeg'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/gif'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/cgm'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'image/bmp'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'font/ttf'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'application/x-xfig'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'application/x-msmetafile'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'application/x-font-type1'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'application/x-director'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'application/vnd.palm'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'application/vnd.mophun.certificate'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'application/vnd.mobius.msl'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'application/vnd.hp-pcl'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'application/vnd.hp-hpgl'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'application/vnd.3gpp.pic-bw-small'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'application/postscript'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'application/pdf'},
      {:preview_type=>:image, :match=>:mime_exact, :value=>'application/msword'},
      {:preview_type=>:image, :match=>:extension, :value=>'yuv'},
      {:preview_type=>:image, :match=>:extension, :value=>'ycbcra'},
      {:preview_type=>:image, :match=>:extension, :value=>'ycbcr'},
      {:preview_type=>:image, :match=>:extension, :value=>'xcf'},
      {:preview_type=>:image, :match=>:extension, :value=>'x3f'},
      {:preview_type=>:image, :match=>:extension, :value=>'x'},
      {:preview_type=>:image, :match=>:extension, :value=>'wpg'},
      {:preview_type=>:image, :match=>:extension, :value=>'viff'},
      {:preview_type=>:image, :match=>:extension, :value=>'vicar'},
      {:preview_type=>:image, :match=>:extension, :value=>'uyvy'},
      {:preview_type=>:image, :match=>:extension, :value=>'uil'},
      {:preview_type=>:image, :match=>:extension, :value=>'tim'},
      {:preview_type=>:image, :match=>:extension, :value=>'sun'},
      {:preview_type=>:image, :match=>:extension, :value=>'sparse-color'},
      {:preview_type=>:image, :match=>:extension, :value=>'sfw'},
      {:preview_type=>:image, :match=>:extension, :value=>'sct'},
      {:preview_type=>:image, :match=>:extension, :value=>'rle'},
      {:preview_type=>:image, :match=>:extension, :value=>'rla'},
      {:preview_type=>:image, :match=>:extension, :value=>'rgba'},
      {:preview_type=>:image, :match=>:extension, :value=>'rfg'},
      {:preview_type=>:image, :match=>:extension, :value=>'raf'},
      {:preview_type=>:image, :match=>:extension, :value=>'rad'},
      {:preview_type=>:image, :match=>:extension, :value=>'pwp'},
      {:preview_type=>:image, :match=>:extension, :value=>'ptif'},
      {:preview_type=>:image, :match=>:extension, :value=>'ps3'},
      {:preview_type=>:image, :match=>:extension, :value=>'ps2'},
      {:preview_type=>:image, :match=>:extension, :value=>'png8'},
      {:preview_type=>:image, :match=>:extension, :value=>'png64'},
      {:preview_type=>:image, :match=>:extension, :value=>'png48'},
      {:preview_type=>:image, :match=>:extension, :value=>'png32'},
      {:preview_type=>:image, :match=>:extension, :value=>'png24'},
      {:preview_type=>:image, :match=>:extension, :value=>'png00'},
      {:preview_type=>:image, :match=>:extension, :value=>'pix'},
      {:preview_type=>:image, :match=>:extension, :value=>'pict'},
      {:preview_type=>:image, :match=>:extension, :value=>'picon'},
      {:preview_type=>:image, :match=>:extension, :value=>'pef'},
      {:preview_type=>:image, :match=>:extension, :value=>'pcds'},
      {:preview_type=>:image, :match=>:extension, :value=>'pcd'},
      {:preview_type=>:image, :match=>:extension, :value=>'pam'},
      {:preview_type=>:image, :match=>:extension, :value=>'palm'},
      {:preview_type=>:image, :match=>:extension, :value=>'p7'},
      {:preview_type=>:image, :match=>:extension, :value=>'otb'},
      {:preview_type=>:image, :match=>:extension, :value=>'orf'},
      {:preview_type=>:image, :match=>:extension, :value=>'nef'},
      {:preview_type=>:image, :match=>:extension, :value=>'mvg'},
      {:preview_type=>:image, :match=>:extension, :value=>'mtv'},
      {:preview_type=>:image, :match=>:extension, :value=>'mrw'},
      {:preview_type=>:image, :match=>:extension, :value=>'mrsid'},
      {:preview_type=>:image, :match=>:extension, :value=>'mpr'},
      {:preview_type=>:image, :match=>:extension, :value=>'mono'},
      {:preview_type=>:image, :match=>:extension, :value=>'miff'},
      {:preview_type=>:image, :match=>:extension, :value=>'mat'},
      {:preview_type=>:image, :match=>:extension, :value=>'jxr'},
      {:preview_type=>:image, :match=>:extension, :value=>'jpt'},
      {:preview_type=>:image, :match=>:extension, :value=>'jp2'},
      {:preview_type=>:image, :match=>:extension, :value=>'jng'},
      {:preview_type=>:image, :match=>:extension, :value=>'jbig'},
      {:preview_type=>:image, :match=>:extension, :value=>'j2k'},
      {:preview_type=>:image, :match=>:extension, :value=>'j2c'},
      {:preview_type=>:image, :match=>:extension, :value=>'inline'},
      {:preview_type=>:image, :match=>:extension, :value=>'info'},
      {:preview_type=>:image, :match=>:extension, :value=>'hrz'},
      {:preview_type=>:image, :match=>:extension, :value=>'hdr'},
      {:preview_type=>:image, :match=>:extension, :value=>'gray'},
      {:preview_type=>:image, :match=>:extension, :value=>'gplt'},
      {:preview_type=>:image, :match=>:extension, :value=>'fits'},
      {:preview_type=>:image, :match=>:extension, :value=>'fax'},
      {:preview_type=>:image, :match=>:extension, :value=>'exr'},
      {:preview_type=>:image, :match=>:extension, :value=>'ept'},
      {:preview_type=>:image, :match=>:extension, :value=>'epsi'},
      {:preview_type=>:image, :match=>:extension, :value=>'epsf'},
      {:preview_type=>:image, :match=>:extension, :value=>'eps3'},
      {:preview_type=>:image, :match=>:extension, :value=>'eps2'},
      {:preview_type=>:image, :match=>:extension, :value=>'epi'},
      {:preview_type=>:image, :match=>:extension, :value=>'epdf'},
      {:preview_type=>:image, :match=>:extension, :value=>'dpx'},
      {:preview_type=>:image, :match=>:extension, :value=>'dng'},
      {:preview_type=>:image, :match=>:extension, :value=>'dib'},
      {:preview_type=>:image, :match=>:extension, :value=>'dds'},
      {:preview_type=>:image, :match=>:extension, :value=>'dcx'},
      {:preview_type=>:image, :match=>:extension, :value=>'dcm'},
      {:preview_type=>:image, :match=>:extension, :value=>'cut'},
      {:preview_type=>:image, :match=>:extension, :value=>'cur'},
      {:preview_type=>:image, :match=>:extension, :value=>'crw'},
      {:preview_type=>:image, :match=>:extension, :value=>'cr2'},
      {:preview_type=>:image, :match=>:extension, :value=>'cmyka'},
      {:preview_type=>:image, :match=>:extension, :value=>'cmyk'},
      {:preview_type=>:image, :match=>:extension, :value=>'clipboard'},
      {:preview_type=>:image, :match=>:extension, :value=>'cin'},
      {:preview_type=>:image, :match=>:extension, :value=>'cals'},
      {:preview_type=>:image, :match=>:extension, :value=>'bpg'},
      {:preview_type=>:image, :match=>:extension, :value=>'bmp3'},
      {:preview_type=>:image, :match=>:extension, :value=>'bmp2'},
      {:preview_type=>:image, :match=>:extension, :value=>'avs'},
      {:preview_type=>:image, :match=>:extension, :value=>'arw'},
      {:preview_type=>:image, :match=>:extension, :value=>'art'},
      {:preview_type=>:image, :match=>:extension, :value=>'aai'}
    ]
  end # PreviewGenerator
end # Asperalm
