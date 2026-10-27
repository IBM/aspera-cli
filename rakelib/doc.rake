# frozen_string_literal: true

require 'aspera/cli/info'
require 'digest'
require_relative '../build/lib/build_tools'
require_relative '../build/lib/doc_helper'
require_relative '../build/lib/doc_command_checker'
require_relative '../build/lib/test_env'
require_relative '../build/lib/asperaconf'
include BuildTools

PATH_TMP_DOT = Paths::TMP / 'uml.dot'

# gfm2pdf-toolchain: PDF manual, check of internal links, export of draw.io diagrams, see CONTRIBUTING.md
# Folder in env var GFM2PDF_HOME: required by the doc tasks that use it, not by the other tasks (tests, packages)
GFM2PDF_HOME = ENV.fetch('GFM2PDF_HOME', nil)
# Toolchain with themes and options of documents in a comment `<!-- gfm2pdf`
GFM2PDF_VERSION_REQUIRED = '>= 1.0.0.pre, < 2'
if GFM2PDF_HOME
  require File.join(GFM2PDF_HOME, 'lib', 'pandoc')
  require File.join(GFM2PDF_HOME, 'lib', 'drawio')
end

# @return [Module] Gfm2Pdf, once checked: env var GFM2PDF_HOME set, version of the toolchain
def gfm2pdf
  raise 'The environment variable GFM2PDF_HOME is not set: folder of gfm2pdf-toolchain, see CONTRIBUTING.md' if GFM2PDF_HOME.nil?
  Gfm2Pdf.check_version(GFM2PDF_VERSION_REQUIRED)
  Gfm2Pdf
end

# Images of the tabs of the draw.io diagrams of the manual: SVG for the online manual, PDF for the PDF manual
# (draw.io SVG has HTML labels, dropped by Inkscape). They are committed: building the manual does not need draw.io.
DIAGRAM_IMAGES = (GFM2PDF_HOME ? Paths::DOC.glob('*.drawio') : []).to_h do |drawio|
  [drawio, tab_names(drawio).product(%w[svg pdf]).map { |tab, ext| Paths::DOC / "#{tab}.#{ext}" }]
end.freeze

# Update signature file if configuration has changed
if Paths::CONF_SIGNATURE.exist? && TestEnv.configuration.any?
  stored = Paths::CONF_SIGNATURE.read
  current = Digest::SHA1.hexdigest(JSON.generate(TestEnv.configuration))
  if current != stored
    puts current
    puts stored
    Aspera::Log.log.warn("Test configuration has changed, updating signature file: #{Paths::CONF_SIGNATURE}")
    Paths::CONF_SIGNATURE.write(current)
  end
end

def capture_stdout_to_file(pathname)
  raise 'Missing block' unless block_given?
  real_stdout = $stdout
  $stdout = StringIO.new
  yield
  pathname.write($stdout.string)
ensure
  $stdout = real_stdout
end

# Declare a PDF build rule, with the theme of aspera-cli
# Also depends on the files of the toolchain and of the theme, and on the options file of the Markdown file:
# `<md name>.gfm2pdf.yaml`, if any
# @param extra [Array] Additional dependencies, e.g. images
def pdf_rule(pdf, md = nil, extra: [])
  md = Pathname(md || pdf.sub(/\.pdf$/, '.md'))
  toolchain = GFM2PDF_HOME ? Gfm2Pdf.dependencies(Paths::PDF_THEME) + [Gfm2Pdf.options_file(md)].select(&:exist?) : []
  file(pdf => [md] + toolchain + extra) do
    gfm2pdf.markdown_to_pdf(md: md, pdf: pdf, theme: Paths::PDF_THEME)
  end
end

# Generated Paths::MD_MANUAL uses these files
DOC_FILES = [
  Paths::MD_ERB,
  Paths::COMMAND,
  Paths::ASESSION,
  Paths::TEST_DEFS,
  Paths::GEMSPEC,
  Paths::GEMFILE
]

# Source file that contain constants used to generate doc (version, urls)
CONST_SOURCES = %w[info version].map { |i| Paths::LIB / "aspera/cli/#{i}.rb" }

