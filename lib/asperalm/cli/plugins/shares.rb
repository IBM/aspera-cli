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
          when :upload
            filelist = argv
            Log.log.debug("file list=#{filelist}")
            if filelist.length < 2 then
              raise OptionParser::InvalidArgument,"Missing source(s) and destination"
            end

            destination=filelist.pop

            send_result=api_shares.call({:operation=>'POST',:subpath=>'files/upload_setup',:json_params=>{ :transfer_requests => [ { :transfer_request => { :paths => [ { :destination => destination } ] } } ] }})
            send_result[:data]['transfer_specs'].each{ |s|
              session=s['transfer_spec']
              @faspmanager.do_transfer(
              :mode    => :send,
              :dest    => session['destination_root'],
              :user    => session['remote_user'],
              :host    => session['remote_host'],
              :token   => session['token'],
              #:cookie  => session['cookie'],
              #:tags    => session['tags'],
              :srcList => filelist,
              :rawArgs => [ '-P', '33001', '-d', '-q', '--ignore-host-key', '-k', '2', '--save-before-overwrite','--partial-file-suffix=.partial' ],
              :retries => 10,
              :use_aspera_key => true)
            }
          when :download
            filelist = argv
            Log.log.debug("file list=#{filelist}")
            if filelist.length < 2 then
              raise OptionParser::InvalidArgument,"Missing source(s) and destination"
            end

            destination=filelist.pop

            send_result=api_shares.call({:operation=>'POST',:subpath=>'files/download_setup',:json_params=>{ :transfer_requests => [ { :transfer_request => { :paths => filelist.map {|i| {:source=>i}; } } } ] }})

            send_result[:data]['transfer_specs'].each{ |s|
              session=s['transfer_spec']
              srcList = session['paths'].map { |i| i['source']}
              @faspmanager.do_transfer(
              :mode    => :recv,
              :dest    => destination,
              :user    => session['remote_user'],
              :host    => session['remote_host'],
              :token   => session['token'],
              :cookie  => session['cookie'],
              :tags    => session['tags'],
              :srcList => srcList,
              :rawArgs => [ '-P', '33001', '-d', '-q', '--ignore-host-key', '-k', '2', '--save-before-overwrite','--partial-file-suffix=.partial' ],
              :retries => 10,
              :use_aspera_key => true)
            }
          when :browse
            thepath=self.class.get_next_arg_value(argv,"path")
            send_result=api_shares.call({:operation=>'POST',:subpath=>'files/browse',:json_params=>{ :path => thepath} } )
            return {:fields=>send_result[:data]['items'].first.keys,:values=>send_result[:data]['items']}
          end
        end
      end
    end
  end # Cli
end # Asperalm
