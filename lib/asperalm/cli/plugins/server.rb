require 'asperalm/cli/main'
require 'asperalm/cli/plugin'
require 'asperalm/ascmd'
require 'asperalm/ssh'

module Asperalm
  module Cli
    module Plugins
      # implement basic remote access with FASP/SSH
      class Server < Plugin
        def declare_options; end

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
          command=Main.tool.options.get_next_arg_from_list('command',action_list)
          # aliases
          command=:ls if command.eql?(:browse)
          command=:rm if command.eql?(:delete)
          command=:mv if command.eql?(:rename)
          ssh_executor=Ssh.new(
          Main.tool.faspmanager.class.ts_override_data['remote_host'],
          Main.tool.faspmanager.class.ts_override_data["remote_user"],
          {:password => Main.tool.faspmanager.class.ts_override_data["password"]})

          ascmd=Asperalm::AsCmd.new(ssh_executor)
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
              transfer_spec={
                'direction'=>'send',
                'destination_root'=>destination,
                'paths'=>filelist.map { |f| {'source'=>f } }
              }
              return Main.tool.start_transfer(transfer_spec)
            when :download
              filelist = Main.tool.options.get_remaining_arguments("source list",1)
              destination=Main.tool.options.get_next_arg_value("destination")
              transfer_spec={
                'direction'=>'receive',
                'destination_root'=>destination,
                'paths'=>filelist.map { |f| {'source'=>f } }
              }
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
