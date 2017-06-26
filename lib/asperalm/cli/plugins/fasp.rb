require 'asperalm/cli/main'
require 'asperalm/cli/plugin'
require 'asperalm/ascmd'

module Asperalm
  module Cli
    module Plugins
      class Fasp < Plugin
        def declare_options; end

        def action_list; [:download,:upload,:browse,:delete,:rename].push(*Asperalm::AsCmd.action_list);end

        # todo: ascmd commands
        def execute_action
          command=Main.tool.options.get_next_arg_from_list('command',action_list)
          # aliases
          command=:ls if command.eql?(:browse)
          command=:rm if command.eql?(:delete)
          command=:mv if command.eql?(:rename)
          ascmd=Asperalm::AsCmd.new({:host=>Main.tool.faspmanager.class.ts_override_data['remote_host'], :user=>Main.tool.faspmanager.class.ts_override_data["remote_user"], :password => Main.tool.faspmanager.class.ts_override_data["password"]})
          begin
            case command
            when :upload
              filelist = Main.tool.options.get_remaining_arguments("file list")
              Log.log.debug("file list=#{filelist}")
              raise CliBadArgument,"Missing source(s) and destination" if filelist.length < 2
              destination=filelist.pop
              transfer_spec={
                'direction'=>'send',
                'destination_root'=>destination,
                'paths'=>filelist.map { |f| {'source'=>f } }
              }
              Main.tool.faspmanager.transfer_with_spec(transfer_spec)
              return Main.result_success
            when :download
              filelist = Main.tool.options.get_remaining_arguments("file list")
              Log.log.debug("file list=#{filelist}")
              raise CliBadArgument,"Missing source(s) and destination" if filelist.length < 2
              destination=filelist.pop
              transfer_spec={
                'direction'=>'receive',
                'destination_root'=>destination,
                'paths'=>filelist.map { |f| {'source'=>f } }
              }
              Main.tool.faspmanager.transfer_with_spec(transfer_spec)
              return Main.result_success
            when :ls; return {:data=>ascmd.ls(Main.tool.options.get_next_arg_value('path')),:type=>:hash_array,:fields=>[:name,:sgid,:suid,:size,:ctime,:mtime,:atime]}
            when :mkdir; ascmd.mkdir(Main.tool.options.get_next_arg_value('path'));return Main.result_success
            when :mv; ascmd.mv(Main.tool.options.get_next_arg_value('src'),Main.tool.options.get_next_arg_value('dst'));return Main.result_success
            when :cp; ascmd.cp(Main.tool.options.get_next_arg_value('src'),Main.tool.options.get_next_arg_value('dst'));return Main.result_success
            when :info; return {:data=>ascmd.info(),:type=>:hash_table}
            when :df; return {:data=>ascmd.df(),:type=>:hash_table}
            when :du; return {:data=>ascmd.du(Main.tool.options.get_next_arg_value('path')),:type=>:hash_table}
            when :md5sum; return {:data=>ascmd.md5sum(Main.tool.options.get_next_arg_value('path')),:type=>:hash_table}
            when :rm; ascmd.rm(Main.tool.options.get_next_arg_value('path'));return Main.result_success
            end
          rescue Asperalm::AsCmd::Error => e
            raise CliBadArgument,e.extended_message
          end
        end
      end # Fasp
    end # Plugins
  end # Cli
end # Asperalm
