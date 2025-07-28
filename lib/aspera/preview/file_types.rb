# frozen_string_literal: true

require 'aspera/log'
require 'aspera/assert'
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
        'application/vnd.ms-excel'           => :office,
        'application/vnd.ms-powerpoint'      => :office,
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
      # @return file type, one of enum CONVERSION_TYPES, or nil if not found
      def mime_to_type(mimetype)
        Aspera.assert_type(mimetype, String)
        return SUPPORTED_MIME_TYPES[mimetype] if SUPPORTED_MIME_TYPES.key?(mimetype)
        return :office if mimetype.start_with?('application/vnd.ms-')
        return :office if mimetype.start_with?('application/vnd.openxmlformats-officedocument')
        return :video if mimetype.start_with?('video/')
        return :image if mimetype.start_with?('image/')
        return nil
      end

      # @param filepath [String] full path to file
      # @param mimetype [String] provided by node API
      # @return file type, one of enum CONVERSION_TYPES
      # @raise [RuntimeError] if no conversion type found
      def conversion_type(filepath, mimetype)
        Log.log.debug{"conversion_type(#{filepath},mime=#{mimetype},magic=#{@use_mimemagic})"}
        mimetype = nil if mimetype.is_a?(String) && (mimetype == 'application/octet-stream' || mimetype.empty?)
        # Use mimemagic if available
        mimetype ||= mime_using_mimemagic(filepath)
        mimetype ||= mime_using_file(filepath)
        # from extensions, using local mapping
        mimetype ||= MIME::Types.of(File.basename(filepath)).first
        raise "no MIME type found for #{File.basename(filepath)}" if mimetype.nil?
        conversion_type = mime_to_type(mimetype)
        raise "no conversion type found for #{File.basename(filepath)}" if conversion_type.nil?
        Log.log.trace1{"conversion_type(#{File.basename(filepath)}): #{conversion_type.class.name} [#{conversion_type}]"}
        return conversion_type
      end

      private

      # Use mime magic to find mime type based on file content (magic numbers)
      # @param filepath [String] full path to file
      # @return [String] mime type, or nil if not found
      def mime_using_mimemagic(filepath)
        return unless @use_mimemagic
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

      # Use 'file' command to find mime type based on file content (Unix)
      def mime_using_file(filepath)
        return Environment.secure_capture(exec: 'file', args: ['--mime-type', '--brief', filepath]).strip
      rescue => e
        Log.log.error{"error using 'file' command: #{e.message}"}
        return nil
      end
    end
  end
end
