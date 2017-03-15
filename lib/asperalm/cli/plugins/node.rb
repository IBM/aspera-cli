require 'asperalm/cli/plugin'

module Asperalm
  module Cli
    module Plugins
      class Node < Plugin
        def opt_names; [:url,:username,:password]; end

        attr_accessor :faspmanager

        def command_list;[ :put, :get, :transfers, :info ];end

        def init_defaults
        end

        def set_options
          self.add_opt_simple(:url,"-wURI", "--url=URI","URL of application, e.g. http://org.asperafiles.com")
          self.add_opt_simple(:username,"-uSTRING", "--username=STRING","username to log in")
          self.add_opt_simple(:password,"-pSTRING", "--password=STRING","password")
        end

        def dojob(command,argv)

          results=''

          api_node=Rest.new(self.get_option_mandatory(:url),{:basic_auth=>{:user=>self.get_option_mandatory(:username), :password=>self.get_option_mandatory(:password)}})

          case command
          when :put
            filelist = argv
            Log.log.debug("file list=#{filelist}")
            if filelist.length < 2 then
              raise OptionParser::InvalidArgument,"Missing source(s) and destination"
            end

            destination=filelist.pop

            send_result=api_node.call({:operation=>'POST',:subpath=>'files/upload_setup',:json_params=>{ :transfer_requests => [ { :transfer_request => { :paths => [ { :destination => destination } ] } } ] }})
            if send_result[:data]['transfer_specs'][0].has_key?('error')
              raise send_result[:data]['transfer_specs'][0]['error']['user_message']
            end
            send_result[:data]['transfer_specs'].each{ |s|
              session=s['transfer_spec']
              results=@faspmanager.do_transfer(
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
          when :get
            filelist = argv
            Log.log.debug("file list=#{filelist}")
            if filelist.length < 2 then
              raise OptionParser::InvalidArgument,"Missing source(s) and destination"
            end

            destination=filelist.pop

            send_result=api_node.call({:operation=>'POST',:subpath=>'files/download_setup',:json_params=>{ :transfer_requests => [ { :transfer_request => { :paths => filelist.map {|i| {:source=>i}; } } } ] }})
            if send_result[:data]['transfer_specs'][0].has_key?('error')
              raise send_result[:data]['transfer_specs'][0]['error']['user_message']
            end

            send_result[:data]['transfer_specs'].each{ |s|
              session=s['transfer_spec']
              srcList = session['paths'].map { |i| i['source']}
              results=@faspmanager.do_transfer(
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
          when :transfers
            command=self.class.get_next_arg_from_list(argv,'command',[ :list ])
            # ,:url_params=>{:active_only=>true}
            resp=api_node.call({:operation=>'GET',:subpath=>'ops/transfers',:headers=>{'Accept'=>'application/json'}})
            results=resp[:data]
          when :info
            resp=api_node.call({:operation=>'GET',:subpath=>'info',:headers=>{'Accept'=>'application/json'}})
            results=resp[:data]
          end

          return results
        end
      end
    end
  end # Cli
end # Asperalm
