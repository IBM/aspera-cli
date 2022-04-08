#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: transfer a file using one of the provided transfer agents
# location of ascp can be specified with env var "ascp"
# temp folder can be specified with env var "tmp"
require 'aspera/fasp/agent_direct'
require 'aspera/fasp/listener'
require 'aspera/fasp/installation'
require 'aspera/log'
require 'aspera/rest'
require 'aspera/rest_errors_aspera'
require 'json'
require 'tmpdir'

tmpdir = ENV['tmp'] || Dir.tmpdir || '.'

DEMO_CONFIG = [
  'ssh://asperaweb@eudemo.asperademo.com:33001',
  'https://node_asperaweb@eudemo.asperademo.com:9092',
  'demoaspera'
].freeze

##############################################################
# generic initialisation : configuration of FaspManager

# set trace level for sample, set to :debug to see complete list of debug information
Aspera::Log.instance.level = :debug

# register aspera REST call error handlers
Aspera::RestErrorsAspera.register_handlers

# some required files are generated here (keys, certs)
Aspera::Fasp::Installation.instance.folder = tmpdir
# set path to your copy of ascp binary (else, let the system find)
Aspera::Fasp::Installation.instance.ascp_path = ENV['ascp'] if ENV.has_key?('ascp')
# another way is to detect installed products and use one of them
#Aspera::Fasp::Installation.instance.installed_products.each{|p|puts("found: #{p[:name]}")}
#Aspera::Fasp::Installation.instance.use_ascp_from_product('Aspera Connect')
# or install:
#

# get FASP Manager singleton based on above ascp location
fasp_manager = Aspera::Fasp::AgentDirect.new

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
  def event_enhanced(data);$stdout.puts(JSON.generate(data));$stdout.flush;end
end

# register the sample listener to display events
fasp_manager.add_listener(MyListener.new)

##############################################################
# first example: download by SSH credentials

# manually build teansfer spec
transfer_spec = {
  #'remote_host'     =>'demo.asperasoft.com',
  'remote_host'      => URI.parse(DEMO_CONFIG[0]).host,
  'ssh_port'         => URI.parse(DEMO_CONFIG[0]).port,
  'remote_user'      => URI.parse(DEMO_CONFIG[0]).user,
  'remote_password'  => DEMO_CONFIG[2],
  'direction'        => 'receive',
  'destination_root' => tmpdir,
  'paths'            => [{'source' => 'aspera-test-dir-tiny/200KB.1'}]
}
# start transfer in separate thread
# method returns as soon as transfer thread is created
# it des not wait for completion, or even for session startup
fasp_manager.start_transfer(transfer_spec)

# optional: helper method: wait for completion of transfers
# here we started a single transfer session (no multisession parameter)
# get array of status, one for each session (so, a single value array)
# each status is either :success or "error message"
transfer_result = fasp_manager.wait_for_transfers_completion
$stdout.puts(JSON.generate(transfer_result))
# get list of errors only
errors = transfer_result.reject{|i|i.eql?(:success)}
# the transfer was not success, as there is at least one error
raise "Error(s) occured: #{errors.join(',')}" if !errors.empty?

##############################################################
# second example: upload with node authorization

# create rest client for Node API on a public demo system, using public demo credentials
node_api = Aspera::Rest.new({
  base_url: DEMO_CONFIG[1],
  auth:     {
    type:     :basic,
    username: URI.parse(DEMO_CONFIG[1]).user,
    password: DEMO_CONFIG[2]
  }})
# define sample file(s) and destination folder
sources = ["#{tmpdir}/sample_file.txt"]
destination = '/Upload'
# create sample file(s)
sources.each{|p|File.write(p,'Hello World!')}
# request transfer authorization to node for a single transfer (This is a node api v3 call)
send_result = node_api.create('files/upload_setup',{ transfer_requests: [{ transfer_request: { paths: [{ destination: destination }] } }] })[:data]
# we normally have only one transfer spec in list, so just get the first transfer_spec
transfer_spec = send_result['transfer_specs'].first['transfer_spec']
# add list of files to upload
transfer_spec['paths'] = sources.map{|p|{'source' => p}}
# set authentication type to "token" (will trigger use of bypass SSH key)
transfer_spec['authentication'] = 'token'
# from here : same as example 1
fasp_manager.start_transfer(transfer_spec)
# optional: wait for transfer completion helper function to get events
transfer_result = fasp_manager.wait_for_transfers_completion
errors = transfer_result.reject{|i|i.eql?(:success)}
# the transfer was not success, as there is at least one error
raise "Error(s) occured: #{errors.join(',')}" if !errors.empty?
