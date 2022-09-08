# frozen_string_literal: true

require 'aspera/cli/basic_auth_plugin'
require 'aspera/ssh'
require 'aspera/nagios'

module Aspera
  module Cli
    module Plugins
      # remote admin with SSH
      class Svradm < BasicAuthPlugin
        class LocalExecutor
          def execute(cmd,_input=nil)
            Log.log.debug("Executing: #{cmd}")
            %x(#{cmd.join(' ')})
          end
        end

        def initialize(env)
          super(env)
          options.add_opt_simple(:ssh_keys,'ssh key path list (Array or single)')
          options.add_opt_simple(:ssh_options,'ssh options (Hash)')
          options.add_opt_simple(:cmd_prefix,'prefix to add for as cmd execution, e.g. sudo or /opt/aspera/bin ')
          options.set_option(:ssh_keys,[])
          options.set_option(:ssh_options,{})
          options.parse_options!
        end

        def asctl_parse(text)
          # normal separator
          r = /:\s*/
          result = []
          text.split("\n").each do |line|
            # console: missing space
            line.gsub!(/(SessionDataCollector)/,'\1 ')
            # orchestrator
            line.gsub!(/ with pid:.*/,'')
            line.gsub!(/ is /,': ')
            items = line.split(r)
            next unless items.length.eql?(2)
            state = {'process' => items.first,'state' => items.last}
            # console
            state['state'].gsub!(/\.+$/,'')
            # console
            state['process'].gsub!(/^.+::/,'')
            # faspex
            state['process'].gsub!(/^Faspex /,'')
            # faspex
            state['process'].gsub!(/ Background/,'')
            state['process'].gsub!(/serving orchestrator on port /,'')
            # console
            r = /\s+/ if state['process'].eql?('Console')
            # orchestrator
            state['process'].gsub!(/^  -> /,'')
            state['process'].gsub!(/ Process/,'')
            result.push(state)
          end
          return result
        end

        def asconfigurator_parse(result)
          lines = result.split("\n")
          # not windows
          Log.log.debug(%x(type asconfigurator))
          status=lines.shift
          case status
          when 'success'
            result = []
            lines.each do |line|
              Log.log.debug(line.to_s)
              # normalize values
              data = line.
                gsub(/^"/,'').
                gsub(/,""$/,',"AS_EMPTY"').
                gsub(/"$/,'').
                split('","').
                map{|i|case i;when 'AS_NULL' then nil;when 'AS_EMPTY' then '';when 'true' then true;when 'false' then false;else i;end}
              data.insert(1,'') if data.length.eql?(4)
              titles=%w[level section parameter value default]
              result.push(titles.each_with_object({}){|t,o|o[t]=data.shift})
            end
            return result
          when 'failure'
            raise lines.join("\n")
          else raise "Unexpected: #{status}"
          end
        end

        ACTIONS = %i[nodeadmin userdata configurator ctl health].freeze

        def execute_action
          server_uri = URI.parse(options.get_option(:url,is_type: :mandatory))
          Log.log.debug("URI : #{server_uri}, port=#{server_uri.port}, scheme:#{server_uri.scheme}")
          server_transfer_spec = {'remote_host' => }
          shell_executor = nil
          case server_uri.scheme
          when 'local'
            shell_executor = LocalExecutor.new
          else # when 'ssh'
            Log.log.error("Scheme #{server_uri.scheme} not supported. Assuming SSH.") if !server_uri.scheme.eql?('ssh')
            if options.get_option(:username).nil?
              options.set_option(:username,Aspera::Fasp::TransferSpec::ACCESS_KEY_TRANSFER_USER)
              Log.log.info("Using default transfer user: #{Aspera::Fasp::TransferSpec::ACCESS_KEY_TRANSFER_USER}")
            end
            ssh_user = 
            ssh_options = options.get_option(:ssh_options)
            raise 'expecting a Hash for ssh_options' unless ssh_options.is_a?(Hash)
            ssh_options = ssh_options.symbolize_keys
            if !server_uri.port.nil?
              ssh_options[:port] = server_uri.port
            end
            cred_set = false
            password = options.get_option(:password)
            if !password.nil?
              ssh_options[:password] = password
              cred_set = true
            end
            ssh_keys = options.get_option(:ssh_keys)
            if !ssh_keys.nil?
              raise 'expecting single value or array for ssh_keys' unless ssh_keys.is_a?(Array) || ssh_keys.is_a?(String)
              ssh_keys = [ssh_keys] if ssh_keys.is_a?(String)
              ssh_keys.map!{|p|File.expand_path(p)}
              Log.log.debug("ssh keys=#{ssh_keys}")
              if !ssh_keys.empty?
                ssh_options[:keys] = ssh_keys
                ssh_keys.each do |k|
                  Log.log.warn("no such key file: #{k}") unless File.exist?(k)
                end
                cred_set = true
              end
            end
            # if user provided transfer spec has a token, we will use by pass keys
            cred_set = true if transfer.option_transfer_spec['token'].is_a?(String)
            raise 'either password, key , or transfer spec token must be provided' if !cred_set
            shell_executor = Ssh.new(server_uri.hostname,options.get_option(:username,is_type: :mandatory),ssh_options)
          end

          # get command and set aliases
          command = options.get_next_command(ACTIONS)
          case command
          when :health
            nagios = Nagios.new
            command_nagios = options.get_next_command(%i[app_services asctlstatus])
            case command_nagios
            when :app_services
              # will not work with aspshell, requires Linux/bash
              procs = shell_executor.execute('ps -A -o comm').split("\n")
              Log.log.debug("found: #{procs}")
              %w[asperanoded asperaredisd].each do |name|
                nagios.add_critical('general',"missing process #{name}") unless procs.include?(name)
              end
              nagios.add_ok('daemons','ok') if nagios.data.empty?
              return nagios.result
            when :asctlstatus
              realcmd = 'asctl'
              prefix = options.get_option(:cmd_prefix)
              realcmd = "#{prefix}#{realcmd} all:status" unless prefix.nil?
              result = shell_executor.execute(realcmd.split)
              data = asctl_parse(result)
              data.each do |i|
                if i['state'].eql?('running')
                  nagios.add_ok(i['process'],i['state'])
                else
                  nagios.add_critical(i['process'],i['state'])
                end
              end
            else raise 'ERROR'
            end
            return nagios.result
          when :nodeadmin,:userdata,:configurator,:ctl
            realcmd = "as#{command}"
            prefix = options.get_option(:cmd_prefix)
            realcmd = "#{prefix}#{realcmd}" unless prefix.nil?
            args = options.get_next_argument("#{realcmd} arguments",expected: :multiple)
            args.unshift('-x') if command.eql?(:configurator)
            result = shell_executor.execute(args.unshift(realcmd))
            case command
            when :ctl
              return {type: :object_list,data: asctl_parse(result)}
            when :configurator
              result=asconfigurator_parse(result)
              return {type: :object_list,data: result} # ,option_expand_last: true
            end
            return Main.result_status(result)
          else raise 'internal error: unexpected action'
          end
        end # execute_action
      end # Server
    end # Plugins
  end # Cli
end # Aspera
