# frozen_string_literal: true

require 'aspera/log'
require 'singleton'
require 'mime/types'

module Aspera
  module Preview
    # function conversion_type returns one of the types: CONVERSION_TYPES
    class FileTypes
      include Singleton
      # values for conversion_type : input format
      CONVERSION_TYPES = %i[image office pdf plaintext video].freeze

      # special cases for mime types
      # spellchecker:disable
      SUPPORTED_MIME_TYPES = {
        'application/json'                   => :plaintext,
        'text/plain'                         => :plaintext,
        'application/pdf'                    => :pdf,
        'audio/ogg'                          => :video,
        'application/mxf'                    => :video,
        'application/mac-binhex40'           => :office,
        'application/msword'                 => :office,
        'application/rtf'                    => :office,
        'application/x-abiword'              => :office,
        'application/x-mspublisher'          => :office,
        'image/vnd.dxf'                      => :office,
        'image/x-cmx'                        => :office,
        'image/x-freehand'                   => :office,
        'image/x-pict'                       => :office,
        'text/csv'                           => :office,
        'text/html'                          => :office,
        'application/dicom'                  => :image,
        'application/postscript'             => :image,
        'application/vnd.3gpp.pic-bw-small'  => :image,
        'application/vnd.hp-hpgl'            => :image,
        'application/vnd.hp-pcl'             => :image,
        'application/vnd.mobius.msl'         => :image,
        'application/vnd.mophun.certificate' => :image,
        'application/x-director'             => :image,
        'application/x-font-type1'           => :image,
        'application/x-msmetafile'           => :image,
        'application/x-xfig'                 => :image,
        'font/ttf'                           => :image,
        'text/troff'                         => :image,
        'video/x-mng'                        => :image}.freeze

      private_constant :SUPPORTED_MIME_TYPES

      # @attr use_mimemagic [bool] true to use mimemagic to determine real mime type based on file content
      attr_accessor :use_mimemagic

      def initialize
        @use_mimemagic = false
      end

      # @param mimetype [String] mime type
      # @return file type, one of enum CONVERSION_TYPES
      def mime_to_type(mimetype)
        return SUPPORTED_MIME_TYPES[mimetype] if SUPPORTED_MIME_TYPES.key?(mimetype)
        return :office if mimetype.start_with?('application/vnd.')
        return :video if mimetype.start_with?('video/')
        return :image if mimetype.start_with?('image/')
        return nil
      end

      # use mime magic to find mime type based on file content (magic numbers)
      def file_to_mime(filepath)
        # moved here, as `mimemagic` can cause installation issues
        require 'mimemagic'
        require 'mimemagic/version'
        require 'mimemagic/overlay' if MimeMagic::VERSION.start_with?('0.3.')
        # check magic number inside file (empty string if not found)
        detected_mime = MimeMagic.by_magic(File.open(filepath)).to_s
        # check extension only
        if mime_to_type(detected_mime).nil?
          Log.log.debug{"no conversion for #{detected_mime}, trying extension"}
          detected_mime = MimeMagic.by_extension(File.extname(filepath)).to_s
        end
        detected_mime = nil if detected_mime.empty?
        Log.log.debug{"mimemagic: #{detected_mime.class.name} [#{detected_mime}]"}
        return detected_mime
      end

      # @param filepath [String] full path to file
      # @param mimetype [String] provided by node API
      # @return file type, one of enum CONVERSION_TYPES
      # @raise [RuntimeError] if no conversion type found
      def conversion_type(filepath, mimetype)
        Log.log.debug{"conversion_type(#{filepath},m=#{mimetype},t=#{@use_mimemagic})"}
        # 1- get type from provided mime type, using local mapping
        conversion_type = mime_to_type(mimetype) if !mimetype.nil?
        # 2- else, from computed mime type (if available)
        if conversion_type.nil? && @use_mimemagic
          detected_mime = file_to_mime(filepath)
          if !detected_mime.nil?
            conversion_type = mime_to_type(detected_mime)
            if !mimetype.nil?
              if mimetype.eql?(detected_mime)
                Log.log.debug('matching mime type per magic number')
              else
                # NOTE: detected can be nil
                Log.log.debug{"non matching mime types: node=[#{mimetype}], magic=[#{detected_mime}]"}
              end
            end
          end
        end
        # 3- else, from extensions, using local mapping
        mime_by_ext = MIME::Types.of(File.basename(filepath)).first
        conversion_type = mime_to_type(mime_by_ext.to_s) if conversion_type.nil? && !mime_by_ext.nil?
        raise "no conversion type found for #{File.basename(filepath)}" if conversion_type.nil?
        Log.log.trace1{"conversion_type(#{File.basename(filepath)}): #{conversion_type.class.name} [#{conversion_type}]"}
        return conversion_type
      end
    end
  end
end
