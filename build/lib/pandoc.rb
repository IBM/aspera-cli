# frozen_string_literal: true

require 'pathname'
require 'aspera/environment'
require 'aspera/log'
require_relative 'paths'

PATH_PANDOC_ROOT = ENV.key?('DIR_PANDOC') ? Pathname.new(ENV['DIR_PANDOC']) : Paths::TOP / 'doc' / 'pandoc'
PANDOC_DEPS = [
  'defaults_common.yaml',
  'defaults_pdf.yaml',
  'defaults_html.yaml',
  'break_replace.lua',
  'find_admonition.lua',
  'gfm_admonition.css',
  'gfm_admonition.lua',
  'pdf_after_body.tex',
  'pdf_in_header.tex'
].map{ |f| (PATH_PANDOC_ROOT / f).to_s}.freeze

# Extract pandoc metadata from markdown comment
def extract_metadata_file(md)
  metadata_file = TMP / 'pandoc_meta'
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
    changes = Aspera::Environment.secure_execute('git', 'status', '--porcelain', md.to_s, mode: :capture)
    raise changes unless changes.empty?
    epoch = Aspera::Environment.secure_execute('git', 'log', '-1', '--pretty=format:%cd', '--date=unix', md.to_s, mode: :capture).to_i
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
      'pandoc',
      "--defaults=#{PATH_PANDOC_ROOT / 'defaults_common.yaml'}",
      "--defaults=#{PATH_PANDOC_ROOT / 'defaults_pdf.yaml'}",
      "--variable=date:#{get_change_date(md)}",
      "--metadata-file=#{metadatafile}",
      "--output=#{pdf}",
      md,
      env: {'GFX_DIR'=> PATH_PANDOC_ROOT.to_s}
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
      'pandoc',
      "--defaults=#{PATH_PANDOC_ROOT / 'defaults_common.yaml'}",
      "--defaults=#{PATH_PANDOC_ROOT / 'defaults_html.yaml'}",
      "--output=#{html}",
      md,
      env: {'GFX_DIR'=> PATH_PANDOC_ROOT.to_s}
    )
  end
end
