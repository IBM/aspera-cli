# frozen_string_literal: true

require 'aspera/cli/info'

require_relative '../build/lib/pandoc'
require_relative '../build/lib/paths'
require_relative '../build/lib/doc_helper'

# Declare a PDF build rule
def pdf_rule(pdf, md = nil)
  # pdf = File.expand_path(pdf)
  md ||= pdf.sub(/\.pdf$/, '.md')
  file(pdf => [md, *PANDOC_DEPS]) do
    markdown_to_pdf(md: md, pdf: pdf)
  end
end

# ------------------------------------------------------------
# Automatic rule: *.md → *.pdf
# ------------------------------------------------------------
rule '.pdf' => '.md' do |t|
  pdf_rule(t.name, t.source)
end

PATH_PDF_MANUAL = Paths::RELEASE / "Manual-#{Aspera::Cli::Info::CMD_NAME}-#{GEM_VERSION}.pdf"
PATH_MD_MANUAL = Paths::TOP / 'README.md'

TMPL_CONF_FILE_PATH = Paths::DOC / 'test_env.conf'
TSPEC_JSON_SCHEMA = Paths::DOC / 'spec.schema.json'
TSPEC_YAML_SCHEMA = Paths::LIB / 'aspera/transfer/spec.schema.yaml'
ASYNC_YAML_SCHEMA = Paths::LIB / 'aspera/sync/conf.schema.yaml'
PATH_BUILD_TOOLS = Paths::BUILD_LIB / 'build_tools.rb'
pdf_rule(PATH_PDF_MANUAL, PATH_MD_MANUAL)

file(TMPL_CONF_FILE_PATH => [PATH_BUILD_TOOLS, Paths.config_file_path]) do
  DocHelper.config_to_template(Paths.config_file_path, TMPL_CONF_FILE_PATH)
end

file TSPEC_JSON_SCHEMA => [TSPEC_YAML_SCHEMA] do
  Aspera::Log.log.info{"Generating: #{TSPEC_JSON_SCHEMA}"}
  Aspera::Environment.secure_execute(exec: Paths::CLI_CMD.to_s, args: ['config', 'ascp', 'schema', '--format=jsonpp', "--output=#{TSPEC_JSON_SCHEMA}"])
end

DOC_FILES = [
  Paths::DOC / 'README.erb.md',
  Paths::CLI_CMD,
  Paths::BIN / 'asession',
  Paths::TEST_DEFS,
  Paths::GEMSPEC,
  Paths::TOP / 'Gemfile'
]
CONST_SOURCES = %w[info version manager].map{ |i| Paths::LIB / "aspera/cli/#{i}.rb"}

file PATH_MD_MANUAL => DOC_FILES + [PATH_BUILD_TOOLS, TSPEC_YAML_SCHEMA, ASYNC_YAML_SCHEMA, Paths::GEMSPEC] + CONST_SOURCES do
  Aspera::Log.log.info{"Generating: #{PATH_MD_MANUAL}"}
  Aspera::Environment.force_terminal_c
  DocHelper.new([PATH_MD_MANUAL] + DOC_FILES).generate
end

desc 'Generate PDF Manual'
task pdf: PATH_PDF_MANUAL

task doc: [PATH_PDF_MANUAL, TMPL_CONF_FILE_PATH, TSPEC_JSON_SCHEMA, PATH_MD_MANUAL]
