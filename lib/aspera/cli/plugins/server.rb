require 'aspera/cli/basic_auth_plugin'
require 'aspera/ascmd'
require 'aspera/node'
require 'aspera/ssh'
require 'aspera/nagios'
require 'tempfile'

module Aspera
  module Cli
    module Plugins
      # implement basic remote access with FASP/SSH
      class Server < BasicAuthPlugin
        class LocalExecutor
          def execute(cmd,input=nil)
            `#{cmd}`
          end
        end

        def initialize(env)
          super(env)
          self.options.add_opt_simple(:ssh_keys,'ssh key path list (Array or single)')
          self.options.add_opt_simple(:ssh_options,'ssh options (Hash)')
          self.options.add_opt_simple(:cmd_prefix,'prefix to add for as cmd execution, e.g. sudo or /opt/aspera/bin ')
          self.options.set_option(:ssh_keys,[])
          self.options.set_option(:ssh_options,{})
          self.options.parse_options!
        end

        def key_symb_to_str_single(source)
          return source.inject({}){|memo,(k,v)| memo[k.to_s] = v; memo}
        end

        def key_symb_to_str_list(source)
          return source.map{|o| key_symb_to_str_single(o)}
        end

        def asctl_parse(text)
          r=/:\s*/
          return text.split("\n").map do |line|
            # console
            line.gsub!(/(SessionDataCollector)/,'\1 ')
            # orchestrator
            line.gsub!(/ with pid:.*/,'')
            line.gsub!(/ is /,': ')
            x=line.split(r)
            next unless x.length.eql?(2)
            y={'process'=>x.first,'state'=>x.last}
            # console
            y['state'].gsub!(/\.+$/,'')
            # console
            y['process'].gsub!(/^.+::/,'')
            # faspex
            y['process'].gsub!(/^Faspex /,'')
            # faspex
            y['process'].gsub!(/ Background/,'')
            y['process'].gsub!(/serving orchestrator on port /,'')
            # console
            r=/\s+/ if y['process'].eql?('Console')
            # orchestrator
            y['process'].gsub!(/^  -> /,'')
            y['process'].gsub!(/ Process/,'')
            y
          end.select{|i|!i.nil?}
        end

        ACTIONS=[:health,:nodeadmin,:userdata,:configurator,:ctl,:download,:upload,:browse,:delete,:rename].concat(Aspera::AsCmd::OPERATIONS)

        def execute_action
          server_uri=URI.parse(self.options.get_option(:url,:mandatory))
          Log.log.debug("URI : #{server_uri}, port=#{server_uri.port}, scheme:#{server_uri.scheme}")
          server_transfer_spec={'remote_host'=>server_uri.hostname}
          shell_executor=nil
          case server_uri.scheme
          when 'ssh'
            if self.options.get_option(:username,:optional).nil?
              self.options.set_option(:username,Aspera::Node::ACCESS_KEY_TRANSFER_USER)
              Log.log.info("Using default transfer user: #{Aspera::Node::ACCESS_KEY_TRANSFER_USER}")
            end
            server_transfer_spec['remote_user']=self.options.get_option(:username,:mandatory)
            ssh_options=self.options.get_option(:ssh_options,:optional)
            raise 'expecting a Hash for ssh_options' unless ssh_options.is_a?(Hash)
            if !server_uri.port.nil?
              ssh_options[:port]=server_uri.port
              server_transfer_spec['ssh_port']=server_uri.port
            end
            cred_set=false
            password=self.options.get_option(:password,:optional)
            if !password.nil?
              ssh_options[:password]=password
              server_transfer_spec['remote_password']=password
              cred_set=true
            end
            ssh_keys=self.options.get_option(:ssh_keys,:optional)
            if !ssh_keys.nil?
              raise 'expecting single value or array for ssh_keys' unless ssh_keys.is_a?(Array) or ssh_keys.is_a?(String)
              ssh_keys=[ssh_keys] if ssh_keys.is_a?(String)
              ssh_keys.map!{|p|File.expand_path(p)}
              Log.log.debug("ssh keys=#{ssh_keys}")
              if !ssh_keys.empty?
                ssh_options[:keys]=ssh_keys
                server_transfer_spec['EX_ssh_key_paths']=ssh_keys
                ssh_keys.each do |k|
                  Log.log.warn("no such key file: #{k}") unless File.exist?(k)
                end
                cred_set=true
              end
            end
            # if user provided transfer spec has a token, we will use by pass keys
            cred_set=true if self.transfer.option_transfer_spec['token'].is_a?(String)
            raise 'either password, key , or transfer spec token must be provided' if !cred_set
            shell_executor=Ssh.new(server_transfer_spec['remote_host'],server_transfer_spec['remote_user'],ssh_options)
          when 'https'
            raise "ERROR: transfer spec with token required" unless self.transfer.option_transfer_spec['token'].is_a?(String)
            server_transfer_spec.merge!({
              'wss_enabled'=>true,
              'wss_port'   =>server_uri.port
            })
          when 'local'
            shell_executor=LocalExecutor.new
          else
            raise CliError,'Only ssh scheme is supported in url' if !server_uri.scheme.eql?('ssh')
          end

          # get command and set aliases
          command=self.options.get_next_command(ACTIONS)
          command=:ls if command.eql?(:browse)
          command=:rm if command.eql?(:delete)
          command=:mv if command.eql?(:rename)
          case command
          when :health
            nagios=Nagios.new
            command_nagios=self.options.get_next_command([ :app_services, :transfer, :asctlstatus ])
            case command_nagios
            when :app_services
              # will not work with aspshell, requires Linux/bash
              procs=shell_executor.execute('ps -A -o comm').split("\n")
              Log.log.debug("found: #{procs}")
              ['asperanoded','asperaredisd'].each do |name|
                nagios.add_critical('general',"missing process #{name}") unless procs.include?(name)
              end
              nagios.add_ok('daemons','ok') if nagios.data.empty?
              return nagios.result
            when :transfer
              file = Tempfile.new('transfer_test')
              filepath=file.path
              file.write("This is a test file for transfer test")
              file.close
              probe_ts=server_transfer_spec.merge({
                'direction'     => 'send',
                'cookie'        => 'aspera.sync', # hide in console
                'resume_policy' => 'none',
                'paths'         => [{'source'=>filepath,'destination'=>'.fasping'}]
              })
              statuses=self.transfer.start(probe_ts,{:src=>:direct})
              file.unlink
              if TransferAgent.session_status(statuses).eql?(:success)
                nagios.add_ok('transfer','ok')
              else
                nagios.add_critical('transfer',statuses.select{|i|!i.eql?(:success)}.first.to_s)
              end
            when :asctlstatus
              realcmd='asctl'
              prefix=self.options.get_option(:cmd_prefix,:optional)
              realcmd="#{prefix}#{realcmd} all:status" unless prefix.nil?
              result=shell_executor.execute(realcmd.split(' '))
              data=asctl_parse(result)
              data.each do |i|
                if i['state'].eql?('running')
                  nagios.add_ok(i['process'],i['state'])
                else
                  nagios.add_critical(i['process'],i['state'])
                end
              end
            else raise "ERROR"
            end
            return nagios.result
          when :nodeadmin,:userdata,:configurator,:ctl
            realcmd='as'+command.to_s
            prefix=self.options.get_option(:cmd_prefix,:optional)
            if !prefix.nil?
              realcmd="#{prefix}#{realcmd}"
            end
            args = self.options.get_next_argument("#{realcmd} arguments",:multiple)
            result=shell_executor.execute(args.unshift(realcmd))
            case command
            when :ctl
              return {:type=>:object_list,:data=>asctl_parse(result)}#
            when :configurator
              lines=result.split("\n")
              Log.log.debug(`type asconfigurator`)
              result=lines
              if lines.first.eql?('success')
                lines.shift
                result={}
                lines.each do |line|
                  Log.log.debug("#{line}")
                  data=line.split(',').map{|i|i.gsub(/^"/,'').gsub(/"$/,'')}.map{|i|case i;when'AS_NULL';nil;when'true';true;when'false';false;else i;end}
                  Log.log.debug("#{data}")
                  section=data.shift
                  datapart=result[section]||={}
                  if section.eql?('user')
                    name=data.shift
                    datapart=datapart[name]||={}
                  end
                  datapart=datapart[data.shift]={}
                  datapart['default']=data.pop
                  datapart['value']=data.pop
                end
                return {:type=>:single_object,:data=>result,:fields=>['section','name','value','default'],:option_expand_last=>true}
              end
            end
            return Main.result_status(result)
          when :upload
            return Main.result_transfer(self.transfer.start(server_transfer_spec.merge('direction'=>'send'),{:src=>:direct}))
          when :download
            return Main.result_transfer(self.transfer.start(server_transfer_spec.merge('direction'=>'receive'),{:src=>:direct}))
          when *Aspera::AsCmd::OPERATIONS
            args=self.options.get_next_argument('ascmd command arguments',:multiple,:optional)
            ascmd=Aspera::AsCmd.new(shell_executor)
            begin
              result=ascmd.send(:execute_single,command,args)
              case command
              when :mkdir;  return Main.result_success
              when :mv;     return Main.result_success
              when :cp;     return Main.result_success
              when :rm;     return Main.result_success
              when :ls;     return {:type=>:object_list,:data=>key_symb_to_str_list(result),:fields=>['zmode','zuid','zgid','size','mtime','name']}
              when :info;   return {:type=>:single_object,:data=>key_symb_to_str_single(result)}
              when :df;     return {:type=>:object_list,:data=>key_symb_to_str_list(result)}
              when :du;     return {:type=>:single_object,:data=>key_symb_to_str_single(result)}
              when :md5sum; return {:type=>:single_object,:data=>key_symb_to_str_single(result)}
              end
            rescue Aspera::AsCmd::Error => e
              raise CliBadArgument,e.extended_message
            end
          else raise "internal error: unexpected action"
          end
        end # execute_action
      end # Server
    end # Plugins
  end # Cli
end # Aspera
