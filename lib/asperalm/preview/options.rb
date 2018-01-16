require 'singleton'
module Asperalm
  module Preview
    class Options
      include Singleton
      attr_accessor :vid_conv_method
      attr_accessor :vid_offset_seconds
      attr_accessor :vid_size
      attr_accessor :vid_framecount
      attr_accessor :vid_blendframes
      attr_accessor :vid_framepause
      attr_accessor :vid_fps
      attr_accessor :vid_mp4_size_reencode
      attr_accessor :clips_offset_seconds
      attr_accessor :clips_size
      attr_accessor :clips_length
      attr_accessor :clips_count
      attr_accessor :thumb_mp4_size
      attr_accessor :thumb_img_size
      attr_accessor :thumb_offset_fraction
      attr_accessor :validate_mime
      attr_accessor :check_extension
      attr_accessor :tmpdir
      # values for option_vid_conv_method
      def self.vid_conv_methods; [:reencode,:clips,:preview];end
    end # Options
  end # Preview
end # Asperalm
