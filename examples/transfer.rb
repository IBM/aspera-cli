# Example: transfer a file using one of the provided transfer agents
$LOAD_PATH.unshift(File.dirname(__FILE__)+"/../lib")
require 'asperalm/fasp/local'
require 'asperalm/fasp/connect'
require 'asperalm/fasp/node'
require 'asperalm/fasp/listener'
require 'asperalm/fasp/installation'
require 'asperalm/log'
require 'asperalm/rest'
require 'json'
class MyListener < Asperalm::Fasp::Listener
  def event_enhanced(data);STDOUT.puts(JSON.generate(data));STDOUT.flush;end
end
Asperalm::Log.instance.level=:debug
Asperalm::Fasp::Installation.instance.installed_products.each{|p|puts("found: #{p[:name]}")}
Asperalm::Fasp::Installation.instance.activated='Aspera Connect'
fasp_manager=Asperalm::Fasp::Local.instance
#fasp_manager=Asperalm::Fasp::Connect.instance
#fasp_manager=Asperalm::Fasp::Node.instance
#Asperalm::Fasp::Node.instance.node_api=Asperalm::Rest.new()
fasp_manager.add_listener(MyListener.new)
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
