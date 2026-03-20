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

# Extract pandoc defaults from markdown comment
def extract_pandoc_defaults_file(md)
  custom_tmp_file = TMP / 'custom_defaults.yaml'
  inside = false
  File.open(custom_tmp_file, 'w') do |out|
    File.foreach(md.to_s) do |line|
      if !inside
        inside = true if line.include?('PANDOC_DEFAULTS_BEGIN')
        next
      end
      break if line.include?('PANDOC_DEFAULTS_END')
      out.write(line)
    end
  end
  custom_tmp_file
end

# Get latest git change date, or else just the file's modification date
def get_change_date(md)
  begin
    changes = run('git', 'status', '--porcelain', md, mode: :capture)
    raise changes unless changes.empty?
    epoch = run('git', 'log', '-1', '--pretty=format:%cd', '--date=unix', md, mode: :capture).to_i
    Time.at(epoch)
  rescue
    Time.now
  end.strftime('%Y/%m/%d')
end

# Generate a LaTeX file with \graphicspath for pandoc to find graphics
def generate_gfx_paths_latex(paths)
  result = TMP / 'pandoc_add.tex'
  # https://latexref.xyz/_005cgraphicspath.html
  result.write("\\usepackage{graphicx}\n\\graphicspath{#{paths.map{ |p| "{#{p}}"}.join('')}}\n")
  result
end

# Generate PDF from Markdown using pandoc templates
def markdown_to_pdf(md:, pdf:)
  log.info{"Generating: #{pdf}"}
  pdf = File.expand_path(pdf)
  # Ensure target folder exists for pandoc
  FileUtils.mkdir_p(File.dirname(pdf))
  # Paths in README.md are relative to its location
  Dir.chdir(File.dirname(md)) do
    md = File.basename(md)
    custom_defaults_file = extract_pandoc_defaults_file(md)
    gfx_paths_latex = generate_gfx_paths_latex([PATH_PANDOC_ROOT])
    run(
      'pandoc',
      "--include-in-header=#{gfx_paths_latex}",
      "--variable=date:#{get_change_date(md)}",
      "--defaults=#{PATH_PANDOC_ROOT / 'defaults_common.yaml'}",
      "--defaults=#{PATH_PANDOC_ROOT / 'defaults_pdf.yaml'}",
      "--defaults=#{custom_defaults_file}",
      "--output=#{pdf}",
      md
    )
    custom_defaults_file.delete
    gfx_paths_latex.delete
  end
end

# Generate HTML from Markdown using pandoc template
def markdown_to_html(md:, html:)
  File.expand_path(html)
  Dir.chdir(File.dirname(md)) do
    md = File.basename(md)
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
    warn(<<~USAGE)
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
      warn('Error: Conversion commands require exactly 3 arguments.')
      print_usage
      exit(1)
    end

    input_file = ARGV[1]
    output_file = ARGV[2]

    # Validate format
    unless %w[pdf html].include?(command)
      warn("Error: Invalid command '#{ARGV[0]}'. Must be 'deps', 'pdf', or 'html'.")
      print_usage
      exit(1)
    end

    # Check if input file exists
    unless File.exist?(input_file)
      warn("Error: Input file '#{input_file}' not found.")
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
    warn("Error during conversion: #{e.message}")
    warn(e.backtrace.join("\n")) if ENV['DEBUG']
    exit(3)
  end
end
