# frozen_string_literal: true

require 'aspera/cli/info'
require 'digest'
require_relative '../build/lib/build_tools'
require_relative '../build/lib/pandoc'
require_relative '../build/lib/doc_helper'
require_relative '../build/lib/test_env'
include BuildTools

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

PATH_MD_MANUAL = Paths::TOP / 'README.md'
PATH_TMPL_CONF_FILE = Paths::DOC / 'test_env.conf'
TSPEC_JSON_SCHEMA = Paths::DOC / 'spec.schema.json'
TSPEC_YAML_SCHEMA = Paths::LIB / 'aspera/transfer/spec.schema.yaml'
ASYNC_YAML_SCHEMA = Paths::LIB / 'aspera/sync/conf.schema.yaml'
PATH_BUILD_TOOLS = Paths::BUILD_LIB / 'build_tools.rb'
PATH_DOC_HELPER = Paths::BUILD_LIB / 'doc_helper.rb'

# Generated PATH_MD_MANUAL uses these files
DOC_FILES = [
  Paths::DOC / 'README.erb.md',
  Paths::BIN / Aspera::Cli::Info::CMD_NAME,
  Paths::BIN / 'asession',
  Paths::TEST_DEFS,
  Paths::GEMSPEC,
  Paths::GEMFILE
]
CONST_SOURCES = %w[info version manager].map{ |i| Paths::LIB / "aspera/cli/#{i}.rb"}
# UML Diagram : requires tools: graphviz and gem xumlidot
# on mac: `gem install xumlidot pry` and `brew install graphviz`
PATH_UML_PNG = Paths::DOC / 'uml.png'
PATH_TMP_DOT = Paths::TMP / 'uml.dot'

namespace :doc do
  rule '.pdf' => '.md' do |t|
    pdf_rule(t.name, t.source)
  end

  pdf_rule(Paths::PDF_MANUAL, PATH_MD_MANUAL)

  file PATH_TMPL_CONF_FILE => [PATH_BUILD_TOOLS, Paths::CONF_SIGNATURE] do
    DocHelper.config_to_template(TestEnv.configuration, PATH_TMPL_CONF_FILE)
  end

  file TSPEC_JSON_SCHEMA => [TSPEC_YAML_SCHEMA] do
    Aspera::Log.log.info{"Generating: #{TSPEC_JSON_SCHEMA}"}
    run(Paths::BIN / Aspera::Cli::Info::CMD_NAME, 'config', 'ascp', 'schema', '--format=jsonpp', "--output=#{TSPEC_JSON_SCHEMA}")
  end

  file PATH_MD_MANUAL => DOC_FILES + [PATH_BUILD_TOOLS, PATH_DOC_HELPER, TSPEC_YAML_SCHEMA, ASYNC_YAML_SCHEMA, Paths::GEMSPEC] + CONST_SOURCES do
    Aspera::Log.log.info{"Generating: #{PATH_MD_MANUAL}"}
    Aspera::Environment.force_terminal_c
    DocHelper.new([PATH_MD_MANUAL] + DOC_FILES).generate
  end

  desc 'Generate PDF Manual'
  task pdf: Paths::PDF_MANUAL

  desc 'Generate All Docs'
  task build: [PATH_TMPL_CONF_FILE, TSPEC_JSON_SCHEMA, PATH_MD_MANUAL, Paths::PDF_MANUAL]

  file PATH_UML_PNG => PATH_TMP_DOT do
    Aspera::Log.log.info{"Generating: #{PATH_UML_PNG}"}
    run('dot', '-Tpng', PATH_TMP_DOT, out: PATH_UML_PNG.to_s)
  end

  file PATH_TMP_DOT => [] do
    Aspera::Log.log.info{"Generating: #{PATH_TMP_DOT}"}
    require 'xumlidot'
    capture_stdout_to_file(PATH_TMP_DOT) do
      Xumlidot::Loader.new([Paths::LIB.to_s], Xumlidot::Options.parse(%w[--dot --no-composition --usage])).load
    end
  end

  desc 'Generate uml'
  task uml: PATH_UML_PNG
end
