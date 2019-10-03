# Example: transfer a file using one of the provided transfer agents

require 'asperalm/fasp/local'
require 'asperalm/fasp/listener'
require 'asperalm/fasp/installation'
require 'asperalm/log'
require 'asperalm/rest'
require 'json'

##############################################################
# generic initialisation : configuration of FaspManager

# set trace level for sample, set to :debug to see complete list of debug information
Asperalm::Log.instance.level=:debug

# set path to your copy of ascp binary
Asperalm::Fasp::Installation.instance.ascp_path='/Users/laurent/Applications/Aspera Connect.app/Contents/Resources/ascp'
# some required files are generated here (keys, certs)
Asperalm::Fasp::Installation.instance.config_folder = '.'

# another way is to detect installed products and use one of them
#Asperalm::Fasp::Installation.instance.installed_products.each{|p|puts("found: #{p[:name]}")}
#Asperalm::Fasp::Installation.instance.use_ascp_from_product('Aspera Connect')

# get FASP Manager singleton based on above ascp location
fasp_manager=Asperalm::Fasp::Local.instance

# Note that it would also be possible to start transfers using other agents
#require 'asperalm/fasp/connect'
#fasp_manager=Asperalm::Fasp::Connect.instance
#fasp_manager=Asperalm::Fasp::Node.instance
#require 'asperalm/fasp/node'
#Asperalm::Fasp::Node.instance.node_api=Asperalm::Rest.new()

##############################################################
# Optional : register an event listener

# example of event listener that displays events on stdout
class MyListener < Asperalm::Fasp::Listener
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
  'remote_host'     =>'demo.asperasoft.com',
  'remote_user'     =>'asperaweb',
  'remote_password' =>'demoaspera',
  'direction'       =>'receive',
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
node_api=Asperalm::Rest.new({
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

