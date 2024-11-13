#!/usr/bin/env ruby
# frozen_string_literal: true

# Retrieve `transfer.proto` from the web
$LOAD_PATH.unshift(File.join(File.dirname(File.dirname(File.realpath(__FILE__))), 'lib'))
require 'aspera/ascp/installation'
Aspera::Ascp::Installation.instance.install_sdk(folder: ARGV.first, backup: false, with_exe: false) {|name| '/' if name.end_with?('transfer.proto')}
