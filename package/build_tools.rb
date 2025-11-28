# frozen_string_literal: true

require 'bundler'
require_relative '../package/folders'

module BuildTools
  # @param gemfile [String] Path to gem file
  # @param group_name_sym [Symbol] Group name
  def gems_in_group(gemfile, group_name_sym)
    Bundler::Definition.build(gemfile, "#{gemfile}.lock", nil).dependencies.filter_map do |dep|
      next unless dep.groups.include?(group_name_sym)
      "#{dep.name}:#{dep.requirement.to_s.delete(' ')}"
    end
  end

  # Execute the command line (not in shell)
  def run(*args, **kwargs)
    args = args.map(&:to_s)
    puts(args.join(' '))
    Aspera::Environment.secure_execute(exec: args.shift, args: args, exception: true, **kwargs)
  end

  def download_proto_file
    require 'aspera/ascp/installation'
    require 'aspera/cli/transfer_progress'
    tmp_proto_folder = ARGV.first
    Aspera::RestParameters.instance.progress_bar = Aspera::Cli::TransferProgress.new
    # Retrieve `transfer.proto` from the web
    Aspera::Ascp::Installation.instance.install_sdk(folder: tmp_proto_folder, backup: false, with_exe: false){ |name| name.end_with?('.proto') ? '/' : nil}
  end
  module_function :gems_in_group, :run, :download_proto_file
end
