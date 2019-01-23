require 'asperalm/cli/basic_auth_plugin'
require 'asperalm/ascmd'
require 'asperalm/ssh'
require 'asperalm/nagios'
require 'tempfile'

module Asperalm
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
          self.options.add_opt_simple(:ssh_keys,Array,'one ssh key at a time')
          self.options.set_option(:ssh_keys,[])
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

        ACTIONS=[:nagios,:nodeadmin,:userdata,:configurator,:ctl,:download,:upload,:browse,:delete,:rename].concat(Asperalm::AsCmd::OPERATIONS)

        def execute_action
          server_uri=URI.parse(self.options.get_option(:url,:mandatory))
          Log.log.debug("URI : #{server_uri}, port=#{server_uri.port}, scheme:#{server_uri.scheme}")
          shell_executor=nil
          case server_uri.scheme
          when 'ssh'
            server_transfer_spec={
              'remote_host'=>server_uri.hostname,
              'remote_user'=>self.options.get_option(:username,:mandatory),
            }
            ssh_options={}
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
            raise 'internal error, expecting array' if !ssh_keys.is_a?(Array)
            if !ssh_keys.empty?
              Log.log.debug("ssh keys=#{ssh_keys}")
              ssh_options[:keys]=ssh_keys
              server_transfer_spec['EX_ssh_key_paths']=ssh_keys
              cred_set=true
            end
            raise 'either password or key must be provided' if !cred_set
            shell_executor=Ssh.new(server_transfer_spec['remote_host'],server_transfer_spec['remote_user'],ssh_options)
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
          when :nagios
            nagios=Nagios.new
            command_nagios=self.options.get_next_command([ :app_services, :transfer ])
            case command_nagios
            when :app_services
              begin
                asctl_parse(shell_executor.execute(['asctl','all:status'])).each do |i|
                  case i['state']
                  when 'running'
                    nagios.add_ok(i['process'],i['state'])
                  else
                    nagios.add_critical(i['process'],i['state'])
                  end
                end
              rescue => e
                nagios.add_critical('general',e.to_s)
              end
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
              puts("#{statuses}")
              if TransferAgent.session_status(statuses).eql?(:success)
                nagios.add_ok('transfer','ok')
              else
                nagios.add_critical('transfer',statuses.select{|i|!i.eql?(:success)}.first.to_s)
              end
            else raise "ERROR"
            end
            return nagios.result
          when :nodeadmin,:userdata,:configurator,:ctl
            realcmd='as'+command.to_s
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
          when *Asperalm::AsCmd::OPERATIONS
            args=self.options.get_next_argument('ascmd command arguments',:multiple,:optional)
            ascmd=Asperalm::AsCmd.new(shell_executor)
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
            rescue Asperalm::AsCmd::Error => e
              raise CliBadArgument,e.extended_message
            end
          else raise "programing error: unexpected action"
          end
        end # execute_action
      end # Server
    end # Plugins
  end # Cli
end # Asperalm
