require 'open3'
require 'asperalm/preview/options'
require 'asperalm/preview/utils'

# TODO: option : do not match extensions
# TODO: option : do not match mime type
module Asperalm
  module Preview
    # generate preview files (png, mp4) for one file only
    # gen_combi_ methods are found by name gen_combi_<preview_format>_<conversion_type>
    # gen_video_ methods are found by name gen_video_<vid_conv_method>
    # video_ methods are utility methods used for the video conversion
    # node api mime types are from: http://svn.apache.org/repos/asf/httpd/httpd/trunk/docs/conf/mime.types
    class Generator
      # values for preview_format, those are the ones for which there is a transformation method:
      # gen_combi_<preview_format>_<conversion_type>
      def self.preview_formats; ['png','mp4'];end

      # supported "conversion_type" to identify conversion method of a file
      def self.conversion_types;[
          :image,
          :video,
          :office,
          :pdf,
          :plaintext
        ];end

      attr_reader :preview_format
      attr_accessor :source
      attr_accessor :destination
      attr_accessor :conversion_type

      def initialize(preview_format,extension,mime_type)
        @preview_format=preview_format
        @extension=extension
        @mime_type=mime_type
        @source=nil
        @destination=nil
        @conversion_type=SUPPORTED_MIME_TYPES[@mime_type]
        if @conversion_type.nil? and Options.instance.check_extension
          @conversion_type=SUPPORTED_EXTENSIONS[@extension]
        end
      end

      def processing_method_symb
        "gen_combi_#{@preview_format}_#{@conversion_type}".to_sym
      end

      def supported?
        return respond_to?(processing_method_symb,true)
      end

      def self.generators(extension,mime_type)
        preview_formats.map {|preview_format|Generator.new(preview_format,extension,mime_type)}
      end

      # create preview from file
      def generate
        method_symb=processing_method_symb
        Log.log.info("#{@source}->#{@destination} (#{method_symb})")
        if Options.instance.validate_mime.eql?(:yes)
          require 'mimemagic'
          require 'mimemagic/overlay'
          magic_mime_type=MimeMagic.by_magic(File.open(@source)).to_s
          if magic_mime_type.empty?
            Log.log.info("no mime type per magic number")
          elsif magic_mime_type.eql?(@mime_type)
            Log.log.info("matching mime type per magic number")
          else
            Log.log.warn("non matching mime types: node=[#{@mime_type}], magic=[#{magic_mime_type}]")
          end
        end
        self.send(method_symb)
      end

      private

      def gen_video_preview()
        duration = get_video_duration(@source)
        offset_seconds = Options.instance.vid_offset_seconds.to_i
        framecount = Options.instance.vid_framecount.to_i
        interval = calc_interval(duration,offset_seconds,framecount)
        tmpdir = Utils.mk_tmpdir(@source)
        previous = ''
        file_number = 1
        1.upto(framecount) do |i|
          filename = get_tmp_num_filepath(tmpdir, file_number)
          Utils.video_dump_frame(@source, offset_seconds, Options.instance.vid_size, filename)
          Utils.video_dupe_frame(filename, tmpdir, Options.instance.vid_framepause)
          Utils.video_blend_frames(previous, filename, tmpdir,Options.instance.vid_blendframes) if i > 1
          previous = get_tmp_num_filepath(tmpdir, file_number + Options.instance.vid_framepause)
          file_number += Options.instance.vid_framepause + Options.instance.vid_blendframes + 1
          offset_seconds+=interval
        end
        Utils.ffmpeg(tmpdir+'/img%04d.jpg',
        ['-framerate',Options.instance.vid_fps],
        @destination,
        ['-filter:v',"scale='trunc(iw/2)*2:trunc(ih/2)*2'",'-codec:v','libx264','-r',30,'-pix_fmt','yuv420p'])
        FileUtils.rm_rf(tmpdir)
      end

      def gen_video_clips()
        # dump clips
        duration = get_video_duration(@source)
        interval = calc_interval(duration,Options.instance.clips_offset_seconds,Options.instance.clips_count)
        tmpdir = Utils.mk_tmpdir(@source)
        offset_seconds = Options.instance.clips_offset_seconds.to_i
        filelist = File.join(tmpdir,'files.txt')
        File.open(filelist, 'w+') do |f|
          1.upto(Options.instance.clips_count) do |i|
            file_number = i.to_s.rjust(4, '0')
            @destination="#{tmpdir}/img#{file_number}.mp4"
            # dump clip
            #-loglevel panic -nostats  -filter:v 'scale=400:trunc(ow*a/2)*2'
            Utils.ffmpeg(@source,
            ['-ss',0.9*offset_seconds],
            @destination,
            ['-ss',0.1*offset_seconds,'-t',Options.instance.clips_length,'-filter:v',"scale=#{Options.instance.clips_size}",'-codec:a','copy'])
            f.puts("file 'img#{file_number}.mp4'")
            offset_seconds += interval
          end
        end
        # concat clips
        Utils.ffmpeg(filelist,
        ['-f','concat'],
        @destination,
        ['-codec','copy'])
        FileUtils.rm_rf(tmpdir)
      end

      def gen_video_reencode()
        # limit to 60 seconds and 360 px wide
        Utils.ffmpeg(@source,
        [],
        @destination,
        ['-t','60','-codec:v','libx264','-profile:v','high',
          '-pix_fmt','yuv420p','-preset','slow','-b:v','500k',
          '-maxrate','500k','-bufsize','1000k',
          '-filter:v',"scale=#{Options.instance.vid_mp4_size_reencode}",
          '-threads','0','-codec:a','libmp3lame','-ac','2','-b:a','128k',
          '-movflags','faststart'])
      end

      def gen_combi_mp4_video()
        self.send("gen_video_#{Options.instance.vid_conv_method}".to_sym)
      end

      def gen_combi_png_office()
        tmpdir=Utils.mk_tmpdir(@source)
        libreoffice_exec='libreoffice'
        #TODO: detect on mac:
        #libreoffice_exec='/Applications/LibreOffice.app/Contents/MacOS/soffice'
        Utils.external_command([libreoffice_exec,'--display',':42','--headless','--invisible','--convert-to','pdf',
          '--outdir',tmpdir,@source])
        saved_source=@source
        pdf_file=File.join(tmpdir,File.basename(@source,File.extname(@source))+'.pdf')
        @source=pdf_file
        gen_combi_png_pdf()
        @source=saved_source
        #File.delete(pdf_file)
        FileUtils.rm_rf(tmpdir)
      end

      def gen_combi_png_pdf()
        Utils.external_command(['convert',
          '-size',"x#{Options.instance.thumb_img_size}",
          '-background','white',
          '-flatten',
          "#{@source}[0]",
          @destination])
      end

      def gen_combi_png_image()
        Utils.external_command(['convert',
          '-auto-orient',
          '-thumbnail',"#{Options.instance.thumb_img_size}x#{Options.instance.thumb_img_size}>",
          '-quality',95,
          '+dither',
          '-posterize',40,
          "#{@source}[0]",
          @destination])
        Utils.external_command(['optipng',@destination])
      end

      # text to png
      def gen_combi_png_plaintext()
        Utils.external_command(['convert',
          '-size',"#{Options.instance.thumb_img_size}x#{Options.instance.thumb_img_size}",
          'xc:white',
          '-font','Courier',
          '-pointsize',12,
          '-fill','black',
          '-annotate','+15+15',"@#{@source}",
          '-trim',
          '-bordercolor','#FFF',
          '-border',10,
          '+repage',
          @destination])
      end

      def gen_combi_png_video()
        Utils.video_dump_frame(@source,Utils.get_video_duration(@source)*Options.instance.thumb_offset_fraction,Options.instance.thumb_mp4_size, @destination)
      end

      # define how files are processed based on mime type
      SUPPORTED_MIME_TYPES={
        'application/json' => :plaintext,
        'application/mac-binhex40' => :office,
        'application/msword' => :office,
        'application/pdf' => :pdf,
        'application/postscript' => :image,
        'application/rtf' => :office,
        'application/vnd.3gpp.pic-bw-small' => :image,
        'application/vnd.hp-hpgl' => :image,
        'application/vnd.hp-pcl' => :image,
        'application/vnd.lotus-wordpro' => :office,
        'application/vnd.mobius.msl' => :image,
        'application/vnd.mophun.certificate' => :image,
        'application/vnd.ms-excel' => :office,
        'application/vnd.ms-excel.sheet.binary.macroenabled.12' => :office,
        'application/vnd.ms-excel.sheet.macroenabled.12' => :office,
        'application/vnd.ms-excel.template.macroenabled.12' => :office,
        'application/vnd.ms-powerpoint' => :office,
        'application/vnd.ms-powerpoint.presentation.macroenabled.12' => :office,
        'application/vnd.ms-powerpoint.template.macroenabled.12' => :office,
        'application/vnd.ms-word.document.macroenabled.12' => :office,
        'application/vnd.ms-word.template.macroenabled.12' => :office,
        'application/vnd.ms-works' => :office,
        'application/vnd.oasis.opendocument.chart' => :office,
        'application/vnd.oasis.opendocument.formula' => :office,
        'application/vnd.oasis.opendocument.graphics' => :office,
        'application/vnd.oasis.opendocument.graphics-template' => :office,
        'application/vnd.oasis.opendocument.presentation' => :office,
        'application/vnd.oasis.opendocument.presentation-template' => :office,
        'application/vnd.oasis.opendocument.spreadsheet' => :office,
        'application/vnd.oasis.opendocument.spreadsheet-template' => :office,
        'application/vnd.oasis.opendocument.text' => :office,
        'application/vnd.oasis.opendocument.text-template' => :office,
        'application/vnd.openxmlformats-officedocument.presentationml.presentation' => :office,
        'application/vnd.openxmlformats-officedocument.presentationml.slideshow' => :office,
        'application/vnd.openxmlformats-officedocument.presentationml.template' => :office,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' => :office,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.template' => :office,
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document' => :office,
        'application/vnd.openxmlformats-officedocument.wordprocessingml.template' => :office,
        'application/vnd.palm' => :office,
        'application/vnd.sun.xml.calc' => :office,
        'application/vnd.sun.xml.calc.template' => :office,
        'application/vnd.sun.xml.draw' => :office,
        'application/vnd.sun.xml.draw.template' => :office,
        'application/vnd.sun.xml.impress' => :office,
        'application/vnd.sun.xml.impress.template' => :office,
        'application/vnd.sun.xml.math' => :office,
        'application/vnd.sun.xml.writer' => :office,
        'application/vnd.sun.xml.writer.template' => :office,
        'application/vnd.wordperfect' => :office,
        'application/x-abiword' => :office,
        'application/x-director' => :image,
        'application/x-font-type1' => :image,
        'application/x-msmetafile' => :image,
        'application/x-mspublisher' => :office,
        'application/x-xfig' => :image,
        'audio/ogg' => :video,
        'font/ttf' => :image,
        'image/bmp' => :image,
        'image/cgm' => :image,
        'image/gif' => :image,
        'image/jpeg' => :image,
        'image/png' => :image,
        'image/sgi' => :image,
        'image/svg+xml' => :image,
        'image/tiff' => :image,
        'image/vnd.adobe.photoshop' => :image,
        'image/vnd.djvu' => :image,
        'image/vnd.dxf' => :office,
        'image/vnd.fpx' => :image,
        'image/vnd.ms-photo' => :image,
        'image/vnd.wap.wbmp' => :image,
        'image/webp' => :image,
        'image/x-cmx' => :office,
        'image/x-freehand' => :office,
        'image/x-icon' => :image,
        'image/x-mrsid-image' => :image,
        'image/x-pcx' => :image,
        'image/x-pict' => :office,
        'image/x-portable-anymap' => :image,
        'image/x-portable-bitmap' => :image,
        'image/x-portable-graymap' => :image,
        'image/x-portable-pixmap' => :image,
        'image/x-rgb' => :image,
        'image/x-tga' => :image,
        'image/x-xbitmap' => :image,
        'image/x-xpixmap' => :image,
        'image/x-xwindowdump' => :image,
        'text/csv' => :office,
        'text/html' => :office,
        'text/plain' => :plaintext,
        'text/troff' => :image,
        'video/h261' => :video,
        'video/h263' => :video,
        'video/h264' => :video,
        'video/mp4' => :video,
        'video/mpeg' => :video,
        'video/quicktime' => :video,
        'video/x-flv' => :video,
        'video/x-m4v' => :video,
        'video/x-matroska' => :video,
        'video/x-mng' => :image,
        'video/x-ms-wmv' => :video,
        'video/x-msvideo' => :video}

      # this is a way to add support for extensions that are otherwise not known by node api (mime type)
      SUPPORTED_EXTENSIONS={
        'aai' => :image,
        'art' => :image,
        'arw' => :image,
        'avs' => :image,
        'bmp2' => :image,
        'bmp3' => :image,
        'bpg' => :image,
        'cals' => :image,
        'cdr' => :office,
        'cin' => :image,
        'clipboard' => :image,
        'cmyk' => :image,
        'cmyka' => :image,
        'cr2' => :image,
        'crw' => :image,
        'cur' => :image,
        'cut' => :image,
        'cwk' => :office,
        'dbf' => :office,
        'dcm' => :image,
        'dcx' => :image,
        'dds' => :image,
        'dib' => :image,
        'dif' => :office,
        'divx' => :video,
        'dng' => :image,
        'dpx' => :image,
        'epdf' => :image,
        'epi' => :image,
        'eps2' => :image,
        'eps3' => :image,
        'epsf' => :image,
        'epsi' => :image,
        'ept' => :image,
        'exr' => :image,
        'fax' => :image,
        'fb2' => :office,
        'fits' => :image,
        'fodg' => :office,
        'fodp' => :office,
        'fods' => :office,
        'fodt' => :office,
        'gplt' => :image,
        'gray' => :image,
        'hdr' => :image,
        'hpw' => :office,
        'hrz' => :image,
        'info' => :image,
        'inline' => :image,
        'j2c' => :image,
        'j2k' => :image,
        'jbig' => :image,
        'jng' => :image,
        'jp2' => :image,
        'jpt' => :image,
        'jxr' => :image,
        'key' => :office,
        'mat' => :image,
        'mcw' => :office,
        'met' => :office,
        'miff' => :image,
        'mml' => :office,
        'mono' => :image,
        'mpr' => :image,
        'mrsid' => :image,
        'mrw' => :image,
        'mtv' => :image,
        'mvg' => :image,
        'mw' => :office,
        'mwd' => :office,
        'nef' => :image,
        'numbers' => :office,
        'orf' => :image,
        'otb' => :image,
        'p7' => :image,
        'pages' => :office,
        'palm' => :image,
        'pam' => :image,
        'pcd' => :image,
        'pcds' => :image,
        'pef' => :image,
        'picon' => :image,
        'pict' => :image,
        'pix' => :image,
        'pm' => :office,
        'pm6' => :office,
        'pmd' => :office,
        'png00' => :image,
        'png24' => :image,
        'png32' => :image,
        'png48' => :image,
        'png64' => :image,
        'png8' => :image,
        'ps2' => :image,
        'ps3' => :image,
        'ptif' => :image,
        'pwp' => :image,
        'rad' => :image,
        'raf' => :image,
        'rfg' => :image,
        'rgba' => :image,
        'rla' => :image,
        'rle' => :image,
        'sct' => :image,
        'sfw' => :image,
        'sgf' => :office,
        'sgv' => :office,
        'slk' => :office,
        'sparse-color' => :image,
        'sun' => :image,
        'svm' => :office,
        'sylk' => :office,
        'tim' => :image,
        'uil' => :image,
        'uof' => :office,
        'uop' => :office,
        'uos' => :office,
        'uot' => :office,
        'uyvy' => :image,
        'vds' => :office,
        'vdx' => :office,
        'vicar' => :image,
        'viff' => :image,
        'vsdx' => :office,
        'wb2' => :office,
        'wk1' => :office,
        'wk3' => :office,
        'wn' => :office,
        'wpg' => :image,
        'wq1' => :office,
        'wq2' => :office,
        'x' => :image,
        'x3f' => :image,
        'xcf' => :image,
        'xlk' => :office,
        'ycbcr' => :image,
        'ycbcra' => :image,
        'yuv' => :image,
        'zabw' => :office}

    end # Generator
  end # Preview
end # Asperalm
