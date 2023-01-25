# frozen_string_literal: true

require 'English'
require 'aspera/cli/plugin'
require 'aspera/sync'
require 'aspera/log'
require 'open3'

module Aspera
  module Cli
    module Plugins
      # Execute Aspera Sync
      class Sync < Plugin
        ASYNC_EXECUTABLE = 'async'
        ASYNC_ADMIN_EXECUTABLE = 'asyncadmin'
        def initialize(env)
          super(env)
          options.add_opt_simple(:parameters, 'Extended value for session set definition')
          options.add_opt_simple(:session_name, 'Name of session to use for admin commands. default: first in parameters')
          options.parse_options!
        end

        ACTIONS = %i[start admin].freeze

        def execute_action
          command = options.get_next_command(ACTIONS)
          case command
          when :start
            env_args = Aspera::Sync.new(options.get_option(:parameters, is_type: :mandatory)).compute_args
            Log.log.debug{"execute: #{env_args[:env].map{|k, v| "#{k}=\"#{v}\""}.join(' ')} \"#{ASYNC_EXECUTABLE}\" \"#{env_args[:args].join('" "')}\""}
            res = system(env_args[:env], [ASYNC_EXECUTABLE, ASYNC_EXECUTABLE], *env_args[:args])
            Log.log.debug{"result=#{res}"}
            case res
            when true then return Main.result_success
            when false then raise "failed: #{$CHILD_STATUS}"
            when nil then return Main.result_status("not started: #{$CHILD_STATUS}")
            else raise 'internal error: unspecified case'
            end
          when :admin
            p = options.get_option(:parameters, is_type: :mandatory)
            n = options.get_option(:session_name)
            cmdline = [ASYNC_ADMIN_EXECUTABLE, '--quiet']
            session = n.nil? ? p['sessions'].first : p['sessions'].find{|s|s['name'].eql?(n)}
            raise 'Session not found' if session.nil?
            raise 'Missing session name' if session['name'].nil?
            cmdline.push('--name=' + session['name'])
            if session.key?('local_db_dir')
              cmdline.push('--local-db-dir=' + session['local_db_dir'])
            elsif session.key?('local_dir')
              cmdline.push('--local-dir=' + session['local_dir'])
            else
              raise 'Missing either local_db_dir or local_dir'
            end
            command2 = options.get_next_command([:status])
            case command2
            when :status
              stdout, stderr, status = Open3.capture3(*cmdline)
              Log.log.debug{"status=#{status}, stderr=#{stderr}"}
              raise "Sync failed: #{status.exitstatus} : #{stderr}" unless status.success?
              items = stdout.split("\n").each_with_object({}){|l, m|i = l.split(/:  */); m[i.first.lstrip] = i.last.lstrip} # rubocop:disable Style/Semicolon
              return {type: :single_object, data: items}
            else raise 'error'
            end # command
          else raise 'error'
          end # command
        end # execute_action
      end # Sync
    end # Plugins
  end # Cli
end # Aspera
