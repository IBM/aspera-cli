require 'asperalm/cli/plugin'
require 'asperalm/ascmd'

module Asperalm
  module Cli
    module Plugins
      class Fasp < Plugin
        attr_accessor :faspmanager
        # todo: ascmd commands
        def execute_action
          command=self.options.get_next_arg_from_list('command',[:download,:upload].push(*Asperalm::AsCmd.action_list))
          ascmd=Asperalm::AsCmd.new({:host=>faspmanager.class.ts_override_data['remote_host'], :user=>faspmanager.class.ts_override_data["remote_user"], :password => faspmanager.class.ts_override_data["password"]})
          begin
            case command
            when :upload
              filelist = option_parser.get_remaining_arguments("file list")
              Log.log.debug("file list=#{filelist}")
              raise CliBadArgument,"Missing source(s) and destination" if filelist.length < 2
              destination=filelist.pop
              transfer_spec={
                'direction'=>'send',
                'destination_root'=>destination,
                'paths'=>filelist.map { |f| {'source'=>f } }
              }
              faspmanager.transfer_with_spec(transfer_spec)
              return Main.no_result
            when :download
              filelist = option_parser.get_remaining_arguments("file list")
              Log.log.debug("file list=#{filelist}")
              raise CliBadArgument,"Missing source(s) and destination" if filelist.length < 2
              destination=filelist.pop
              transfer_spec={
                'direction'=>'receive',
                'destination_root'=>destination,
                'paths'=>filelist.map { |f| {'source'=>f } }
              }
              faspmanager.transfer_with_spec(transfer_spec)
              return Main.no_result
            when :ls; return {:data=>ascmd.ls(self.options.get_next_arg_value('path')),:type=>:hash_array,:fields=>[:name,:sgid,:suid,:size,:ctime,:mtime,:atime]}
            when :mkdir; ascmd.mkdir(self.options.get_next_arg_value('path'));return Main.no_result
            when :mv; ascmd.mv(self.options.get_next_arg_value('src'),self.options.get_next_arg_value('dst'));return Main.no_result
            when :cp; ascmd.cp(self.options.get_next_arg_value('src'),self.options.get_next_arg_value('dst'));return Main.no_result
            when :info; return {:data=>ascmd.info(),:type=>:hash_table}
            when :df; return {:data=>ascmd.df(),:type=>:hash_table}
            when :du; return {:data=>ascmd.du(self.options.get_next_arg_value('path')),:type=>:hash_table}
            when :md5sum; return {:data=>ascmd.md5sum(self.options.get_next_arg_value('path')),:type=>:hash_table}
            when :rm; ascmd.rm(self.options.get_next_arg_value('path'));return Main.no_result
            end
          rescue Asperalm::AsCmd::Error => e
            raise CliBadArgument,e.extended_message
          end
        end
      end # Fasp
    end # Plugins
  end # Cli
end # Asperalm
