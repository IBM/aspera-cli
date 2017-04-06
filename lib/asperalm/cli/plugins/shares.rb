require 'asperalm/cli/plugin'

module Asperalm
  module Cli
    module Plugins
      class Shares < Plugin
        attr_accessor :faspmanager

        def set_options
          @option_parser.add_opt_simple(:url,"-wURI", "--url=URI","URL of application, e.g. http://org.asperafiles.com")
          @option_parser.add_opt_simple(:username,"-uSTRING", "--username=STRING","username to log in")
          @option_parser.add_opt_simple(:password,"-pSTRING", "--password=STRING","password")
        end

        def dojob
          api_shares=Rest.new(@option_parser.get_option_mandatory(:url)+'/node_api',{:basic_auth=>{:user=>@option_parser.get_option_mandatory(:username), :password=>@option_parser.get_option_mandatory(:password)}})
          command=@option_parser.get_next_arg_from_list('command',[ :upload, :download, :browse ])
          case command
          when :browse
            thepath=@option_parser.get_next_arg_value("path")
            send_result=api_shares.call({:operation=>'POST',:subpath=>'files/browse',:json_params=>{ :path => thepath} } )
            return nil if !send_result[:data].has_key?('items')
            return {:fields=>send_result[:data]['items'].first.keys,:values=>send_result[:data]['items']}
          when :upload
            filelist = @option_parser.get_remaining_arguments("file list")
            Log.log.debug("file list=#{filelist}")
            if filelist.length < 2 then
              raise CliBadArgument,"Missing source(s) and destination"
            end
            destination=filelist.pop
            send_result=api_shares.call({:operation=>'POST',:subpath=>'files/upload_setup',:json_params=>{ :transfer_requests => [ { :transfer_request => { :paths => [ { :destination => destination } ] } } ] }})
            raise "expecting one session exactly" if send_result[:data]['transfer_specs'].length != 1
            transfer_spec=send_result[:data]['transfer_specs'].first['transfer_spec']
            transfer_spec['paths']=filelist.map { |i| {'source'=>i} }
            @faspmanager.transfer_with_spec(transfer_spec)
          when :download
            filelist = @option_parser.get_remaining_arguments("source(s) and destination")
            Log.log.debug("file list=#{filelist}")
            raise CliBadArgument,"Missing source(s) and destination" if filelist.length < 2
            destination=filelist.pop
            send_result=api_shares.call({:operation=>'POST',:subpath=>'files/download_setup',:json_params=>{ :transfer_requests => [ { :transfer_request => { :paths => filelist.map {|i| {:source=>i}; } } } ] }})
            raise "expecting one session exactly" if send_result[:data]['transfer_specs'].length != 1
            transfer_spec=send_result[:data]['transfer_specs'].first['transfer_spec']
            @faspmanager.transfer_with_spec(transfer_spec)
            return nil
          else
            raise "ERROR, unknown command: [#{command}]"
          end
        end
      end
    end
  end # Cli
end # Asperalm
