# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'fileutils'

require_relative '../build/lib/build_tools'
require_relative '../build/lib/doc_site'
include BuildTools

PATH_TMP_MKDOCS = Paths::TMP / 'mkdocs'
VENV_DIR = Paths::TMP / '.venv_mkdocs'
VENV_FLAG = VENV_DIR / 'bin/activate'

def run_venv(*args)
  newenv = {
    'PATH'        => [VENV_DIR / 'bin', ENV['PATH']].join(':'),
    'VIRTUAL_ENV' => VENV_DIR.to_s
  }
  run(*args, env: newenv)
end

namespace :doc do
  file VENV_FLAG => [] do
    VENV_DIR.mkdir
    run('python3', '-m', 'venv', VENV_DIR.to_s)
    run_venv('python3', '-m', 'pip', 'install', '-r', Paths::MKDOCS / 'requirements.txt')
  end

  desc 'Generate the documentation web site (MkDocs): one page per section of the manual, llms.txt at its root'
  task site: [VENV_FLAG, Paths::MD_MANUAL] do
    PATH_TMP_MKDOCS.rmtree
    path_site = PATH_TMP_MKDOCS / 'site'
    path_docs = PATH_TMP_MKDOCS / 'src'
    path_site.mkpath
    path_docs.mkpath
    config = YAML.safe_load((Paths::MKDOCS / 'mkdocs.yml').read)
    site = DocSite.new(
      manual:   Paths::MD_MANUAL,
      llms:     Paths::LLMS_TXT,
      site_url: config['site_url'],
      repo_url: "#{config['repo_url']}/blob/main/#{Paths::MD_MANUAL.dirname.relative_path_from(Paths::TOP)}",
      home:     Paths::TOP / 'README.md',
      home_url: "#{config['repo_url']}/blob/main"
    )
    site.write(path_docs)
    FileUtils.cp_r(Paths::MKDOCS / 'stylesheets', path_docs)
    # Image of link previews (Open Graph), and theme override that declares it
    FileUtils.cp_r(Paths::MKDOCS / 'assets', path_docs)
    FileUtils.cp_r(Paths::MKDOCS / 'overrides', PATH_TMP_MKDOCS)
    config['docs_dir'] = path_docs.to_s
    config['nav'] = site.nav
    config_file = PATH_TMP_MKDOCS / 'mkdocs.yml'
    config_file.write(config.to_yaml)
    run_venv('mkdocs', 'build', '--strict', '--config-file', config_file, '--site-dir', path_site)
    Aspera::Log.log.info { "Site: #{path_site}" }
  end
end
