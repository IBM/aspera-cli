require 'asperalm/cli/plugin'

module Asperalm
  module Cli
    module Plugins
      class Fasp < Plugin
        attr_accessor :faspmanager

        # todo: ascmd commands
        def execute_action
          command=self.options.get_next_arg_from_list('command',[:download,:upload])
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
          end
        end
      end # Fasp
    end # Plugins
  end # Cli
end # Asperalm
