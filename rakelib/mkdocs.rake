# frozen_string_literal: true

require 'fileutils'

require_relative '../build/lib/build_tools'
include BuildTools

PATH_TMP_MKDOCS = Paths::TMP / 'mkdocs'
VENV_DIR = Paths::TMP / '.venv_mkdocs'
VENV_FLAG = VENV_DIR / 'bin/activate'

def run_venv(*args)
  nenwenv = {
    'PATH'        => [VENV_DIR / 'bin', ENV['PATH']].map(&:to_s).join(':'),
    'VIRTUAL_ENV' => VENV_DIR.to_s
  }
  run(*args, env: nenwenv)
end

namespace :doc do
  file VENV_FLAG => [] do
    VENV_DIR.mkdir
    run('python3', '-m', 'venv', VENV_DIR.to_s)
    run_venv('python3', '-m', 'pip', 'install', '-r', Paths::MKDOCS / 'requirements.txt')
  end

  desc 'ok'
  task mkdocs: [VENV_FLAG] do
    path_site = PATH_TMP_MKDOCS / 'site'
    path_docs = PATH_TMP_MKDOCS / 'src'
    path_site.mkpath
    path_docs.mkpath
    FileUtils.cp(MD_MANUAL, path_docs / 'index.md')
    config_file = PATH_TMP_MKDOCS / 'mkdocs.yml'
    config = YAML.safe_load((Paths::MKDOCS / 'mkdocs.yml').read)
    config['docs_dir'] = path_docs.to_s
    config_file.write(config.to_yaml)
    run_venv('mkdocs', 'build', '--config-file', config_file, '--site-dir', path_site)
  end
end
