#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pathname'
require_relative 'paths'
require_relative 'build_tools'

include BuildTools
include Paths

# Path to pandoc root directory
PATH_PANDOC_ROOT = ENV.key?('DIR_PANDOC') ? Pathname.new(ENV['DIR_PANDOC']) : Paths::PANDOC
# List of pandoc dependencies files
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

# Extract pandoc defaults from markdown comment, else return nil
# @param md [Pathname] Path to Markdown file
def extract_pandoc_defaults_file(md)
  inside = false
  lines = []
  File.foreach(md) do |line|
    if !inside
      inside = true if line.include?('PANDOC_DEFAULTS_BEGIN')
      next
    end
    break if line.include?('PANDOC_DEFAULTS_END')
    lines << line
  end
  return if lines.empty?
  custom_tmp_file = TMP / 'custom_defaults.yaml'
  custom_tmp_file.write(lines.join)
  custom_tmp_file
end

# Get latest git change date, or else just the file's modification date
# @param md [Pathname] Path to Markdown file
def get_change_date(md)
  begin
    changes = run('git', 'status', '--porcelain', md, mode: :capture, exception: true).first
    raise changes unless changes.empty?
    change_date = run('git', 'log', '-1', '--pretty=format:%cd', '--date=unix', md, mode: :capture, exception: true).first
    change_date.empty? ? md.mtime : Time.at(change_date.to_i)
  rescue
    md.mtime
  end.strftime('%Y/%m/%d')
end

# Generate a LaTeX file with \graphicspath for pandoc to find graphics
# @param paths [Array<Pathname>] Array of paths to include in graphicspath
# @return [Pathname] Path to generated LaTeX file
def generate_gfx_paths_latex(paths)
  result = TMP / 'pandoc_add.tex'
  # https://latexref.xyz/_005cgraphicspath.html
  result.write("\\usepackage{graphicx}\n\\graphicspath{#{paths.map{ |p| "{#{p}}"}.join('')}}\n")
  result
end

# Check for additional pandoc defaults file and add it to the list
# @param md [Pathname] Path to Markdown file
# @param format [String] Output format ('pdf' or 'html')
# @param additional [Array<Pathname>] Array to append additional defaults file to
def check_add_defaults_file(md, format, additional)
  add_defaults = md.dirname / ".#{md.basename}.#{format}.pandoc.yaml"
  log.info{"checking defaults: #{add_defaults}"}
  return unless add_defaults.exist?
  log.info{"Using default pandoc defaults: #{add_defaults}"}
  additional << add_defaults
end

ATTRS = %i{width height}

# Convert HTML <img> to format expected in pandoc
# @param content [String] HTML content to convert
# @return [String] Converted content with Markdown image syntax
def convert_img_for_pandoc(content)
  content.gsub(%r{<img\s+([^>]*?)/?>}) do
    attrs = Regexp.last_match(1)
    src = attrs[/src=["']([^"']*)["']/, 1]
    alt = attrs[/alt=["']([^"']*)["']/, 1] || ''
    "![#{alt}](#{src})"
  end
end

# Generate PDF from Markdown using pandoc templates
# @param md [Pathname] Path to Markdown file
# @param pdf [Pathname] Path to output PDF file
def markdown_to_pdf(md:, pdf:)
  log.info{"Generating: #{pdf}"}
  pdf = pdf.expand_path
  # Ensure target folder exists for pandoc
  pdf.dirname.mkpath
  # Paths in Markdown file are relative to its location
  Dir.chdir(md.dirname) do
    md = md.basename
    tmp_md = Pathname.new(".tmp.#{md}")
    tmp_md.write(convert_img_for_pandoc(md.read))
    custom_defaults_file = extract_pandoc_defaults_file(md)
    gfx_paths_latex = generate_gfx_paths_latex([PATH_PANDOC_ROOT, '.'])
    defaults = [
      PATH_PANDOC_ROOT / 'defaults_common.yaml',
      PATH_PANDOC_ROOT / 'defaults_pdf.yaml'
    ]
    defaults.push(custom_defaults_file) if custom_defaults_file
    check_add_defaults_file(md, 'pdf', defaults)
    run(
      'pandoc',
      "--include-in-header=#{gfx_paths_latex}",
      "--variable=date:#{get_change_date(md)}",
      *defaults.map{ |f| "--defaults=#{f}"},
      "--output=#{pdf}",
      tmp_md
    )
    # temporary files
    custom_defaults_file&.delete
    gfx_paths_latex.delete
    tmp_md.delete
    FileUtils.rm_rf('svg-inkscape')
  end
end

# Generate HTML from Markdown using pandoc template
# @param md [Pathname] Path to Markdown file
# @param html [Pathname] Path to output HTML file
def markdown_to_html(md:, html:)
  html = html.expand_path
  Dir.chdir(md.dirname) do
    md = md.basename
    run(
      'pandoc',
      "--defaults=#{PATH_PANDOC_ROOT / 'defaults_common.yaml'}",
      "--defaults=#{PATH_PANDOC_ROOT / 'defaults_html.yaml'}",
      "--output=#{html}",
      md,
      env: {'GFX_DIR'=> PATH_PANDOC_ROOT.to_s}
    )
  end
end

# Main execution block when script is run directly
if __FILE__ == $PROGRAM_NAME
  # Print usage information
  def print_usage
    puts(<<~USAGE)
      Usage: #{File.basename($PROGRAM_NAME)} <command> [arguments]

      Commands:
        deps                          List pandoc dependency files
        pdf <input.md> <output.pdf>   Convert Markdown to PDF
        html <input.md> <output.html> Convert Markdown to HTML

      Examples:
        #{File.basename($PROGRAM_NAME)} deps
        #{File.basename($PROGRAM_NAME)} pdf README.md output.pdf
        #{File.basename($PROGRAM_NAME)} html README.md output.html
    USAGE
  end

  # Validate arguments and execute conversion
  begin
    # Check minimum number of arguments
    if ARGV.empty?
      print_usage
      exit(1)
    end

    command = ARGV[0].downcase

    # Handle 'deps' command
    if command == 'deps'
      puts PANDOC_DEPS.join(' ')
      exit(0)
    end

    # Handle conversion commands (pdf, html)
    if ARGV.length != 3
      puts('Error: Conversion commands require exactly 3 arguments.')
      print_usage
      exit(1)
    end

    input_file = Pathname.new(ARGV[1])
    output_file = Pathname.new(ARGV[2])

    # Validate format
    unless %w[pdf html].include?(command)
      puts("Error: Invalid command '#{ARGV[0]}'. Must be 'deps', 'pdf', or 'html'.")
      print_usage
      exit(1)
    end

    # Check if input file exists
    unless input_file.exist?
      puts("Error: Input file '#{input_file}' not found.")
      exit(2)
    end

    # Execute conversion based on format
    case command
    when 'pdf'
      markdown_to_pdf(md: input_file, pdf: output_file)
    when 'html'
      markdown_to_html(md: input_file, html: output_file)
    end

    puts "Successfully converted #{input_file} to #{output_file}"
    exit(0)
  rescue => e
    puts("Error during conversion: #{e.message}")
    puts(e.backtrace.join("\n")) if ENV['DEBUG']
    exit(3)
  end
end
