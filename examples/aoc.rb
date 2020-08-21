#!/usr/bin/env ruby
require 'asperalm/on_cloud'
require 'asperalm/log'

Asperalm::Log.instance.level=:debug

aocapi=Asperalm::OnCloud.new(
url: 'https://myorg.ibmaspera.com',
auth: :jwt,
private_key: File.read('path/to_your_private_key.pem'),
username: 'my.email@example.com',
scope: 'user:all',
subpath: 'api/v1')

self_user_data=aocapi.read('self')

Asperalm::Log.dump('self',self_user_data)
