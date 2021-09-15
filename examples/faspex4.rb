#!/usr/bin/env ruby
require 'aspera/rest'
require 'aspera/log'
require 'aspera/fasp/local'

tmpdir=ENV['tmp']||Dir.tmpdir || '.'

# Set high log level for the example
Aspera::Log.instance.level=:debug

# Set folder where SDK is installed
# (if ascp is not there, the lib will try to find in usual locations)
Aspera::Fasp::Installation.instance.folder = tmpdir

if ! ARGV.length.eql?(3)
  Aspera::Log.log.error("wrong number of args: #{ARGV.length}")
  Aspera::Log.log.error("Usage: #{$0} <faspex URL> <faspex username> <faspex password>")
  Aspera::Log.log.error("Example: #{$0} https://faspex.com/aspera/faspex john p@sSw0rd")
  Process.exit(1)
end

faspex_url=ARGV[0]
faspex_user=ARGV[1]
faspex_pass=ARGV[2]

# comment out this if certificate is valid, keep to ignore certificate
Aspera::Rest.insecure=true

# 1: demo API v3
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
transfer_spec['paths']=['source'=>file_to_send]
# get the local agent (i.e. ascp)
client=Aspera::Fasp::Local.new
# disable ascp output on stdout (optional)
client.quiet=true
# start transfer (asynchronous)
job_id=client.start_transfer(transfer_spec)
# wait for all transfer completion (for the example)
result=client.wait_for_transfers_completion
#  notify of any transfer error
result.select{|i|!i.eql?(:success)}.each do |e|
  Aspera::Log.log.error("A transfer error occured: #{e.message}")
end

# 3: demo API v4
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

Aspera::Log.dump('users',api_v4.read('users')[:data])
