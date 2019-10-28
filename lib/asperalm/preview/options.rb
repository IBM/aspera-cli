module Asperalm
  module Preview
    # generator options. Used as parameter to preview generator object.
    # also settable by command line.
    class Options
      # types of generation for video files
      VIDEO_CONVERSION_METHODS=[:preview,:reencode,:clips]
      # options used in generator
      DESCRIPTIONS = [
        { :name => :video_conversion, :default => :reencode, :values => VIDEO_CONVERSION_METHODS, :description => "method for video preview generation" },
        { :name => :vid_size, :default => '320:-2', :description => "preview only: video size" },
        { :name => :vid_offset_seconds, :default => 10, :description => "preview only: " },
        { :name => :vid_framecount, :default => 30, :description => "preview only: " },
        { :name => :vid_blendframes, :default => 2, :description => "preview only: " },
        { :name => :vid_framepause, :default => 5, :description => "preview only: " },
        { :name => :vid_fps, :default => 15, :description => "preview only: " },
        { :name => :reencode_size, :default => "-2:'min(ih,360)'", :description => "reencode only: video size" },
        { :name => :clips_size, :default => '320:-2', :description => "clips only: video size of clip" },
        { :name => :clips_offset_seconds, :default => 10, :description => "clips only: start time" },
        { :name => :clips_length, :default => 5, :description => "clips only: length in seconds of each clips" },
        { :name => :clips_count, :default => 5, :description => "clips only: number of clips" },
        { :name => :thumb_vid_size, :default => "-1:'min(ih,600)'", :description => "size of thumbnail of video (ffmpeg scale argument)" },
        { :name => :thumb_vid_fraction, :default => 0.1, :description => "fraction of video where to take snapshot for thumbnail" },
        { :name => :thumb_img_size, :default => 800, :description => "height of thumbnail of non video" },
        { :name => :validate_mime, :default => :no, :description => "produce warning if mime type of node api is different than file analysis" },
        { :name => :check_extension, :default => :yes, :description => "check additional extension that are not supported by node api" },
        { :name => :max_size, :default => 1<<24, :description => "maximum size of preview file" },
      ]
      # add accessors
      DESCRIPTIONS.each do |opt|
        attr_accessor opt[:name]
      end
    end # Options
  end # Preview
end # Asperalm
