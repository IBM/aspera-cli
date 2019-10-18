require 'open3'
require 'asperalm/preview/options'
require 'asperalm/preview/utils'
require 'asperalm/preview/file_types'
require 'mimemagic'
require 'mimemagic/overlay'

# TODO: option : do not match extensions
# TODO: option : do not match mime type
module Asperalm
  module Preview
    # generate one preview file for one format for one file at a time
    class Generator
      # values for preview_format : output format
      PREVIEW_FORMATS=[:png,:mp4]

      attr_reader :conversion_type

      # @param src source file path
      # @param dst destination file path
      # @param mime_type optional mime type as provided by node api
      # node API mime types are from: http://svn.apache.org/repos/asf/httpd/httpd/trunk/docs/conf/mime.types
      # supported preview type is one of Preview::PREVIEW_FORMATS
      # the resulting preview file type is taken from destination file extension.
      # conversion methods are provided by private methods: gen_combi_<conversion_type>_<preview_format>
      # (combi = combination of source file type and destination format)
      #   -> conversion_type is one of FileTypes::CONVERSION_TYPES
      #   -> preview_format is one of Generator::PREVIEW_FORMATS
      # the conversion video->mp4 is implemented in methods: gen_video_<video_conversion>
      #  -> conversion method is one of Generator::VIDEO_CONVERSION_METHODS
      def initialize(options,src,dst,mime_type=nil)
        @options=options
        @source_file_path=src
        @destination_file_path=dst
        # extract preview format from extension of target file
        @preview_format=File.extname(@destination_file_path).gsub(/^\./,'').to_sym
        @mime_type=mime_type
        if @mime_type.nil?
          @mime_type=MimeMagic.by_magic(File.open(src)).to_s
        end
        @conversion_type=FileTypes::SUPPORTED_MIME_TYPES[@mime_type]
        if @conversion_type.nil? and @options.check_extension
          @conversion_type=FileTypes::SUPPORTED_EXTENSIONS[File.extname(@source_file_path).downcase.gsub(/^\./,'')]
        end
      end

      def processing_method_symb
        "gen_combi_#{@conversion_type}_#{@preview_format}".to_sym
      end

      def supported?
        return respond_to?(processing_method_symb,true)
      end

      #      def self.generators(extension,mime_type)
      #        PREVIEW_FORMATS.map {|preview_format|Generator.new(preview_format,extension,mime_type)}
      #      end

      # create preview as specified in constructor
      def generate
        method_symb=processing_method_symb
        Log.log.info("#{@source_file_path}->#{@destination_file_path} (#{method_symb})")
        if @options.validate_mime
          magic_mime_type=MimeMagic.by_magic(File.open(@source_file_path)).to_s
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
        # check that generated size does not exceed maximum
        result_size=File.size(@destination_file_path)
        if result_size > @options.max_size
          Log.log.warn("preview size exceeds maximum #{result_size} > #{@options.max_size}")
        end
      end

      private

      def mk_tmpdir(input_file)
        # TODO: get parameter from plugin
        maintmp=Dir.tmpdir
        temp_folder=File.join(maintmp,input_file.split('/').last.gsub(/\s/, '_').gsub(/\W/, ''))
        FileUtils.mkdir_p(temp_folder)
        return temp_folder
      end

      # @return interval duration in seconds to have "count" intervals between offset and end
      def calc_interval(duration, offset_seconds, count)
        (duration - offset_seconds) / count
      end

      def gen_video_preview()
        duration = Utils.video_get_duration(@source_file_path)
        offset_seconds = @options.vid_offset_seconds.to_i
        framecount = @options.vid_framecount.to_i
        interval = calc_interval(duration,offset_seconds,framecount)
        temp_folder = mk_tmpdir(@source_file_path)
        previous = ''
        file_number = 1
        1.upto(framecount) do |i|
          filename = Utils.get_tmp_num_filepath(temp_folder, file_number)
          Utils.video_dump_frame(@source_file_path, offset_seconds, @options.vid_size, filename)
          Utils.video_dupe_frame(filename, temp_folder, @options.vid_framepause)
          Utils.video_blend_frames(previous, filename, temp_folder,@options.vid_blendframes) if i > 1
          previous = Utils.get_tmp_num_filepath(temp_folder, file_number + @options.vid_framepause)
          file_number += @options.vid_framepause + @options.vid_blendframes + 1
          offset_seconds+=interval
        end
        Utils.ffmpeg(Utils.ffmpeg_fmt(temp_folder),
        ['-framerate',@options.vid_fps],
        @destination_file_path,
        ['-filter:v',"scale='trunc(iw/2)*2:trunc(ih/2)*2'",'-codec:v','libx264','-r',30,'-pix_fmt','yuv420p'])
        FileUtils.rm_rf(temp_folder)
      end

      # generate n clips starting at offset
      def gen_video_clips()
        # dump clips
        duration = Utils.video_get_duration(@source_file_path)
        offset_seconds = @options.clips_offset_seconds.to_i
        clips_cnt=@options.clips_count
        interval = calc_interval(duration,offset_seconds,clips_cnt)
        temp_folder = mk_tmpdir(@source_file_path)
        filelist = File.join(temp_folder,'files.txt')
        File.open(filelist, 'w+') do |f|
          1.upto(clips_cnt) do |i|
            tmpfilename=sprintf("img%04d.mp4",i)
            Utils.ffmpeg(@source_file_path,
            ['-ss',0.9*offset_seconds],
            File.join(temp_folder,tmpfilename),
            ['-ss',0.1*offset_seconds,'-t',@options.clips_length,'-filter:v',"scale=#{@options.clips_size}",'-codec:a','libmp3lame'])
            f.puts("file '#{tmpfilename}'")
            offset_seconds += interval
          end
        end
        # concat clips
        Utils.ffmpeg(filelist,
        ['-f','concat'],
        @destination_file_path,
        ['-codec','copy'])
        FileUtils.rm_rf(temp_folder)
      end

      # do a simple reencoding
      def gen_video_reencode()
        Utils.ffmpeg(@source_file_path,[],@destination_file_path,[
          '-t','60',
          '-codec:v','libx264',
          '-profile:v','high',
          '-pix_fmt','yuv420p',
          '-preset','slow',
          '-b:v','500k',
          '-maxrate','500k',
          '-bufsize','1000k',
          '-filter:v',"scale=#{@options.reencode_size}",
          '-threads','0',
          '-codec:a','libmp3lame',
          '-ac','2',
          '-b:a','128k',
          '-movflags','faststart'])
      end

      def gen_combi_video_mp4()
        self.send("gen_video_#{@options.video_conversion}".to_sym)
      end

      def gen_combi_office_png()
        temp_folder=mk_tmpdir(@source_file_path)
        libreoffice_exec='libreoffice'
        #TODO: detect on mac:
        #libreoffice_exec='/Applications/LibreOffice.app/Contents/MacOS/soffice'
        Utils.external_command([libreoffice_exec,'--display',':42','--headless','--invisible','--convert-to','pdf',
          '--outdir',temp_folder,@source_file_path])
        saved_source=@source_file_path
        pdf_file=File.join(temp_folder,File.basename(@source_file_path,File.extname(@source_file_path))+'.pdf')
        @source_file_path=pdf_file
        gen_combi_pdf_png()
        @source_file_path=saved_source
        #File.delete(pdf_file)
        FileUtils.rm_rf(temp_folder)
      end

      def gen_combi_pdf_png()
        Utils.external_command(['convert',
          '-size',"x#{@options.thumb_img_size}",
          '-background','white',
          '-flatten',
          "#{@source_file_path}[0]",
          @destination_file_path])
      end

      def gen_combi_image_png()
        Utils.external_command(['convert',
          '-auto-orient',
          '-thumbnail',"#{@options.thumb_img_size}x#{@options.thumb_img_size}>",
          '-quality',95,
          '+dither',
          '-posterize',40,
          "#{@source_file_path}[0]",
          @destination_file_path])
        Utils.external_command(['optipng',@destination_file_path])
      end

      # text to png
      def gen_combi_plaintext_png()
        # get 100 first lines of text file
        first_lines=File.open(@source_file_path){|f|100.times.map{f.readline rescue ''}}.join
        Utils.external_command(['convert',
          '-size',"#{@options.thumb_img_size}x#{@options.thumb_img_size}",
          'xc:white',
          '-font','Courier',
          '-pointsize',12,
          '-fill','black',
          '-annotate','+15+15',first_lines,
          '-trim',
          '-bordercolor','#FFF',
          '-border',10,
          '+repage',
          @destination_file_path])
      end

      def gen_combi_video_png()
        Utils.video_dump_frame(
        @source_file_path,
        Utils.video_get_duration(@source_file_path)*@options.thumb_vid_fraction,
        @options.thumb_vid_size,
        @destination_file_path)
      end

    end # Generator
  end # Preview
end # Asperalm
