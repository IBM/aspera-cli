module Aspera
  module Preview
    # generator options. Used as parameter to preview generator object.
    # also settable by command line.
    class Options
      # types of generation for video files
      VIDEO_CONVERSION_METHODS=[:reencode,:blend,:clips]
      VIDEO_THUMBNAIL_METHODS=[:fixed,:animated]
      # options used in generator
      # for scaling see: https://trac.ffmpeg.org/wiki/Scaling
      # iw/ih : input width or height
      # -x : keep aspect ratio, having value a multiple of x
      DESCRIPTIONS = [
        { name: :max_size,             default: 1<<24,              description: "maximum size (in bytes) of preview file" },
        { name: :thumb_vid_scale,      default: "-1:'min(ih,100)'", description: "png: video: size (ffmpeg scale argument)" },
        { name: :thumb_vid_fraction,   default: 0.1,                description: "png: video: position of snapshot" },
        { name: :thumb_img_size,       default: 800,                description: "png: non-video: height (and width)" },
        { name: :thumb_text_font,      default: 'Courier',          description: "png: plaintext: font to render text with image magick convert, list with: identify -list font" },
        { name: :video_conversion,     default: :reencode,          description: "mp4: method for preview generation", values: VIDEO_CONVERSION_METHODS },
        { name: :video_png_conv,       default: :fixed,             description: "mp4: method for thumbnail generation", values: VIDEO_THUMBNAIL_METHODS },
        { name: :video_start_sec,      default: 10,                 description: "mp4: start offset (seconds) of video preview" },
        { name: :video_scale,          default: "'min(iw,360)':-2", description: "mp4: video scale (ffmpeg)" },
        { name: :blend_keyframes,      default: 30,                 description: "mp4: blend: # key frames" },
        { name: :blend_pauseframes,    default: 3,                  description: "mp4: blend: # pause frames" },
        { name: :blend_transframes,    default: 5,                  description: "mp4: blend: # transition blend frames" },
        { name: :blend_fps,            default: 15,                 description: "mp4: blend: frame per second" },
        { name: :clips_count,          default: 5,                  description: "mp4: clips: number of clips" },
        { name: :clips_length,         default: 5,                  description: "mp4: clips: length in seconds of each clips" },
      ]
      # add accessors
      DESCRIPTIONS.each do |opt|
        attr_accessor opt[:name]
      end
    end # Options
  end # Preview
end # Aspera
