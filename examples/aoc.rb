#!/usr/bin/env ruby
require 'aspera/aoc'
require 'aspera/log'

Aspera::Log.instance.level=:debug

if ! ARGV.length.eql?(3)
  Aspera::Log.log.error("wrong number of args: #{ARGV.length}")
  Aspera::Log.log.error("Usage: #{$0} <aoc URL> <aoc username> <aoc private key content>")
  Aspera::Log.log.error("Example: #{$0} https://myorg.ibmaspera.com john@example.com $(cat /home/john/my_key.pem)")
  Process.exit(1)
end

aoc_url=ARGV[0]
aoc_user=ARGV[1]
aoc_key_value=ARGV[2]

aocapi=Aspera::AoC.new(
url: aoc_url,
auth: :jwt,
private_key: aoc_key_value,
username: aoc_user,
scope: 'user:all',
subpath: 'api/v1')

self_user_data=aocapi.read('self')

Aspera::Log.dump('self',self_user_data)
