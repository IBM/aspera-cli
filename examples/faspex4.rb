#!/usr/bin/env ruby
# find Faspex API here: https://developer.ibm.com/apis/catalog/?search=faspex
# this example makes use of class Aspera::Rest for REST calls, alternatively class RestClient of gem rest-client could be used
# this example makes use of class Aspera::Fasp::AgentDirect for transfers, alternatively the official "Transfer SDK" could be used
# Aspera SDK can be downloaded with: `ascli conf ascp install` , it installs in $HOME/.aspera/ascli/sdk
require 'aspera/rest'
require 'aspera/log'
require 'aspera/fasp/agent_direct'

tmpdir=ENV['tmp']||Dir.tmpdir || '.'

# Set high log level for the example, decrease to :warn usually
Aspera::Log.instance.level=:debug

# Set folder where SDK is installed (mandatory)
# (if ascp is not there, the lib will try to find in usual locations)
# (if data files are not there, they will be created)
Aspera::Fasp::Installation.instance.folder = tmpdir

if ! ARGV.length.eql?(3)
  Aspera::Log.log.error("Wrong number of args: #{ARGV.length}")
  Aspera::Log.log.error("Usage: #{$0} <faspex URL> <faspex username> <faspex password>")
  Aspera::Log.log.error("Example: #{$0} https://faspex.com/aspera/faspex john p@sSw0rd")
  Process.exit(1)
end

faspex_url=ARGV[0] # typically: https://faspex.example.com/aspera/faspex
faspex_user=ARGV[1]
faspex_pass=ARGV[2]

# comment out this if certificate is valid, keep line to ignore certificate
Aspera::Rest.insecure=true

# 1: Faspex 4 API v3
#---------------

# create REST API object
api_v3=Aspera::Rest.new({
  :base_url => faspex_url,
  :auth     => {
  :type     => :basic,
  :username => faspex_user,
  :password => faspex_pass
  }})

# very simple api call
api_v3.read('me')

# 2: send a package
#---------------

# create a sample file to send
file_to_send=File.join(tmpdir,'myfile.bin')
File.open(file_to_send, "w") {|f| f.write("sample data") }
# package creation parameters
package_create_params={'delivery'=>{'title'=>'test package','recipients'=>['aspera.user1@gmail.com'],'sources'=>[{'paths'=>[file_to_send]}]}}
pkg_created=api_v3.create('send',package_create_params)[:data]
# get transfer specification (normally: only one)
transfer_spec=pkg_created['xfer_sessions'].first
# set paths of files to send
transfer_spec['paths']=[{'source'=>file_to_send}]
# get the local agent (i.e. ascp)
transfer_client=Aspera::Fasp::AgentDirect.new
# disable ascp output on stdout (optional)
transfer_client.quiet=true
# start transfer (asynchronous)
job_id=transfer_client.start_transfer(transfer_spec)
# wait for all transfer completion (for the example)
result=transfer_client.wait_for_transfers_completion
#  notify of any transfer error
result.select{|i|!i.eql?(:success)}.each do |e|
  Aspera::Log.log.error("A transfer error occured: #{e.message}")
end

# 3: Faspex 4 API v4
#---------------
api_v4=Aspera::Rest.new({
  :base_url  => faspex_url+'/api',
  :auth      => {
  :type      => :oauth2,
  :base_url  => faspex_url+'/auth/oauth2',
  :grant     => :header_userpass,
  :user_name => faspex_user,
  :user_pass => faspex_pass,
  :scope     => 'admin'
  }})

# Use it. Note that Faspex 4 API v4 is totally different from Faspex 4 v3 APIs, see ref on line 2
Aspera::Log.dump('users',api_v4.read('users')[:data])
