# Example: transfer a file using one of the provided transfer agents
$LOAD_PATH.unshift(File.dirname(__FILE__)+"/../lib")
require 'asperalm/fasp/local'

#require 'asperalm/fasp/connect'
#require 'asperalm/fasp/node'
require 'asperalm/fasp/listener'
require 'asperalm/fasp/installation'
require 'asperalm/log'
require 'asperalm/rest'
require 'json'

# example of event listener that displays events on stdout
class MyListener < Asperalm::Fasp::Listener
  def event_enhanced(data);STDOUT.puts(JSON.generate(data));STDOUT.flush;end
end

# set trace level
Asperalm::Log.instance.level=:debug

# one way to select "ascp" is to detect installed products
#Asperalm::Fasp::Installation.instance.installed_products.each{|p|puts("found: #{p[:name]}")}
#Asperalm::Fasp::Installation.instance.activated='Aspera Connect'

# another way: provide necessary resource paths
my_project_folder='/Users/laurent/Applications/Aspera Connect.app/Contents/Resources'
my_resources={
  :ascp               => "ascp",
  :ssh_bypass_key_dsa => "asperaweb_id_dsa.openssh",
  :ssh_bypass_key_rsa => "aspera_tokenauth_id_rsa"
}
Asperalm::Fasp::Installation.instance.paths=my_resources.merge(my_resources){|k,o,n|"#{my_project_folder}/#{n}"}
# get fasp manager singleton based on above ascp location
fasp_manager=Asperalm::Fasp::Local.instance

# note that it would also be possible to start transfers using other agents
#fasp_manager=Asperalm::Fasp::Connect.instance
#fasp_manager=Asperalm::Fasp::Node.instance
#Asperalm::Fasp::Node.instance.node_api=Asperalm::Rest.new()

# register the sample listener to display events
fasp_manager.add_listener(MyListener.new)

# first example: transfer by SSH credentials
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

# second example: transfer with node authorization
node_api=Asperalm::Rest.new({
  :base_url       => 'https://eudemo.asperademo.com:9092',
  :auth_type      => :basic,
  :basic_username => 'node_faspex',
  :basic_password => '434e5c01-5b20-4884-bc6b-62370a371cf5'})
destination='/'
# request transfer authorization to node
send_result=node_api.create('files/upload_setup',{ :transfer_requests => [ { :transfer_request => { :paths => [ { :destination => destination } ] } } ] } )[:data]
# we normally have only one transfer spec in list
transfer_spec=send_result['transfer_specs'].first['transfer_spec']
# set list of files to upload
transfer_spec['paths']=[{'source'=>'/Users/laurent/200KB.1'}]
# use ssh bypass key
transfer_spec['authentication']='token'
fasp_manager.start_transfer(transfer_spec)
fasp_manager.wait_for_transfers_completion
