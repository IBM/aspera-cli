# frozen_string_literal: true

require 'English'
require 'aspera/cli/plugin'
require 'aspera/sync'
require 'aspera/log'
require 'open3'

module Aspera
  module Cli
    module Plugins
      # list and download connect client versions, select FASP implementation
      class Sync < Plugin
        def initialize(env)
          super(env)
          options.add_opt_simple(:parameters,'extended value for session set definition')
          options.add_opt_simple(:session_name,'name of session to use for admin commands, by default first one')
          options.parse_options!
        end

        ACTIONS = %i[start admin].freeze

        def execute_action
          command = options.get_next_command(ACTIONS)
          case command
          when :start
            env_args = Aspera::Sync.new(options.get_option(:parameters,is_type: :mandatory)).compute_args
            async_bin = 'async'
            Log.log.debug("execute: #{env_args[:env].map{|k,v| "#{k}=\"#{v}\""}.join(' ')} \"#{async_bin}\" \"#{env_args[:args].join('" "')}\"")
            res = system(env_args[:env],[async_bin,async_bin],*env_args[:args])
            Log.log.debug("result=#{res}")
            case res
            when true then return Main.result_success
            when false then raise "failed: #{$CHILD_STATUS}"
            when nil then return Main.result_status("not started: #{$CHILD_STATUS}")
            else raise 'internal error: unspecified case'
            end
          when :admin
            p = options.get_option(:parameters,is_type: :mandatory)
            n = options.get_option(:session_name)
            cmdline = ['asyncadmin','--quiet']
            session = n.nil? ? p['sessions'].first : p['sessions'].find{|s|s['name'].eql?(n)}
            cmdline.push('--name=' + session['name'])
            if session.has_key?('local_db_dir')
              cmdline.push('--local-db-dir=' + session['local_db_dir'])
            else
              cmdline.push('--local-dir=' + session['local_dir'])
            end
            command2 = options.get_next_command([:status])
            case command2
            when :status
              stdout, stderr, status = Open3.capture3(*cmdline)
              Log.log.debug("status=#{status}, stderr=#{stderr}")
              items = stdout.split("\n").each_with_object({}){|l,m|i = l.split(/:  */);m[i.first.lstrip] = i.last.lstrip;}
              return {type: :single_object,data: items}
            else raise 'error'
            end # command
          else raise 'error'
          end # command
        end # execute_action
      end # Sync
    end # Plugins
  end # Cli
end # Aspera
