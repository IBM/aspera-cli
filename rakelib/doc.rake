# frozen_string_literal: true

require 'aspera/cli/info'
require 'digest'
require_relative '../build/lib/build_tools'
require_relative '../build/lib/pandoc'
require_relative '../build/lib/doc_helper'
require_relative '../build/lib/test_env'
include BuildTools

PATH_TMP_DOT = Paths::TMP / 'uml.dot'

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

# Declare a PDF build rule
def pdf_rule(pdf, md = nil)
  # pdf = File.expand_path(pdf)
  md ||= pdf.sub(/\.pdf$/, '.md')
  file(pdf => [md] + PANDOC_DEPS) do
    markdown_to_pdf(md: md, pdf: pdf)
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

# Source file that contain constants used to generate doc
CONST_SOURCES = %w[info version manager].map{ |i| Paths::LIB / "aspera/cli/#{i}.rb"}

namespace :doc do
  rule '.pdf' => '.md' do |t|
    pdf_rule(t.name, t.source)
  end

  pdf_rule(Paths::PDF_MANUAL, Paths::MD_MANUAL)

  file Paths::TMPL_CONF_FILE => [Paths::BUILD_TOOLS, Paths::CONF_SIGNATURE] do
    DocHelper.config_to_template(TestEnv.configuration, Paths::TMPL_CONF_FILE)
  end

  file Paths::TSPEC_JSON_SCHEMA => [Paths::TSPEC_YAML_SCHEMA] do
    Aspera::Log.log.info{"Generating: #{Paths::TSPEC_JSON_SCHEMA}"}
    run(Paths::BIN / Aspera::Cli::Info::CMD_NAME, 'config', 'ascp', 'schema', '--format=jsonpp', "--output=#{Paths::TSPEC_JSON_SCHEMA}")
  end

  file Paths::MD_MANUAL => DOC_FILES + [Paths::BUILD_TOOLS, Paths::DOC_HELPER, Paths::TSPEC_YAML_SCHEMA, Paths::ASYNC_YAML_SCHEMA, Paths::GEMSPEC] + CONST_SOURCES do
    Aspera::Environment.force_terminal_c
    DocHelper.new([Paths::MD_MANUAL] + DOC_FILES).generate
  end

  desc 'Generate PDF Manual'
  task pdf: Paths::PDF_MANUAL

  desc 'Generate PDF Manual'
  task md: Paths::MD_MANUAL

  desc 'Generate All Docs'
  task build: [Paths::TMPL_CONF_FILE, Paths::TSPEC_JSON_SCHEMA, Paths::MD_MANUAL, Paths::PDF_MANUAL]

  # UML Diagram : requires tools: graphviz and gem xumlidot
  # on mac: `gem install xumlidot pry` and `brew install graphviz`
  file Paths::UML_PNG => PATH_TMP_DOT do
    Aspera::Log.log.info{"Generating: #{Paths::UML_PNG}"}
    run('dot', '-Tpng', PATH_TMP_DOT, out: Paths::UML_PNG.to_s)
  end

  file PATH_TMP_DOT => [] do
    Aspera::Log.log.info{"Generating: #{PATH_TMP_DOT}"}
    require 'xumlidot'
    capture_stdout_to_file(PATH_TMP_DOT) do
      Xumlidot::Loader.new([Paths::LIB.to_s], Xumlidot::Options.parse(%w[--dot --no-composition --usage])).load
    end
  end

  desc 'Generate uml'
  task uml: Paths::UML_PNG
end
