#!/usr/bin/env ruby
# frozen_string_literal: true

# Tools used in README.erb.md

# get transfer spec parameter description
require 'aspera/fasp/parameters'
require 'aspera/cli/info'
require 'yaml'
require 'erb'

# set values used in ERB
# just command name
def cmd;Aspera::Cli::PROGRAM_NAME;end

# used in text with formatting of command
def tool;'`' + cmd + '`';end

# prefix for env vars
def evp;cmd.upcase + '_';end

# just the name for "option preset"
def opprst;'option preset';end

# name with link
def prst;'[' + opprst + '](#lprt)';end

# name with link (plural)
def prsts;'[' + opprst + 's](#lprt)';end

# Transfer spec name with link
def trspec;'[*transfer-spec*](#transferspec)';end

# in title
def prstt;opprst.capitalize;end

def gemspec;Gem::Specification.load(@env[:GEMSPEC]) || raise("error loading #{@env[:GEMSPEC]}");end

def geminstadd;/\.[^0-9]/.match?(gemspec.version.to_s) ? ' --pre' : '';end

# transfer spec description generation
def spec_table
  r = []
  r << '<table><tr><th>Field</th><th>Type</th>'
  Aspera::Fasp::Parameters::SUPPORTED_AGENTS_SHORT.each do |c|
    r << '<th>' << c.to_s.upcase << '</th>'
  end
  r << '<th>Description</th></tr>'
  Aspera::Fasp::Parameters.man_table.each do |p|
    p[:description] += (p[:description].empty? ? '' : "\n") + '(' + p[:cli] + ')' unless p[:cli].to_s.empty?
    p.delete(:cli)
    p.keys.each{|c|p[c] = '&nbsp;' if p[c].to_s.empty?}
    p[:description] = p[:description].gsub("\n",'<br/>')
    p[:type] = p[:type].gsub(',','<br/>')
    r << '<tr><td>' << p[:name] << '</td><td>' << p[:type] << '</td>'
    Aspera::Fasp::Parameters::SUPPORTED_AGENTS_SHORT.each do |c|
      r << '<td>' << p[c] << '</td>'
    end
    r << '<td>' << p[:description] << '</td></tr>'
  end
  r << '</table>'
  return r.join
end

# @return the minimum ruby version from gemspec
def ruby_minimum_version
  requirement = gemspec.required_ruby_version.to_s
  raise "gemspec version must be generic, i.e. like '>= x.y', not specific like '#{requirement}'" if gemspec.required_ruby_version.specific?
  return requirement.gsub(/^[^0-9]*/,'')
end

def ruby_version
  message = "version: #{gemspec.required_ruby_version}"
  unless ruby_minimum_version.eql?(Aspera::Cli::RUBY_FUTURE_MINIMUM_VERSION)
    message += ". Deprecation notice: the minimum will be #{Aspera::Cli::RUBY_FUTURE_MINIMUM_VERSION} in a future version"
  end
  return message
end

def generate_help(varname)
  raise "missing #{varname}" unless @env.has_key?(varname)
  return %x(#{@env[varname]} -h 2>&1)
end

def include_usage
  generate_help(:ASCLI).gsub(%r{(current=).*(/.aspera/)},'\1/usershome\2')
end

def include_asession
  generate_help(:ASESSION)
end

# various replacements from commands in test makefile
REPLACEMENTS = {
  '@preset:misc.'          => 'my_',
  'LOCAL_SAMPLE_FILENAME'  => 'testfile.bin',
  'LOCAL_SAMPLE_FILEPATH'  => 'testfile.bin',
  'HSTS_UPLOADED_FILE'     => 'testfile.bin',
  'HSTS_FOLDER_UPLOAD'     => 'folder_1',
  'Test Package TIMESTAMP' => 'Important files delivery',
  'AOC_EXTERNAL_EMAIL'     => 'external.user@example.com',
  'EMAIL_ADDR'             => 'internal.user@example.com',
  'CF_'                    => '',
  '$@'                     => 'test'
}.freeze

def include_commands
  commands = []
  File.open(@env[:TEST_MAKEFILE]) do |f|
    f.each_line do |line|
      next unless line.include?('$(EXE_MAN')
      line = line.chomp()
      # replace command name
      line = line.gsub(/^.*\$\(EXE_MAN.?\)/,cmd)
      # replace makefile macros
      line = line.gsub(/\$\(([^)]*)\)/,'\1')
      # remove multi command mark
      line = line.gsub(/\)?&&\\$/,'')
      # remove redirection
      line = line.gsub(/ [>|] .*$/,'')
      # remove folder macro
      line = line.gsub(/DIR_[A-Z]+/,'')
      # replace shell vars in JSON
      line = line.gsub(/'"\$\$\{([a-z_0-9]+)\}"'/,'my_\1')
      # replace shell vars in shell
      line = line.gsub(/\$\$\{([a-z_0-9]+)\}/,'my_\1')
      # de-dup dollar in regex
      line = line.gsub('$$','$')
      REPLACEMENTS.each_pair{|k,v|line = line.gsub(k,v)}
      commands.push(line)
    end
  end
  return commands.sort.uniq.join("\n")
end

KEPT_GLOBAL_SECTIONS=%w[config default].freeze

# main function to generate config file with secrets
def generate_generic_conf
  n = {}
  local_config = ARGV.first
  raise 'missing argument: local config file' if local_config.nil?
  YAML.load_file(local_config).each do |k,v|
    n[k] = KEPT_GLOBAL_SECTIONS.include?(k) ? v : v.keys.each_with_object({}){|i,m|m[i] = 'your value here'}
  end
  puts(n.to_yaml)
end

# main function to generate README.md
def generate_doc
  @env = {}
  %i[TEMPLATE ASCLI ASESSION TEST_MAKEFILE GEMSPEC].each do |var|
    @env[var] = ARGV.shift
    raise "Missing arg: #{var}" if @env[var].nil?
  end
  puts ERB.new(File.read(@env[:TEMPLATE])).result(Kernel.binding)
end
