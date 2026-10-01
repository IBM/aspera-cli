#!/usr/bin/env ruby
# frozen_string_literal: true

# Export the tabs of a draw.io file as images: one image per tab, next to the file, named after the tab.
# Make rules using it: build/doc/pandoc/drawio.mak

require 'rexml/document'

USAGE = <<~TEXT
  Usage:
    drawio.rb list <file.drawio> <format>             print the image paths, e.g. images/topology.svg
    drawio.rb export <file.drawio> <image> [options]  export the tab named like the image, in the format of its
                                                      extension; options go to the draw.io CLI, e.g. --scale 2
TEXT

# Link added by draw.io at the end of SVG exports with HTML labels: "Text is not SVG - cannot display".
# Renderers without foreignObject support display it, e.g. librsvg used for the PDF.
SVG_TEXT_WARNING = %r{<switch><g requiredFeatures="[^"]*"/><a [^>]*svg-export-text-problems[^>]*>.*?</switch>}m

# Names of the tabs of a .drawio file, in order
def tab_names(drawio_file)
  REXML::Document.new(File.read(drawio_file)).get_elements('//diagram').map { |diagram| diagram.attributes['name'] }
end

# Path of the draw.io desktop executable
def drawio_bin
  candidates =
    case RUBY_PLATFORM
    when /darwin/ then ['/Applications/draw.io.app/Contents/MacOS/draw.io']
    when /mswin|mingw|cygwin/ then ['C:\Program Files\draw.io\draw.io.exe']
    else []
    end
  candidates += ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).map { |dir| File.join(dir, 'drawio') }
  candidates.find { |path| File.executable?(path) } || abort('draw.io desktop not found')
end

# Print the path of the image of each tab
def list_images(drawio_file, format)
  folder = File.dirname(drawio_file)
  tab_names(drawio_file).each do |name|
    puts(folder.eql?('.') ? "#{name}.#{format}" : File.join(folder, "#{name}.#{format}"))
  end
end

# Export the tab named like the image file
def export_tab(drawio_file, image_file, *drawio_options)
  tab_name = File.basename(image_file, '.*')
  index = tab_names(drawio_file).index(tab_name)
  abort("tab not found: #{tab_name} in #{drawio_file}") if index.nil?
  # Page indexes are 0-based (an index out of range silently selects the last page)
  system(
    drawio_bin, '--export', '--page-index', index.to_s, *drawio_options, '--output', image_file, drawio_file,
    exception: true
  )
  File.write(image_file, File.read(image_file).sub(SVG_TEXT_WARNING, '')) if File.extname(image_file).eql?('.svg')
end

if $PROGRAM_NAME == __FILE__
  command, *args = ARGV
  case command
  when 'list' then args.length.eql?(2) ? list_images(*args) : abort(USAGE)
  when 'export' then args.length >= 2 ? export_tab(*args) : abort(USAGE)
  else abort(USAGE)
  end
end
