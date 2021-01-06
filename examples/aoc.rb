#!/usr/bin/env ruby
require 'aspera/aoc'
require 'aspera/log'

Aspera::Log.instance.level=:debug

aocapi=Aspera::AoC.new(
url: 'https://myorg.ibmaspera.com',
auth: :jwt,
private_key: File.read('path/to_your_private_key.pem'),
username: 'my.email@example.com',
scope: 'user:all',
subpath: 'api/v1')

self_user_data=aocapi.read('self')

Aspera::Log.dump('self',self_user_data)
