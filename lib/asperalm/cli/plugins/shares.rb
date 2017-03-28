require 'asperalm/cli/plugin'

module Asperalm
  module Cli
    module Plugins
      class Shares < Plugin
        def opt_names; [:url,:username,:password]; end

        attr_accessor :faspmanager

        def command_list;[ :upload, :download, :browse ];end

        def set_options
          self.add_opt_simple(:url,"-wURI", "--url=URI","URL of application, e.g. http://org.asperafiles.com")
          self.add_opt_simple(:username,"-uSTRING", "--username=STRING","username to log in")
          self.add_opt_simple(:password,"-pSTRING", "--password=STRING","password")
        end

        def dojob(command,argv)
          api_shares=Rest.new(self.get_option_mandatory(:url)+'/node_api',{:basic_auth=>{:user=>self.get_option_mandatory(:username), :password=>self.get_option_mandatory(:password)}})
          case command
          when :browse
            thepath=self.class.get_next_arg_value(argv,"path")
            send_result=api_shares.call({:operation=>'POST',:subpath=>'files/browse',:json_params=>{ :path => thepath} } )
            return nil if !send_result[:data].has_key?('items')
            return {:fields=>send_result[:data]['items'].first.keys,:values=>send_result[:data]['items']}
          when :upload
            filelist = self.class.get_remaining_arguments(argv,"file list")
            Log.log.debug("file list=#{filelist}")
            if filelist.length < 2 then
              raise OptionParser::InvalidArgument,"Missing source(s) and destination"
            end
            destination=filelist.pop
            send_result=api_shares.call({:operation=>'POST',:subpath=>'files/upload_setup',:json_params=>{ :transfer_requests => [ { :transfer_request => { :paths => [ { :destination => destination } ] } } ] }})
            raise "expecting one session exactly" if send_result[:data]['transfer_specs'].length != 1
            transfer_spec=send_result[:data]['transfer_specs'].first['transfer_spec']
            transfer_spec['paths']=filelist.map { |i| {'source'=>i} }
            @faspmanager.transfer_with_spec(transfer_spec)
          when :download
            filelist = self.class.get_remaining_arguments(argv,"source(s) and destination")
            Log.log.debug("file list=#{filelist}")
            raise OptionParser::InvalidArgument,"Missing source(s) and destination" if filelist.length < 2
            destination=filelist.pop
            send_result=api_shares.call({:operation=>'POST',:subpath=>'files/download_setup',:json_params=>{ :transfer_requests => [ { :transfer_request => { :paths => filelist.map {|i| {:source=>i}; } } } ] }})
            raise "expecting one session exactly" if send_result[:data]['transfer_specs'].length != 1
            transfer_spec=send_result[:data]['transfer_specs'].first['transfer_spec']
            @faspmanager.transfer_with_spec(transfer_spec)
            return nil
          end
        end
      end
    end
  end # Cli
end # Asperalm
