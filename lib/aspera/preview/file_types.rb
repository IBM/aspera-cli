require 'aspera/log'
require 'singleton'

module Aspera
  module Preview
    # function conversion_type returns one of the types: CONVERSION_TYPES
    class FileTypes
      include Singleton
      # values for conversion_type : input format
      CONVERSION_TYPES=[
        :image,
        :office,
        :pdf,
        :plaintext,
        :video
      ]

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
        'docx' => :office,
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
        'log' => :plaintext,
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
        'mxf' => :video,
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
        'pdf' => :pdf,
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
        'txt' => :plaintext,
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
        'webm' => :video,
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
        'xlsx' => :office,
        'xls' => :office,
        'ycbcr' => :image,
        'ycbcra' => :image,
        'yuv' => :image,
        'zabw' => :office}

      private_constant :SUPPORTED_MIME_TYPES, :SUPPORTED_EXTENSIONS

      # @attr use_mimemagic [bool] true to use mimemagic to determine real mime type based on file content
      attr_accessor :use_mimemagic

      def initialize
        @use_mimemagic=false
      end

      # use mime magic to find mime type based on file content (magic numbers)
      def mime_from_file(filepath)
        # moved here, as mimemagic can cause installation issues
        require 'mimemagic'
        require 'mimemagic/version'
        require 'mimemagic/overlay' if MimeMagic::VERSION.start_with?('0.3.')
        # check magic number inside file (empty string if not found)
        detected_mime=MimeMagic.by_magic(File.open(filepath)).to_s
        # check extension only
        if !SUPPORTED_MIME_TYPES.has_key?(detected_mime)
          Log.log.debug("no conversion for #{detected_mime}, trying extension")
          detected_mime=MimeMagic.by_extension(File.extname(filepath)).to_s
        end
        detected_mime=nil if detected_mime.empty?
        Log.log.debug("mimemagic: #{detected_mime.class.name} [#{detected_mime}]")
        return detected_mime
      end

      # return file type, one of enum CONVERSION_TYPES
      # @param filepath [String] full path to file
      # @param mimetype [String] provided by node api
      def conversion_type(filepath,mimetype)
        Log.log.debug("conversion_type(#{filepath},m=#{mimetype},t=#{@use_mimemagic})")
        # 1- get type from provided mime type, using local mapping
        conv_type=SUPPORTED_MIME_TYPES[mimetype] if ! mimetype.nil?
        # 2- else, from computed mime type (if available)
        if conv_type.nil? and @use_mimemagic
          detected_mime=mime_from_file(filepath)
          if ! detected_mime.nil?
            conv_type=SUPPORTED_MIME_TYPES[detected_mime]
            if ! mimetype.nil?
              if mimetype.eql?(detected_mime)
                Log.log.debug('matching mime type per magic number')
              else
                # note: detected can be nil
                Log.log.debug("non matching mime types: node=[#{mimetype}], magic=[#{detected_mime}]")
              end
            end
          end
        end
        # 3- else, from extensions, using local mapping
        extension = File.extname(filepath.downcase)[1..-1]
        conv_type=SUPPORTED_EXTENSIONS[extension] if conv_type.nil?
        Log.log.debug("conversion_type(#{extension}): #{conv_type.class.name} [#{conv_type}]")
        return conv_type
      end
    end
  end
end
