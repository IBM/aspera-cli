# frozen_string_literal: true

require 'open3'
require 'aspera/preview/options'
require 'aspera/preview/utils'
require 'aspera/preview/file_types'

module Aspera
  module Preview
    # generate one preview file for one format for one file at a time
    class Generator
      # values for preview_format : output format
      PREVIEW_FORMATS = [:png,:mp4]

      # CLI needs to know conversion type to know if need skip it
      attr_reader :conversion_type

      # @param src source file path
      # @param dst destination file path
      # @param api_mime_type optional mime type as provided by node api (or nil)
      # node API mime types are from: http://svn.apache.org/repos/asf/httpd/httpd/trunk/docs/conf/mime.types
      # supported preview type is one of Preview::PREVIEW_FORMATS
      # the resulting preview file type is taken from destination file extension.
      # conversion methods are provided by private methods: convert_<conversion_type>_to_<preview_format>
      # (combi = combination of source file type and destination format)
      #   -> conversion_type is one of FileTypes::CONVERSION_TYPES
      #   -> preview_format is one of Generator::PREVIEW_FORMATS
      # the conversion video->mp4 is implemented in methods: convert_video_to_mp4_using_<video_conversion>
      #  -> conversion method is one of Generator::VIDEO_CONVERSION_METHODS
      def initialize(options,src,dst,main_temp_dir,api_mime_type)
        @options = options
        @source_file_path = src
        @destination_file_path = dst
        @temp_folder = File.join(main_temp_dir,@source_file_path.split('/').last.gsub(/\s/, '_').gsub(/\W/, ''))
        # extract preview format from extension of target file
        @preview_format_symb = File.extname(@destination_file_path).gsub(/^\./,'').to_sym
        @conversion_type = FileTypes.instance.conversion_type(@source_file_path,api_mime_type)
      end

      # name of processing method in this object
      # combination of: conversion type and output format (and video_conversion for video)
      def processing_method_symb
        name = "convert_#{@conversion_type}_to_#{@preview_format_symb}"
        if @conversion_type.eql?(:video)
          case @preview_format_symb
          when :mp4
            name = "#{name}_using_#{@options.video_conversion}"
          when :png
            name = "#{name}_using_#{@options.video_png_conv}"
          end
        end
        Log.log.debug("method: #{name}")
        return name.to_sym
      end

      # @return true if conversion is supported.
      # for instance, plaintext to mp4 is not supported
      def supported?
        return false if @conversion_type.nil?
        return respond_to?(processing_method_symb,true)
      end

      # create preview as specified in constructor
      def generate
        raise 'could not detect type of file' if @conversion_type.nil?
        method_symb = processing_method_symb
        Log.log.info("#{@source_file_path}->#{@destination_file_path} (#{method_symb})")
        begin
          send(method_symb)
          # check that generated size does not exceed maximum
          result_size = File.size(@destination_file_path)
          if result_size > @options.max_size
            Log.log.warn("preview size exceeds maximum #{result_size} > #{@options.max_size}")
          end
        rescue StandardError => e
          Log.log.error("Ignoging: #{e.message.to_s}")
          Log.log.debug(e.backtrace.join("\n").red)
          FileUtils.cp(File.expand_path(@preview_format_symb.eql?(:mp4) ? 'video_error.png' : 'image_error.png',File.dirname(__FILE__)),@destination_file_path)
        ensure
          FileUtils.rm_rf(@temp_folder)
        end
      end

      private

      # creates a unique temp folder for file
      def this_tmpdir
        FileUtils.mkdir_p(@temp_folder)
        return @temp_folder
      end

      # @return offset in seconds suitable for ffmpeg -ss option
      # @param duration of video
      # @param start_offset of parts
      # @param total_count of parts
      # @param index of part (start at 1)
      def get_offset(duration, start_offset, total_count, index)
        raise 'duration must be Float' unless duration.is_a?(Float)
        return start_offset + ((index - 1) * (duration - start_offset) / total_count)
      end

      def convert_video_to_mp4_using_blend
        p_duration = Utils.video_get_duration(@source_file_path)
        p_start_offset = @options.video_start_sec.to_i
        p_keyframecount = @options.blend_keyframes.to_i
        last_keyframe = nil
        current_index = 1
        1.upto(p_keyframecount) do |i|
          offset_seconds = get_offset(p_duration,p_start_offset,p_keyframecount,i)
          Utils.video_dump_frame(@source_file_path, offset_seconds, @options.video_scale, this_tmpdir, current_index)
          Utils.video_dupe_frame(this_tmpdir, current_index, @options.blend_pauseframes)
          Utils.video_blend_frames(this_tmpdir,last_keyframe, current_index) unless last_keyframe.nil?
          # go to last dupe frame
          last_keyframe = current_index + @options.blend_pauseframes
          # go after last dupe frame and keep space to blend
          current_index = last_keyframe + 1 + @options.blend_transframes
        end
        Utils.ffmpeg(
        in_f: Utils.ffmpeg_fmt(this_tmpdir),
        in_p: ['-framerate',@options.blend_fps],
        out_f: @destination_file_path,
        out_p: [
          '-filter:v',"scale='trunc(iw/2)*2:trunc(ih/2)*2'",
          '-codec:v','libx264',
          '-r',30,
          '-pix_fmt','yuv420p'])
      end

      # generate n clips starting at offset
      def convert_video_to_mp4_using_clips
        p_duration = Utils.video_get_duration(@source_file_path)
        filelist = File.join(this_tmpdir,'clip_files.txt')
        File.open(filelist, 'w+') do |f|
          1.upto(@options.clips_count.to_i) do |i|
            offset_seconds = get_offset(p_duration,@options.video_start_sec.to_i,@options.clips_count.to_i,i)
            tmpfilename = format('clip%04d.mp4',i)
            Utils.ffmpeg(
            in_f: @source_file_path,
            in_p: ['-ss',0.9 * offset_seconds],
            out_f: File.join(this_tmpdir,tmpfilename),
            out_p: [
              '-ss',0.1 * offset_seconds,
              '-t',@options.clips_length,
              '-filter:v',"scale=#{@options.video_scale}",
              '-codec:a','libmp3lame'])
            f.puts("file '#{tmpfilename}'")
          end
        end
        # concat clips
        Utils.ffmpeg(
        in_f: filelist,
        in_p: ['-f','concat'],
        out_f: @destination_file_path,
        out_p: ['-codec','copy'])
      end

      # do a simple reencoding
      def convert_video_to_mp4_using_reencode
        Utils.ffmpeg(
        in_f: @source_file_path,
        out_f: @destination_file_path,
        out_p: [
          '-t','60',
          '-codec:v','libx264',
          '-profile:v','high',
          '-pix_fmt','yuv420p',
          '-preset','slow',
          '-b:v','500k',
          '-maxrate','500k',
          '-bufsize','1000k',
          '-filter:v',"scale=#{@options.video_scale}",
          '-threads','0',
          '-codec:a','libmp3lame',
          '-ac','2',
          '-b:a','128k',
          '-movflags','faststart'])
      end

      def convert_video_to_png_using_fixed
        Utils.video_dump_frame(
        @source_file_path,
        Utils.video_get_duration(@source_file_path) * @options.thumb_vid_fraction,
        @options.thumb_vid_scale,
        @destination_file_path)
      end

      # https://trac.ffmpeg.org/wiki/SponsoringPrograms/GSoC/2015#AnimatedPortableNetworkGraphicsAPNG
      # ffmpeg -h muxer=apng
      # thumb is 32x32
      # ffmpeg  output.png
      def convert_video_to_png_using_animated
        Utils.ffmpeg(
        in_f: @source_file_path,
        in_p: [
          '-ss',10, # seek to input position
          '-t',20 # max seconds
        ],
        out_f: @destination_file_path,
        out_p: [
          '-vf','fps=5,scale=120:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse',
          '-loop',0,
          '-f','gif'
        ])
      end

      def convert_office_to_png
        tmp_pdf_file = File.join(this_tmpdir,File.basename(@source_file_path,File.extname(@source_file_path)) + '.pdf')
        Utils.external_command(:unoconv,[
          '-f','pdf',
          '-o',tmp_pdf_file,
          @source_file_path])
        convert_pdf_to_png(tmp_pdf_file)
      end

      def convert_pdf_to_png(source_file_path=nil)
        source_file_path ||= @source_file_path
        Utils.external_command(:convert,[
          '-size',"x#{@options.thumb_img_size}",
          '-background','white',
          '-flatten',
          "#{source_file_path}[0]",
          @destination_file_path])
      end

      def convert_image_to_png
        Utils.external_command(:convert,[
          '-auto-orient',
          '-thumbnail',"#{@options.thumb_img_size}x#{@options.thumb_img_size}>",
          '-quality',95,
          '+dither',
          '-posterize',40,
          "#{@source_file_path}[0]",
          @destination_file_path])
        Utils.external_command(:optipng,[@destination_file_path])
      end

      # text to png
      def convert_plaintext_to_png
        # get 100 first lines of text file
        first_lines = File.open(@source_file_path){|f|Array.new(100){f.readline rescue ''}.join}
        Utils.external_command(:convert,[
          '-size',"#{@options.thumb_img_size}x#{@options.thumb_img_size}",
          'xc:white', # define canvas with background color (xc, or canvas) of preceding size
          '-font',@options.thumb_text_font,
          '-pointsize',12,
          '-fill','black', # font color
          '-annotate','+0+0',first_lines,
          '-trim', # avoid large blank regions
          '-bordercolor','white',
          '-border',8,
          '+repage',
          @destination_file_path])
      end
    end # Generator
  end # Preview
end # Aspera
