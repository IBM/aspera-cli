#!/usr/bin/env ruby
require 'asperalm/on_cloud'
require 'asperalm/log'

Asperalm::Log.instance.level=:debug

aocapi=Asperalm::OnCloud.new(
url: 'https://sedemo.ibmaspera.com',
auth: :jwt,
private_key: File.read('/Users/laurent/.aspera/mlia/aspera_on_cloud_key'),
username: 'laurent.martin.aspera@fr.ibm.com',
scope: 'user:all',
subpath: 'api/v1')

self_user_data=aocapi.read('self')

Asperalm::Log.dump("self",self_user_data)
