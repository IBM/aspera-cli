# frozen_string_literal: true

require 'pathname'
require 'aspera/environment'
require 'aspera/log'
require_relative 'paths'

PATH_PANDOC_ROOT = ENV.key?('DIR_PANDOC') ? Pathname.new(ENV['DIR_PANDOC']) : Paths::TOP / 'doc' / 'pandoc'
PATH_DEF_COMMON = PATH_PANDOC_ROOT / 'defaults_common.yaml'
PATH_DEF_PDF = PATH_PANDOC_ROOT / 'defaults_pdf.yaml'
PATH_DEF_HTML = PATH_PANDOC_ROOT / 'defaults_html.yaml'
PANDOC_DEPS = [
  PATH_DEF_COMMON,
  PATH_DEF_PDF,
  PATH_DEF_HTML,
  PATH_PANDOC_ROOT / 'break_replace.lua',
  PATH_PANDOC_ROOT / 'find_admonition.lua',
  PATH_PANDOC_ROOT / 'gfm_admonition.css',
  PATH_PANDOC_ROOT / 'gfm_admonition.lua',
  PATH_PANDOC_ROOT / 'pdf_after_body.tex',
  PATH_PANDOC_ROOT / 'pdf_in_header.tex'
  #  PATH_PANDOC_ROOT / 'pandoc.rb'
].map(&:to_s)

# Extract pandoc metadata from markdown comment
def extract_metadata_file(md)
  metadata_file = "#{md}.pandoc_meta"
  inside = false
  File.open(metadata_file, 'w') do |out|
    File.foreach(md.to_s) do |line|
      if !inside
        inside = true if line.include?('PANDOC_META_BEGIN')
        next
      end
      break if line.include?('PANDOC_META_END')
      out.write(line)
    end
  end
  metadata_file
end

# Get latest git change date, or else just the file's modification date
def get_change_date(md)
  begin
    changes = Aspera::Environment.secure_capture(exec: 'git', args: ['status', '--porcelain', md.to_s])
    raise changes unless changes.empty?
    epoch = Aspera::Environment.secure_capture(exec: 'git', args: ['log', '-1', '--pretty=format:%cd', '--date=unix', md.to_s]).to_i
    Time.at(epoch)
  rescue
    Time.now
  end.strftime('%Y/%m/%d')
end

# Generate PDF from Markdown using pandoc template
def markdown_to_pdf(md:, pdf:)
  Aspera::Log.log.info{"Generating: #{pdf}"}
  pdf = File.expand_path(pdf)
  Dir.chdir(File.dirname(md)) do
    md = File.basename(md)
    metadatafile = extract_metadata_file(md)
    Aspera::Environment.secure_execute(
      env: {'GFX_DIR'=> PATH_PANDOC_ROOT.to_s},
      exec: 'pandoc',
      args: [
        "--defaults=#{PATH_DEF_COMMON}",
        "--defaults=#{PATH_DEF_PDF}",
        "--variable=date:#{get_change_date(md)}",
        "--metadata-file=#{metadatafile}",
        "--output=#{pdf}",
        md
      ]
    )
    File.delete(metadatafile)
  end
end

# Generate HTML from Markdown using pandoc template
def markdown_to_html(md:, html:)
  File.expand_path(html)
  Dir.chdir(File.dirname(md)) do
    md = File.basename(md)
    Aspera::Environment.secure_execute(
      env: {'GFX_DIR'=> PATH_PANDOC_ROOT.to_s},
      exec: 'pandoc',
      args: [
        "--defaults=#{PATH_DEF_COMMON}",
        "--defaults=#{PATH_DEF_HTML}",
        "--output=#{html}",
        md
      ]
    )
  end
end
