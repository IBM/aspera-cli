require 'asperalm/cli/plugin'

module Asperalm
  module Cli
    module Plugins
      class Faspex < Plugin
        def opt_names; [:url,:username,:password]; end

        def get_pkgboxs; [:inbox,:sent,:archive]; end

        def command_list; [ :send, :recv, :recv_publink, :packages ]; end

        @pkgbox=:inbox
        attr_accessor :faspmanager

        # extract elements from anonymous faspex link
        def get_link_data(email)
          package_match = email.match(/((http[^"]+)\/(external_deliveries\/([^?]+)))\?passcode=([^"]+)/)
          if package_match.nil? then
            raise OptionParser::InvalidArgument, "string does not match Faspex url"
          end
          return {
            :uri => package_match[0],
            :url => package_match[1],
            :faspex_base_url =>  package_match[2],
            :subpath => package_match[3],
            :delivery_id => package_match[4],
            :passcode => package_match[5]
          }
        end

        # extract transfer information from xml returned by faspex
        def uri_to_transferspec(fasplink)
          transfer_uri=URI.parse(fasplink)
          transfer_data=URI::decode_www_form(transfer_uri.query).to_h
          transfer_params={}
          transfer_data.each { |i| transfer_params[i[0]] = i[1] }
          transfer_params['remote_host']=transfer_uri.host
          transfer_params['remote_user']=transfer_uri.user
          transfer_params['srcList']=[URI.decode_www_form_component(transfer_uri.path)]
          return transfer_params
        end

        def xmlentry_to_transferspec(entry)
          fasplink=(entry['link'].select{|e| e["rel"].eql?("package")}).first["href"]
          return uri_to_transferspec(fasplink)
        end

        def get_faspex_authenticated_api
          return Rest.new(self.get_option_mandatory(:url),{:basic_auth=>{:user=>self.get_option_mandatory(:username), :password=>self.get_option_mandatory(:password)}})
        end

        def init_defaults
          @pkgbox=:inbox
        end

        def set_options
          self.add_opt_simple(:url,"-wURI", "--url=URI","URL of application, e.g. http://org.asperafiles.com")
          self.add_opt_simple(:username,"-uSTRING", "--username=STRING","username to log in")
          self.add_opt_simple(:password,"-pSTRING", "--password=STRING","password")
          self.add_opt_list(:pkgbox,"package box",'--box=TYPE')
        end

        def dojob(command,argv)
          case command
          when :send
            api_faspex=get_faspex_authenticated_api

            filelist = argv
            Log.log.info("file list=#{filelist}")
            if filelist.empty? then
              raise OptionParser::InvalidArgument,"missing file list"
            end

            send_result=api_faspex.call({:operation=>'POST',:subpath=>'send',:json_params=>{"delivery"=>{"use_encryption_at_rest"=>false,"note"=>"this file was sent by a script","sources"=>[{"paths"=>filelist}],"title"=>"File sent by script","recipients"=>["aspera.user1@gmail.com"],"send_upload_result"=>true}},:headers=>{'Accept'=>'application/json'}})
            send_result[:data]['xfer_sessions'].each { |session|
              @faspmanager.do_transfer(
              :mode    => :send,
              :dest    => session['destination_root'],
              :user    => session['remote_user'],
              :host    => session['remote_host'],
              :token   => session['token'],
              :cookie  => session['cookie'],
              :tags    => session['tags'],
              :srcList => filelist,
              :rawArgs => [ '-P', '33001', '-d', '-q', '--ignore-host-key', '-k', '2', '--save-before-overwrite','--partial-file-suffix=.partial' ],
              :retries => 10,
              :use_aspera_key => true)
            }
          when :recv
            api_faspex=get_faspex_authenticated_api
            if true
              pkguuid=self.class.get_next_arg_value(argv,"Package UUID")
              all_inbox_xml=api_faspex.call({:operation=>'GET',:subpath=>"#{@pkgbox.to_s}.atom",:headers=>{'Accept'=>'application/xml'}})[:http].body
              allinbox=XmlSimple.xml_in(all_inbox_xml, {"ForceArray" => true})
              results=allinbox['entry'].select { |e| pkguuid.eql?(e['id'].first)}
              if results.length != 1
                raise "no such uuid"
              end
              results=results.first
            else
              delivid=self.class.get_next_arg_value(argv,"Package delivery ID")
              entry_xml=api_faspex.call({:operation=>'GET',:subpath=>"received/#{delivid}",:headers=>{'Accept'=>'application/xml'}})[:http].body
              results=XmlSimple.xml_in(entry_xml, {"ForceArray" => true})
            end
            transfer_params=xmlentry_to_transferspec(results)
            @faspmanager.do_transfer(
            :mode    => :recv,
            :dest    => '.',
            :user    => transfer_params['remote_user'],
            :host    => transfer_params['remote_host'],
            :token   => transfer_params['token'],
            :cookie  => transfer_params['cookie'],
            :tags64  => transfer_params['tags64'],
            :srcList => transfer_params['srcList'],
            :rawArgs => [ '-P', '33001', '-d', '-q', '--ignore-host-key', '-k', '2', '--save-before-overwrite','--partial-file-suffix=.partial' ],
            :retries => 10,
            :use_aspera_key => true)
          when :recv_publink
            thelink=self.class.get_next_arg_value(argv,"Faspex public URL for a package")
            link_data=get_link_data(thelink)
            # unauthenticated API
            api_faspex=Rest.new(link_data[:faspex_base_url],{})
            pkgdatares=api_faspex.call({:operation=>'GET',:subpath=>link_data[:subpath],:url_params=>{:passcode=>link_data[:passcode]},:headers=>{'Accept'=>'application/xml'}})
            transfer_params=xmlentry_to_transferspec(XmlSimple.xml_in(pkgdatares[:http].body, {"ForceArray" => false}))
            results=transfer_params
            @faspmanager.do_transfer(
            :mode    => :recv,
            :dest    => '.',
            :user    => transfer_params['remote_user'],
            :host    => transfer_params['remote_host'],
            :token   => transfer_params['token'],
            :cookie  => transfer_params['cookie'],
            :tags64  => transfer_params['tags64'],
            :srcList => transfer_params['srcList'],
            :rawArgs => [ '-P', '33001', '-d', '-q', '--ignore-host-key', '-k', '2', '--save-before-overwrite','--partial-file-suffix=.partial' ],
            :retries => 10,
            :use_aspera_key => true)
          when :packages
            default_fields=['recipient_delivery_id','title','id']
            api_faspex=get_faspex_authenticated_api
            all_inbox_xml=api_faspex.call({:operation=>'GET',:subpath=>"#{@pkgbox.to_s}.atom",:headers=>{'Accept'=>'application/xml'}})[:http].body
            all_inbox_data=XmlSimple.xml_in(all_inbox_xml, {"ForceArray" => true})
            if all_inbox_data.has_key?('entry')
              values=all_inbox_data['entry'].map { |e| default_fields.inject({}) { |m,v|
                  if "recipient_delivery_id".eql?(v) then
                    if e['to'][0].has_key?(v)
                      m[v] = e['to'][0][v][0]
                    else
                      m[v] = 'unknown'
                    end
                  else
                    m[v] = e[v][0];
                  end
                  m } }
              return {:fields=>default_fields,:values=>values}
            end
          end # command
        end
      end
    end
  end # Cli
end # Asperalm
