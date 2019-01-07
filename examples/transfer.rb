# Example: transfer a file using one of the provided transfer agents
# add include path relative to gem root, not necessary if gem is installed
$LOAD_PATH.unshift(File.dirname(__FILE__)+"/../lib")
require 'asperalm/fasp/local'
require 'asperalm/fasp/listener'
require 'asperalm/fasp/installation'
require 'asperalm/log'
require 'asperalm/rest'
require 'json'

# example of event listener that displays events on stdout
class MyListener < Asperalm::Fasp::Listener
  def event_enhanced(data);STDOUT.puts(JSON.generate(data));STDOUT.flush;end
end

# set trace level for sample
Asperalm::Log.instance.level=:debug

# To use the "local" FASP, one way is to tell paths to mandatory files embedded in your app
# Here we provide the list of files and main folder
my_project_folder='/Users/laurent/Applications/Aspera Connect.app/Contents/Resources'
my_resources={
  :ascp               => 'ascp',
  :ssh_bypass_key_dsa => 'asperaweb_id_dsa.openssh',
  :ssh_bypass_key_rsa => 'aspera_tokenauth_id_rsa'
}
Asperalm::Fasp::Installation.instance.paths=my_resources.merge(my_resources){|k,o,n|"#{my_project_folder}/#{n}"}

# another way is to detect installed products and use one of them
#Asperalm::Fasp::Installation.instance.installed_products.each{|p|puts("found: #{p[:name]}")}
#Asperalm::Fasp::Installation.instance.activated='Aspera Connect'

# get FASP Manager singleton based on above ascp location
fasp_manager=Asperalm::Fasp::Local.instance

# Note that it would also be possible to start transfers using other agents
#require 'asperalm/fasp/connect'
#fasp_manager=Asperalm::Fasp::Connect.instance
#fasp_manager=Asperalm::Fasp::Node.instance
#require 'asperalm/fasp/node'
#Asperalm::Fasp::Node.instance.node_api=Asperalm::Rest.new()

# register the sample listener to display events
fasp_manager.add_listener(MyListener.new)

# first example: download by SSH credentials
transfer_spec={
  'remote_host'     =>'demo.asperasoft.com',
  'remote_user'     =>'asperaweb',
  'remote_password' =>'demoaspera',
  'direction'       =>'receive',
  'destination_root'=>'.',
  'paths'           =>[{'source'=>'aspera-test-dir-tiny/200KB.1'}]
}
fasp_manager.start_transfer(transfer_spec)
fasp_manager.wait_for_transfers_completion

# second example: upload with node authorization
node_api=Asperalm::Rest.new({
  :base_url       => 'https://eudemo.asperademo.com:9092',
  :auth_type      => :basic,
  :basic_username => 'node_aspera',
  :basic_password => 'aspera'})
# my sources (create sample file) and destination folder
sources=['sample_file.txt']
destination='/Upload'
sources.each{|p|File.write(p,"Hello World!")}
# request transfer authorization to node
send_result=node_api.create('files/upload_setup',{ :transfer_requests => [ { :transfer_request => { :paths => [ { :destination => destination } ] } } ] } )[:data]
# we normally have only one transfer spec in list, so just get the first transfer_spec
transfer_spec=send_result['transfer_specs'].first['transfer_spec']
# set list of files to upload
transfer_spec['paths']=sources.map{|p|{'source'=>p}}
# use ssh bypass key
transfer_spec['authentication']='token'
fasp_manager.start_transfer(transfer_spec)
# optional: wait for transfer completion helper function to get events
fasp_manager.wait_for_transfers_completion
