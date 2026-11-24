# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../lib/aspera/cli/info'
require_relative '../../lib/aspera/cli/version'
require 'pathname'

# Path constants for the project layout (build scripts, docs, tests).
# All paths are relative to the repository root.
module Paths
  # Project (repository) root directory.
  TOP = Pathname.new(__dir__).parent.parent
  # Temporary files (not checked in)
  TMP = TOP / 'tmp'
  # Secrets generated for tests (not checked in), see `generated_secret` in tests/test_helpers.rb
  SECRETS = TMP / 'secrets'
  # Executables
  BIN = TOP / 'bin'
  # Ruby sources of the gem
  LIB = TOP / 'lib'
  # Documentation
  DOC = TOP / 'docs'
  # Tests
  TST = TOP / 'tests'
  # Build scripts and resources
  BUILD = TOP / 'build'
  # Release artifacts: gem, PDF manual, packages
  RELEASE = TOP / 'pkg'
  # Theme of gfm2pdf-toolchain: look of the PDF manual
  PDF_THEME = BUILD / 'doc' / 'pdf_theme'
  # Configuration of the online manual (MkDocs)
  MKDOCS = BUILD / 'doc' / 'mkdocs'
  # Source of {BuildTools}
  BUILD_TOOLS = BUILD / 'lib' / 'build_tools.rb'
  # Source of {DocHelper}
  DOC_HELPER = BUILD / 'lib' / 'doc_helper.rb'
  # Source of {DocMarkup}
  DOC_MARKUP = BUILD / 'lib' / 'doc_markup.rb'
  # Source of {MarkdownFormatter}
  MARKDOWN_FORMATTER = BUILD / 'lib' / 'markdown_formatter.rb'
  # Gem specification
  GEMSPEC = TOP / 'aspera-cli.gemspec'
  # Gem dependencies
  GEMFILE = TOP / 'Gemfile'
  # Locked versions of gem dependencies
  GEMFILE_LOCK = TOP / 'Gemfile.lock'
  # PDF manual
  PDF_MANUAL = RELEASE / "Manual-#{Aspera::Cli::Info::CMD_NAME}.pdf"
  # Archive of the gem and its dependencies (offline installation)
  GEM_PACK = RELEASE / 'gempack.zip'
  # Command-line test suite definitions
  TEST_DEFS = TST / 'tests.yml'
  # Test definitions of the plugin bundles: `tests.yml` in the `spec` folder of each bundle (not shipped in the gem)
  BUNDLE_TEST_DEFS_GLOB = 'lib/aspera/plugins/*/spec/tests.yml'
  # Manual section of each plugin bundle: ERB template included in `MD_ERB`
  BUNDLE_MANUAL_GLOB = 'lib/aspera/plugins/*/manual.erb.md'
  # Versions of servers used in tests
  SERVERS_TESTED = TST / 'servers_tested.yaml'
  # Change log
  CHANGELOG_FILE = TOP / 'CHANGELOG.md'
  # Source of the gem version (`VERSION`)
  VERSION_FILE = TOP / 'lib/aspera/cli/version.rb'
  # Template of the container image definition
  DOCKERFILE_TEMPLATE = BUILD / 'container/Dockerfile.tmpl.erb'
  # Version to build, if different from `VERSION` (e.g. beta), see `BuildTools.use_specific_version`
  OVERRIDE_VERSION_FILE = TMP / 'container_beta_version.txt'
  # Resources of the Windows portable package (zip)
  WIN_ZIP_SRC = BUILD / 'windowszip'
  # Resources of the Linux portable package (tgz)
  LINUX_TGZ_SRC = BUILD / 'linuxtgz'
  # Hash of the test configuration: when it changes, the template configuration is regenerated
  CONF_SIGNATURE = DOC / 'conf_signature.txt'
  # Template configuration for tests, generated from the test configuration (secrets hidden)
  TMPL_CONF_FILE = DOC / 'test_env.conf'
  # Transfer spec schema (JSON), generated from `TSPEC_YAML_SCHEMA`
  TSPEC_JSON_SCHEMA = DOC / 'spec.schema.json'
  # Schema of `aspera.conf`, see {Aspera::Conf::Generator}
  ASPERA_CONF_XSD = DOC / 'aspera.conf.xsd'
  # UML diagram of classes
  UML_PNG = DOC / 'uml.png'
  # Mascot image (SVG)
  MASCOT_SVG = DOC / 'art' / 'mascot.svg'
  # Mascot image (PDF, for the PDF manual)
  MASCOT_PDF = DOC / 'art' / 'mascot.pdf'
  # Manual (Markdown), generated from `MD_ERB`
  MD_MANUAL = DOC / 'README.md'
  # Summary for AI assistants, at the root of the gem (and of the documentation web site)
  LLMS_TXT = TOP / 'llms.txt'
  # Agent skill, generated from `LLMS_TXT`: copied by the user in the skills folder of the AI client
  SKILL_MD = TOP / 'skills' / 'ascli' / 'SKILL.md'
  # Template of the manual, see {DocHelper}
  MD_ERB = DOC / 'README.erb.md'
  # Page of the PDF manual after the cover, see docs/README.gfm2pdf.yaml
  PDF_PREFACE = DOC / 'README.preface.tex'
  # Transfer spec schema (YAML)
  TSPEC_YAML_SCHEMA = LIB / 'aspera/transfer/spec.schema.yaml'
  # Async (sync) configuration schema
  ASYNC_YAML_SCHEMA        = LIB / 'aspera/sync/conf.schema.yaml'
  # Schema of the SQLite tables of the async snap database (`snap.db`)
  ASYNC_TABLES_YAML_SCHEMA = LIB / 'aspera/sync/async_tables.yaml'
  # Main executable: `ascli`
  COMMAND = BIN / Aspera::Cli::Info::CMD_NAME
  # Executable: `asession`
  ASESSION = BIN / 'asession'
end
