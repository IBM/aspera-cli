#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.join(File.dirname(File.dirname(File.realpath(__FILE__))), 'lib'))
require 'aspera/ascp/installation'
require 'aspera/cli/transfer_progress'
Aspera::RestParameters.instance.progress_bar = Aspera::Cli::TransferProgress.new
# Retrieve `transfer.proto` from the web
Aspera::Ascp::Installation.instance.install_sdk(folder: ARGV.first, backup: false, with_exe: false) {|name| name.end_with?('.proto') ? '/' : nil }
