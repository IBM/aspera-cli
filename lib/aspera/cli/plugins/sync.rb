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
          self.options.add_opt_simple(:parameters,"extended value for session set definition")
          self.options.add_opt_simple(:session_name,"name of session to use for admin commands, by default first one")
          self.options.parse_options!
        end

        ACTIONS=[ :start, :admin ]

        def execute_action
          command=self.options.get_next_command(ACTIONS)
          case command
          when :start
            env_args=Aspera::Sync.new(self.options.get_option(:parameters,:mandatory)).compute_args
            res=system(env_args[:env],['async','async'],*env_args[:args])
            Log.log.debug("result=#{res}")
            case res
            when true; return Main.result_success
            when false; return Main.result_status("failed: #{$?}")
            when nil; return Main.result_status("not started: #{$?}")
            else raise "internal error: unspecified case"
            end
          when :admin
            p=self.options.get_option(:parameters,:mandatory)
            n=self.options.get_option(:session_name,:optional)
            cmdline=['asyncadmin','--quiet']
            if n.nil?
              session=p['sessions'].first
            else
              session=p['sessions'].select{|s|s['name'].eql?(n)}.first
            end
            cmdline.push('--name='+session['name'])
            if session.has_key?('local_db_dir')
              cmdline.push('--local-db-dir='+session['local_db_dir'])
            else
              cmdline.push('--local-dir='+session['local_dir'])
            end
            command2=self.options.get_next_command([:status])
            case command2
            when :status
              stdout, stderr, status = Open3.capture3(*cmdline)
              Log.log.debug("status=#{status}, stderr=#{stderr}")
              items=stdout.split("\n").inject({}){|m,l|i=l.split(/:  */);m[i.first.lstrip]=i.last.lstrip;m}
              return {:type=>:single_object,:data=>items}
            else raise "error"
            end # command
          else raise "error"
          end # command
        end # execute_action
      end # Sync
    end # Plugins
  end # Cli
end # Aspera
