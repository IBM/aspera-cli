require 'asperalm/cli/main'
require 'asperalm/cli/basic_auth_plugin'
require 'asperalm/ascmd'
require 'asperalm/ssh'

module Asperalm
  module Cli
    module Plugins
      # implement basic remote access with FASP/SSH
      class Server < BasicAuthPlugin
        #def declare_options; end
        def action_list; [:nodeadmin,:userdata,:configurator,:download,:upload,:browse,:delete,:rename].push(*Asperalm::AsCmd.action_list);end

        # converts keys in hash table from symbol to string
        def convert_hash_sym_key(hash);h={};hash.each { |k,v| h[k.to_s]=v};return h;end

        def result_convert_hash_array(hash_array,fields)
          return {:data=>hash_array.map {|i| convert_hash_sym_key(i)},:type=>:hash_array,:fields=>fields.map {|f| f.to_s}}
        end

        def result_convert_key_val_list(key_val_list)
          return {:data=>convert_hash_sym_key(key_val_list),:type=>:key_val_list}
        end

        def execute_action
          server_uri=URI.parse(Main.tool.options.get_option_mandatory(:url))
          Log.log.debug("URI : #{server_uri}, port=#{server_uri.port}, scheme:#{server_uri.scheme}")
          raise CliError,"Only ssh scheme is supported in url" if !server_uri.scheme.eql?("ssh")
          username=Main.tool.options.get_option_mandatory(:username)
          ssh_options={}
          # todo : support ssh key
          ssh_options[:password]=Main.tool.options.get_option_mandatory(:password)
          ssh_options[:port]=server_uri.port if !server_uri.port.nil?
          ssh_executor=Ssh.new(server_uri.hostname,username,ssh_options)
          ascmd=Asperalm::AsCmd.new(ssh_executor)

          transfer_spec={
            "remote_host"=>server_uri.hostname,
            "remote_user"=>username,
            "password"=>ssh_options[:password]
          }

          # get command and set aliases
          command=Main.tool.options.get_next_arg_from_list('command',action_list)
          command=:ls if command.eql?(:browse)
          command=:rm if command.eql?(:delete)
          command=:mv if command.eql?(:rename)
          begin
            case command
            when :nodeadmin,:userdata,:configurator
              realcmd="as"+command.to_s
              args = Main.tool.options.get_remaining_arguments("#{realcmd} arguments")
              command = args.unshift(realcmd).map{|v|'"'+v+'"'}.join(" ")
              return {:data=>ssh_executor.exec_session(command),:type=>:status}
            when :upload
              filelist = Main.tool.options.get_remaining_arguments("source list",1)
              destination=Main.tool.options.get_next_arg_value("destination")
              transfer_spec.merge!({
                'direction'=>'send',
                'destination_root'=>destination,
                'paths'=>filelist.map { |f| {'source'=>f } }
              })
              return Main.tool.start_transfer(transfer_spec)
            when :download
              filelist = Main.tool.options.get_remaining_arguments("source list",1)
              destination=Main.tool.options.get_next_arg_value("destination")
              transfer_spec.merge!({
                'direction'=>'receive',
                'destination_root'=>destination,
                'paths'=>filelist.map { |f| {'source'=>f } }
              })
              return Main.tool.start_transfer(transfer_spec)
            when :mkdir; ascmd.mkdir(Main.tool.options.get_next_arg_value('path'));return Main.result_success
            when :mv; ascmd.mv(Main.tool.options.get_next_arg_value('src'),Main.tool.options.get_next_arg_value('dst'));return Main.result_success
            when :cp; ascmd.cp(Main.tool.options.get_next_arg_value('src'),Main.tool.options.get_next_arg_value('dst'));return Main.result_success
            when :rm; ascmd.rm(Main.tool.options.get_next_arg_value('path'));return Main.result_success
            when :ls; return result_convert_hash_array(ascmd.ls(Main.tool.options.get_next_arg_value('path')),[:name,:sgid,:suid,:size,:ctime,:mtime,:atime])
            when :info; return result_convert_key_val_list(ascmd.info())
            when :df; return {:data=>ascmd.df(),:type=>:key_val_list}
            when :du; return {:data=>ascmd.du(Main.tool.options.get_next_arg_value('path')),:type=>:key_val_list}
            when :md5sum; return {:data=>ascmd.md5sum(Main.tool.options.get_next_arg_value('path')),:type=>:key_val_list}
            end
          rescue Asperalm::AsCmd::Error => e
            raise CliBadArgument,e.extended_message
          end
        end
      end # Fasp
    end # Plugins
  end # Cli
end # Asperalm
