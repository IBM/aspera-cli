# frozen_string_literal: true
# Tools used in README.erb.md

# get transfer spec parameter description
require 'aspera/fasp/parameters'
require 'aspera/cli/info'
require 'yaml'

# check that required env vars exist
def checked_env(varname)
  raise "missing env var #{varname}" unless ENV.has_key?(varname)
  return ENV[varname]
end

def read_file_var(varname)
  raise "missing env var #{varname}" unless ENV.has_key?(varname)
  raise "missing file for #{varname}: #{checked_env(varname)}" unless File.exist?(checked_env(varname))
  return File.read(checked_env(varname))
end

# set values used in ERB
# just command name
def cmd;checked_env('EXENAME');end

# used in text with formatting of command
def tool;'`'+cmd+'`';end

# prefix for env vars
def evp;cmd.upcase+'_';end

# just the name for "option preset"
def opprst;'option preset';end

# name with link
def prst;'['+opprst+'](#lprt)';end

# name with link (plural)
def prsts;'['+opprst+'s](#lprt)';end

# Transfer spec name with link
def trspec;'[*transfer-spec*](#transferspec)';end

# in title
def prstt;opprst.capitalize;end

def gemspec;Gem::Specification.load(checked_env('GEMSPEC')) or raise "error loading #{checked_env('GEMSPEC')}";end

def geminstadd;gemspec.version.to_s.match(/\.[^0-9]/) ? ' --pre' : '';end

# transfer spec description generation
def spec_table
  r=[]
  r<<'<table><tr><th>Field</th><th>Type</th>'
  Aspera::Fasp::Parameters::SUPPORTED_AGENTS_SHORT.each do |c|
    r << '<th>'<<c.to_s.upcase<<'</th>'
  end
  r << '<th>Description</th></tr>'
  Aspera::Fasp::Parameters.man_table.each do |p|
    p[:description] += (p[:description].empty? ? '' : "\n") + '(' + p[:cli] + ')' unless p[:cli].to_s.empty?
    p.delete(:cli)
    p.keys.each{|c|p[c]='&nbsp;' if p[c].to_s.empty?}
    p[:description]=p[:description].gsub("\n",'<br/>')
    p[:type]=p[:type].gsub(',','<br/>')
    r << '<tr><td>'<<p[:name]<<'</td><td>'<<p[:type]<<'</td>'
    Aspera::Fasp::Parameters::SUPPORTED_AGENTS_SHORT.each do |c|
      r << '<td>'<<p[c]<<'</td>'
    end
    r << '<td>'<<p[:description]<<'</td></tr>'
  end
  r << '</table>'
  return r.join
end

def ruby_version
  message="version: #{gemspec.required_ruby_version}"
  unless Aspera::Cli::RUBY_CURRENT_MINIMUM_VERSION.eql?(Aspera::Cli::RUBY_FUTURE_MINIMUM_VERSION)
    message+=". Deprecation notice: the minimum will be #{Aspera::Cli::RUBY_FUTURE_MINIMUM_VERSION} in a future version"
  end
  return message
end

def include_usage
  read_file_var('INCL_USAGE').gsub(%r[(current=).*(/.aspera/)],'\1/usershome\2')
end

def include_asession
  read_file_var('INCL_ASESSION')
end

REPLACEMENTS={
  '@preset:misc.'=>'my_',
  'LOCAL_SAMPLE_FILENAME'=>'testfile.bin',
  'LOCAL_SAMPLE_FILEPATH'=>'testfile.bin',
  'HSTS_FOLDER_UPLOAD'=>'folder_1',
  'HSTS_UPLOADED_FILE'=>'testfile.bin',
  'PKG_TEST_TITLE'=>'Important files delivery',
  'AOC_EXTERNAL_EMAIL'=>'external.user@example.com',
  'EMAIL_ADDR'=>'internal.user@example.com',
  'CF_'=>'',
  '$@'=>'test'
}

def include_commands
  commands=[]
  File.open(checked_env('TEST_MAKEFILE')) do |f|
    f.each_line do |line|
      next unless line.include?('$(EXE_MAN')
      line=line.chomp()
      # replace command name
      line=line.gsub(/^.*\$\(EXE_MAN.?\)/,cmd)
      # remove multi command mark
      line=line.gsub(/&&\\$/,'')
      # remove redirection
      line=line.gsub(/ > .*$/,'')
      # de-dup dollar coming from makefile
      line=line.gsub('$$','$')
      # remove folder macro
      line=line.gsub(/DIR_[A-Z]+/,'')
      # replace shell vars
      line=line.gsub(/\$\{([a-z_]+)\}/,'my_\1')
      # replace makefile macros
      line=line.gsub(/\$\(([^)]*)\)/,'\1')
      # replace any multiple quote combination to double quote
      line=line.gsub(/['"]{2,}/,'"')
      REPLACEMENTS.each_pair{|k,v|line=line.gsub(k,v)}
      commands.push(line)
    end
  end
  return commands.sort.uniq.join("\n")
end

def generic_secrets
  n={}
  c=YAML.load_file(checked_env('TEST_CONF_FILE_PATH')).each do |k,v|
    n[k]=["config","default"].include?(k) ? v : v.keys.each_with_object({}){|i,m|m[i]='your value here'}
  end
  puts(n.to_yaml)
end