# frozen_string_literal: true

require_relative '../build/lib/build_tools'
include BuildTools

DIR_MKDOC = Paths::DOC / 'mkdoc'
DIR_MKDOCS = Paths::DOC / 'mkdoc' / 'docs'
VENV_DIR = Paths::TMP / '.venv_mkdocs'
VENV_FLAG = VENV_DIR / 'bin/activate'

def run_venv(venv, *args)
  nenwenv = {
    'PATH'        => [venv / 'bin', ENV['PATH']].map(&:to_s).join(':'),
    'VIRTUAL_ENV' => venv.to_s
  }
  run(*args, env: nenwenv)
end

# clean   : Remove any temporary products.
CLEAN.push(DIR_MKDOCS.to_s)
# clobber : Remove any generated file.
CLOBBER.push(VENV_DIR.to_s)

namespace :doc do
  file VENV_FLAG => [] do
    VENV_DIR.mkdir
    run('python3', '-m', 'venv', VENV_DIR.to_s)
    run_venv(VENV_DIR, 'python3', '-m', 'pip', 'install', '-r', 'requirements.txt')
  end

  desc 'ok'
  task mkdocs: [VENV_FLAG] do
    DIR_MKDOCS.mkdir
    File.cp(TOP / 'README.md', DIR_MKDOCS / 'index.md')
    run_venv(VENV_DIR, 'serve')
  end
end
