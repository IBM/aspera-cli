# frozen_string_literal: true

require 'aspera/log'
require 'aspera/assert'
require 'singleton'
require 'marcel'

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
        'video/x-mng'                        => :image
      }.freeze

      private_constant :SUPPORTED_MIME_TYPES

      # @attr use_mimemagic [Boolean] `true` to use mimemagic to determine real mime type based on file content
      attr_accessor :use_mimemagic

      def initialize
        @use_mimemagic = false
      end

      # @param mimetype [String] mime type
      # @return [NilClass,Symbol] file type, one of enum CONVERSION_TYPES, or nil if not found
      def mime_to_type(mimetype)
        Aspera.assert_type(mimetype, String)
        return SUPPORTED_MIME_TYPES[mimetype] if SUPPORTED_MIME_TYPES.key?(mimetype)
        return :office if mimetype.start_with?('application/vnd.ms-')
        return :office if mimetype.start_with?('application/vnd.openxmlformats-officedocument')
        return :video if mimetype.start_with?('video/')
        return :image if mimetype.start_with?('image/')
        return
      end

      # @param filepath [String] Full path to file
      # @param mimetype [String] MIME typre provided by node API
      # @return file type, one of enum CONVERSION_TYPES
      # @raise [RuntimeError] if no conversion type found
      def conversion_type(filepath, mimetype)
        Log.log.debug{"conversion_type(#{filepath},mime=#{mimetype},magic=#{@use_mimemagic})"}
        # Default type or empty means no type
        mimetype = TYPE_NOT_FOUND if mimetype.nil? || (mimetype.is_a?(String) && mimetype.empty?)
        mimetype = Marcel::MimeType.for(Pathname.new(filepath), name: File.basename(filepath), declared_type: mimetype)
        mimetype = 'text/plain' if mimetype.eql?(TYPE_NOT_FOUND) && ascii_text_file?(filepath)
        raise "no MIME type found for #{File.basename(filepath)}" if mimetype.eql?(TYPE_NOT_FOUND)
        conversion_type = mime_to_type(mimetype)
        raise "no conversion type found for #{File.basename(filepath)}" if conversion_type.nil?
        Log.log.trace1{"conversion_type(#{File.basename(filepath)}): #{conversion_type.class.name} [#{conversion_type}]"}
        return conversion_type
      end

      private

      TYPE_NOT_FOUND = 'application/octet-stream'
      ACCEPT_CTRL_CHARS = [9, 10, 13]

      # Returns true if the file looks like ASCII text (printable ASCII + \t, \r, \n, space).
      # It reads only a small prefix (default: 64KB) and fails fast on the first bad byte.
      def ascii_text_file?(path, sample_size: 64 * 1024)
        File.open(path, 'rb') do |f|
          sample = f.read(sample_size) || ''.b
          sample.each_byte do |b|
            next if b.between?(32, 126) || ACCEPT_CTRL_CHARS.include?(b)
            # Any other control character => not ASCII text
            return false
          end
          true
        end
      end
    end
  end
end