namespace :doc do
  rule '.pdf' => '.md' do |t|
    pdf_rule(t.name, t.source)
  end

  pdf_rule(Paths::PDF_MANUAL, Paths::MD_MANUAL, extra: [Paths::PDF_PREFACE, Paths::MASCOT_SVG] + DIAGRAM_IMAGES.values.flatten.select { |i| i.extname.eql?('.pdf') })

  file Paths::TMPL_CONF_FILE => [Paths::BUILD_TOOLS, Paths::CONF_SIGNATURE] do
    config = TestEnv.configuration
    Aspera.assert(!config.empty?) { 'Need configuration to generate template' }
    DocHelper.config_to_template(config, Paths::TMPL_CONF_FILE)
  end

  file Paths::TSPEC_JSON_SCHEMA => [Paths::TSPEC_YAML_SCHEMA] do
    Aspera::Log.log.info { "Generating: #{Paths::TSPEC_JSON_SCHEMA}" }
    run(Paths::BIN / Aspera::Cli::Info::CMD_NAME, 'config', 'ascp', 'schema', '--format=jsonpp', "--out.file=#{Paths::TSPEC_JSON_SCHEMA}")
  end

  desc 'Generate XSD for aspera.conf'
  task :aspera_conf_xsd do
    ASPERA_CONF_XSD.write(Aspera::Conf::Generator.new(%x{asuserdata -+}).generate)
  end

  file Paths::MD_MANUAL => DOC_FILES + [Paths::BUILD_TOOLS, Paths::DOC_HELPER, Paths::TSPEC_YAML_SCHEMA, Paths::ASYNC_YAML_SCHEMA, Paths::ASYNC_TABLES_YAML_SCHEMA, Paths::GEMSPEC] + CONST_SOURCES do
    Aspera::Environment.force_terminal_c
    DocHelper.new([Paths::MD_MANUAL] + DOC_FILES).generate
  end

  desc 'Check links in manual'
  task :check_links do
    Aspera::Log.log.info { 'Checking links in manual' }
    DocHelper.new([Paths::MD_MANUAL] + DOC_FILES).check_links_manual
  end

  desc 'Check commands and options of examples in manual'
  task :check_commands do
    DocCommandChecker.new(template: Paths::MD_ERB, ascli: Paths::COMMAND).check
  end

  desc 'Check internal links (#anchor) in manual, for GitHub and PDF (requires gfm2pdf-toolchain)'
  task check_anchors: Paths::MD_MANUAL do
    gfm2pdf.check_markdown_anchors(Paths::MD_MANUAL)
  end

  desc 'Generate PDF Manual'
  task pdf: [:check_anchors, Paths::PDF_MANUAL]

  desc 'Generate Markdown Manual'
  task md: [:check_commands, Paths::MD_MANUAL]

  desc 'Generate docs except PDF'
  task prep: [Paths::TMPL_CONF_FILE, Paths::TSPEC_JSON_SCHEMA, Paths::MD_MANUAL]

  desc 'Generate All Docs'
  task build: [:prep, :check_anchors, Paths::PDF_MANUAL]

  # UML Diagram : requires tools: graphviz and gem xumlidot
  # on mac: `gem install xumlidot pry` and `brew install graphviz`
  file Paths::UML_PNG => PATH_TMP_DOT do
    Aspera::Log.log.info { "Generating: #{Paths::UML_PNG}" }
    run('dot', '-Tpng', PATH_TMP_DOT, out: Paths::UML_PNG.to_s)
  end

  file PATH_TMP_DOT => [] do
    Aspera::Log.log.info { "Generating: #{PATH_TMP_DOT}" }
    require 'xumlidot'
    capture_stdout_to_file(PATH_TMP_DOT) do
      Xumlidot::Loader.new([Paths::LIB.to_s], Xumlidot::Options.parse(%w[--dot --no-composition --usage])).load
    end
  end

  # file Paths::MASCOT_PDF => [Paths::MASCOT_SVG] do
  #  Aspera::Log.log.info{"Generating: #{Paths::MASCOT_PDF}"}
  #  run('inkscape', "--export-filename=#{Paths::MASCOT_PDF}", Paths::MASCOT_SVG)
  # end

  desc 'Generate uml'
  task uml: Paths::UML_PNG

  # Not a dependency of the manual, so that building it does not need draw.io desktop
  desc 'Export draw.io diagrams of the manual (requires gfm2pdf-toolchain and draw.io desktop)'
  task :diagrams do
    gfm2pdf
    DIAGRAM_IMAGES.each do |drawio, images|
      images.each do |image|
        next if uptodate?(image.to_s, [drawio.to_s])
        Aspera::Log.log.info { "Generating: #{image}" }
        export_tab(drawio.to_s, image.to_s)
      end
    end
  end
end
