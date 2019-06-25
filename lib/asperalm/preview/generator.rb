require 'open3'
require 'asperalm/preview/options'
require 'asperalm/preview/utils'
require 'asperalm/preview/file_types'

# TODO: option : do not match extensions
# TODO: option : do not match mime type
module Asperalm
  module Preview
    # generate preview files (png, mp4) for one file
    # private gen_combi_ methods are found by name gen_combi_<conversion_type>_<preview_format>
    # private gen_video_ methods are found by name gen_video_<vid_conv_method>
    # node api mime types are from: http://svn.apache.org/repos/asf/httpd/httpd/trunk/docs/conf/mime.types
    class Generator
      # values for preview_format : output format
      def self.preview_formats; [:png,:mp4];end

      # values for conversion_type : input format
      def self.conversion_types;[
          :image,
          :video,
          :office,
          :pdf,
          :plaintext
        ];end

      attr_reader :conversion_type

      def initialize(src,dst,mime_type=nil)
        @source=src
        @destination=dst
        @preview_format=File.extname(@destination).gsub(/^\./,'').to_sym
        @mime_type=mime_type
        if @mime_type.nil?
          require 'mimemagic'
          require 'mimemagic/overlay'
          @mime_type=MimeMagic.by_magic(File.open(src)).to_s
        end
        @conversion_type=FileTypes::SUPPORTED_MIME_TYPES[@mime_type]
        if @conversion_type.nil? and Options.instance.check_extension
          @conversion_type=FileTypes::SUPPORTED_EXTENSIONS[File.extname(@source).downcase.gsub(/^\./,'')]
        end
      end

      def processing_method_symb
        "gen_combi_#{@conversion_type}_#{@preview_format}".to_sym
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
        if Options.instance.validate_mime
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
        begin
          self.send(method_symb)
        rescue => e
          raise e
        end
      end

      private

      def gen_video_preview()
        duration = Utils.video_get_duration(@source)
        offset_seconds = Options.instance.vid_offset_seconds.to_i
        framecount = Options.instance.vid_framecount.to_i
        interval = Utils.calc_interval(duration,offset_seconds,framecount)
        tmpdir = Utils.mk_tmpdir(@source)
        previous = ''
        file_number = 1
        1.upto(framecount) do |i|
          filename = Utils.get_tmp_num_filepath(tmpdir, file_number)
          Utils.video_dump_frame(@source, offset_seconds, Options.instance.vid_size, filename)
          Utils.video_dupe_frame(filename, tmpdir, Options.instance.vid_framepause)
          Utils.video_blend_frames(previous, filename, tmpdir,Options.instance.vid_blendframes) if i > 1
          previous = Utils.get_tmp_num_filepath(tmpdir, file_number + Options.instance.vid_framepause)
          file_number += Options.instance.vid_framepause + Options.instance.vid_blendframes + 1
          offset_seconds+=interval
        end
        Utils.ffmpeg(Utils.ffmpeg_fmt(tmpdir),
        ['-framerate',Options.instance.vid_fps],
        @destination,
        ['-filter:v',"scale='trunc(iw/2)*2:trunc(ih/2)*2'",'-codec:v','libx264','-r',30,'-pix_fmt','yuv420p'])
        FileUtils.rm_rf(tmpdir)
      end

      def gen_video_clips()
        # dump clips
        duration = Utils.video_get_duration(@source)
        offset_seconds = Options.instance.clips_offset_seconds.to_i
        clips_cnt=Options.instance.clips_count
        interval = Utils.calc_interval(duration,offset_seconds,clips_cnt)
        tmpdir = Utils.mk_tmpdir(@source)
        filelist = File.join(tmpdir,'files.txt')
        File.open(filelist, 'w+') do |f|
          1.upto(clips_cnt) do |i|
            tmpfilename=sprintf("img%04d.mp4",i)
            Utils.ffmpeg(@source,
            ['-ss',0.9*offset_seconds],
            File.join(tmpdir,tmpfilename),
            ['-ss',0.1*offset_seconds,'-t',Options.instance.clips_length,'-filter:v',"scale=#{Options.instance.clips_size}",'-codec:a','copy'])
            f.puts("file '#{tmpfilename}'")
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
        Utils.ffmpeg(@source,[],@destination,[
          '-t','60',
          '-codec:v','libx264',
          '-profile:v','high',
          '-pix_fmt','yuv420p',
          '-preset','slow',
          '-b:v','500k',
          '-maxrate','500k',
          '-bufsize','1000k',
          '-filter:v',"scale=#{Options.instance.vid_mp4_size_reencode}",
          '-threads','0',
          '-codec:a','libmp3lame',
          '-ac','2',
          '-b:a','128k',
          '-movflags','faststart'])
      end

      def gen_combi_video_mp4()
        self.send("gen_video_#{Options.instance.vid_conv_method}".to_sym)
      end

      def gen_combi_office_png()
        tmpdir=Utils.mk_tmpdir(@source)
        libreoffice_exec='libreoffice'
        #TODO: detect on mac:
        #libreoffice_exec='/Applications/LibreOffice.app/Contents/MacOS/soffice'
        Utils.external_command([libreoffice_exec,'--display',':42','--headless','--invisible','--convert-to','pdf',
          '--outdir',tmpdir,@source])
        saved_source=@source
        pdf_file=File.join(tmpdir,File.basename(@source,File.extname(@source))+'.pdf')
        @source=pdf_file
        gen_combi_pdf_png()
        @source=saved_source
        #File.delete(pdf_file)
        FileUtils.rm_rf(tmpdir)
      end

      def gen_combi_pdf_png()
        Utils.external_command(['convert',
          '-size',"x#{Options.instance.thumb_img_size}",
          '-background','white',
          '-flatten',
          "#{@source}[0]",
          @destination])
      end

      def gen_combi_image_png()
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
      def gen_combi_plaintext_png()
        # get 100 first lines of text file
        first_lines=File.open(@source){|f|100.times.map{f.readline}}.join
        Utils.external_command(['convert',
          '-size',"#{Options.instance.thumb_img_size}x#{Options.instance.thumb_img_size}",
          'xc:white',
          '-font','Courier',
          '-pointsize',12,
          '-fill','black',
          '-annotate','+15+15',first_lines,
          '-trim',
          '-bordercolor','#FFF',
          '-border',10,
          '+repage',
          @destination])
      end

      def gen_combi_video_png()
        Utils.video_dump_frame(@source,Utils.video_get_duration(@source)*Options.instance.thumb_offset_fraction,Options.instance.thumb_mp4_size, @destination)
      end

    end # Generator
  end # Preview
end # Asperalm
