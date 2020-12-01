#!/usr/bin/env ruby
# Example: transfer a file using one of the provided transfer agents

require 'aspera/fasp/local'
require 'aspera/fasp/listener'
require 'aspera/fasp/installation'
require 'aspera/log'
require 'aspera/rest'
require 'aspera/rest_errors_aspera'
require 'json'

##############################################################
# generic initialisation : configuration of FaspManager

# set trace level for sample, set to :debug to see complete list of debug information
Aspera::Log.instance.level=:debug

# set path to your copy of ascp binary
Aspera::Fasp::Installation.instance.ascp_path='/Users/laurent/Applications/Aspera Connect.app/Contents/Resources/ascp'
# some required files are generated here (keys, certs)
Aspera::Fasp::Installation.instance.config_folder = '.'

# register aspera REST call error handlers
Aspera::RestErrorsAspera.registerHandlers

# another way is to detect installed products and use one of them
#Aspera::Fasp::Installation.instance.installed_products.each{|p|puts("found: #{p[:name]}")}
#Aspera::Fasp::Installation.instance.use_ascp_from_product('Aspera Connect')

# get FASP Manager singleton based on above ascp location
fasp_manager=Aspera::Fasp::Local.new

# Note that it would also be possible to start transfers using other agents
#require 'aspera/fasp/connect'
#fasp_manager=Aspera::Fasp::Connect.new
#require 'aspera/fasp/node'
#fasp_manager=Aspera::Fasp::Node.new(Aspera::Rest.new(...))

##############################################################
# Optional : register an event listener

# example of event listener that displays events on stdout
class MyListener < Aspera::Fasp::Listener
  # this is the callback called during transfers, here we only display the received information
  # but it could be used to get detailed error information, check "type" field is "ERROR"
  def event_enhanced(data);STDOUT.puts(JSON.generate(data));STDOUT.flush;end
end

# register the sample listener to display events
fasp_manager.add_listener(MyListener.new)

##############################################################
# first example: download by SSH credentials

# manually build teansfer spec
transfer_spec={
  #'remote_host'     =>'demo.asperasoft.com',
  'remote_host'     =>'eudemo.asperademo.com',
  'remote_user'     =>'asperaweb',
  'remote_password' =>'demoaspera',
  'direction'       =>'receive',
  'ssh_port'        =>33001,
  'destination_root'=>'.',
  'paths'           =>[{'source'=>'aspera-test-dir-tiny/200KB.1'}]
}
# start transfer in separate thread
# method returns as soon as transfer thread is created
# it des not wait for completion, or even for session startup
fasp_manager.start_transfer(transfer_spec)

# optional: helper method: wait for completion of transfers
# here we started a single transfer session (no multisession parameter)
# get array of status, one for each session (so, a single value array)
# each status is either :success or "error message"
transfer_result=fasp_manager.wait_for_transfers_completion
STDOUT.puts(JSON.generate(transfer_result))
# get list of errors only
errors=transfer_result.select{|i|!i.eql?(:success)}
# the transfer was not success, as there is at least one error
raise "Error(s) occured: #{errors.join(',')}" if !errors.empty?

##############################################################
# second example: upload with node authorization

# create rest client for Node API
node_api=Aspera::Rest.new({
  :base_url => 'https://eudemo.asperademo.com:9092',
  :auth     => {
  :type     => :basic,
  :username => 'node_asperaweb',
  :password => 'demoaspera'
  }})
# define sample file(s) and destination folder
sources=['sample_file.txt']
destination='/Upload'
# create sample file(s)
sources.each{|p|File.write(p,"Hello World!")}
# request transfer authorization to node for a single transfer (This is a node api v3 call)
send_result=node_api.create('files/upload_setup',{ :transfer_requests => [ { :transfer_request => { :paths => [ { :destination => destination } ] } } ] } )[:data]
# we normally have only one transfer spec in list, so just get the first transfer_spec
transfer_spec=send_result['transfer_specs'].first['transfer_spec']
# add list of files to upload
transfer_spec['paths']=sources.map{|p|{'source'=>p}}
# set authentication type to "token" (will trigger use of bypass SSH key)
transfer_spec['authentication']='token'
# from here : same as example 1
fasp_manager.start_transfer(transfer_spec)
# optional: wait for transfer completion helper function to get events
transfer_result=fasp_manager.wait_for_transfers_completion
errors=transfer_result.select{|i|!i.eql?(:success)}
# the transfer was not success, as there is at least one error
raise "Error(s) occured: #{errors.join(',')}" if !errors.empty?

