require 'asperalm/cli/basic_auth_plugin'
require 'asperalm/ascmd'
require 'asperalm/ssh'

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

        alias super_declare_options declare_options

        def declare_options
          super_declare_options
          self.options.add_opt_simple(:ssh_keys,Array,"PATH_ARRAY is @json:'[\"path1\",\"path2\"]'")
          self.options.set_option(:ssh_keys,[])
        end

        def action_list; [:nodeadmin,:userdata,:configurator,:download,:upload,:browse,:delete,:rename].push(*Asperalm::AsCmd.action_list);end

        def execute_action
          server_uri=URI.parse(self.options.get_option(:url,:mandatory))
          Log.log.debug("URI : #{server_uri}, port=#{server_uri.port}, scheme:#{server_uri.scheme}")
          shell_executor=nil
          case server_uri.scheme
          when 'ssh'
            transfer_spec={
              "remote_host"=>server_uri.hostname,
              "remote_user"=>self.options.get_option(:username,:mandatory),
            }
            ssh_options={}
            if !server_uri.port.nil?
              ssh_options[:port]=server_uri.port
              transfer_spec["ssh_port"]=server_uri.port
            end
            cred_set=false
            password=self.options.get_option(:password,:optional)
            if !password.nil?
              ssh_options[:password]=password
              transfer_spec['remote_password']=password
              cred_set=true
            end
            ssh_keys=self.options.get_option(:ssh_keys,:optional)
            raise "internal error, expecting array" if !ssh_keys.is_a?(Array)
            if !ssh_keys.empty?
              ssh_options[:keys]=ssh_keys
              transfer_spec["EX_ssh_key_paths"]=ssh_keys
              cred_set=true
            end
            raise "either password or key must be provided" if !cred_set
            shell_executor=Ssh.new(transfer_spec["remote_host"],transfer_spec["remote_user"],ssh_options)
          when 'local'
            shell_executor=LocalExecutor.new
          else
            raise CliError,"Only ssh scheme is supported in url" if !server_uri.scheme.eql?("ssh")
          end

          # get command and set aliases
          command=self.options.get_next_argument('command',action_list)
          command=:ls if command.eql?(:browse)
          command=:rm if command.eql?(:delete)
          command=:mv if command.eql?(:rename)
          begin
            case command
            when :nodeadmin,:userdata,:configurator
              realcmd="as"+command.to_s
              args = self.options.get_next_argument("#{realcmd} arguments",:multiple)
              # concatenate arguments, enclose in double quotes
              command_line = args.unshift(realcmd).map{|v|'"'+v+'"'}.join(" ")
              result=shell_executor.execute(command_line)
              if command.eql?(:configurator)
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
                  return {:type=>:key_val_list,:data=>result,:fields=>['section','name','value','default'],:option_expand_last=>true}
                end
              end
              return Plugin.result_status(result)
            when :upload
              filelist = self.options.get_next_argument("source list",:multiple)
              transfer_spec.merge!({
                'direction'=>'send',
                'paths'=>filelist.map { |f| {'source'=>f } }
              })
              return self.manager.start_transfer(transfer_spec,:direct)
            when :download
              filelist = self.options.get_next_argument("source list",:multiple)
              transfer_spec.merge!({
                'direction'=>'receive',
                'paths'=>filelist.map { |f| {'source'=>f } }
              })
              return self.manager.start_transfer(transfer_spec,:direct)
            when *Asperalm::AsCmd.action_list
              args=self.options.get_next_argument('ascmd command arguments',:multiple,:optional)
              ascmd=Asperalm::AsCmd.new(shell_executor)
              result=ascmd.send(:execute_single,command,args)
              case command
              when :mkdir; return Plugin.result_success
              when :mv; return Plugin.result_success
              when :cp; return Plugin.result_success
              when :rm; return Plugin.result_success
              when :ls; return {:type=>:hash_array,:data=>result,:fields=>[:zmode,:zuid,:zgid,:size,:mtime,:name],:symb_key=>true}
              when :info; return {:type=>:key_val_list,:data=>result,:symb_key=>true}
              when :df; return {:type=>:hash_array,:data=>result,:symb_key=>true}
              when :du; return {:type=>:key_val_list,:data=>result,:symb_key=>true}
              when :md5sum; return {:type=>:key_val_list,:data=>result,:symb_key=>true}
              end
            end
          rescue Asperalm::AsCmd::Error => e
            raise CliBadArgument,e.extended_message
          end
        end
      end # Fasp
    end # Plugins
  end # Cli
end # Asperalm
