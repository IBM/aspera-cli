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
        def self.get_link_data(email)
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
        # only external users get token in link (see: <faspex>/app/views/delivery/_content.xml.builder)
        def self.uri_to_transferspec(fasplink)
          transfer_uri=URI.parse(fasplink)
          transfer_data=URI::decode_www_form(transfer_uri.query).to_h
          transfer_params={}
          transfer_data.each { |i| transfer_params[i[0]] = i[1] }
          transfer_params['remote_host']=transfer_uri.host
          transfer_params['remote_user']=transfer_uri.user
          transfer_params['srcList']=[URI.decode_www_form_component(transfer_uri.path)]
          return transfer_params
        end

        def self.get_fasp_uri_from_entry(entry)
          return (entry['link'].select{|e| e["rel"].eql?("package")}).first["href"]
        end

        def get_faspex_authenticated_api
          return Rest.new(self.get_option_mandatory(:url),{:basic_auth=>{:user=>self.get_option_mandatory(:username), :password=>self.get_option_mandatory(:password)}})
        end

        def set_options
          self.add_opt_simple(:url,"-wURI", "--url=URI","URL of application, e.g. http://org.asperafiles.com")
          self.add_opt_simple(:username,"-uSTRING", "--username=STRING","username to log in")
          self.add_opt_simple(:password,"-pSTRING", "--password=STRING","password")
          @pkgbox=:inbox
          self.add_opt_list(:pkgbox,"package box",'--box=TYPE')
        end

        def dojob(command,argv)
          case command
          when :send
            filelist = self.class.get_remaining_arguments(argv,"file list")
            api_faspex=get_faspex_authenticated_api
            send_result=api_faspex.call({:operation=>'POST',:subpath=>'send',:json_params=>{"delivery"=>{"use_encryption_at_rest"=>false,"note"=>"this file was sent by a script","sources"=>[{"paths"=>filelist}],"title"=>"File sent by script","recipients"=>["aspera.user1@gmail.com"],"send_upload_result"=>true}},:headers=>{'Accept'=>'application/json'}})[:data]
            if send_result.has_key?('error')
              raise OptionParser::InvalidArgument,"#{send_result['error']['user_message']} / #{send_result['error']['internal_message']}"
            end
            send_result['xfer_sessions'].each { |session|
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
              package_entries=[]
              if allinbox.has_key?('entry')
                package_entries=allinbox['entry'].select { |e| pkguuid.eql?(e['id'].first) }
              end
              if package_entries.length != 1
                raise OptionParser::InvalidArgument,"no such uuid"
              end
              package_entry=package_entries.first
            else
              delivid=self.class.get_next_arg_value(argv,"Package delivery ID")
              entry_xml=api_faspex.call({:operation=>'GET',:subpath=>"received/#{delivid}",:headers=>{'Accept'=>'application/xml'}})[:http].body
              package_entry=XmlSimple.xml_in(entry_xml, {"ForceArray" => true})
            end
            # NOTE: only external users have token in faspe: link !
            transfer_uri=self.class.get_fasp_uri_from_entry(package_entry)
            transfer_params=self.class.uri_to_transferspec(transfer_uri)
            if !transfer_params.has_key?('token')
              xmlpayload='<?xml version="1.0" encoding="UTF-8"?><url-list xmlns="http://schemas.asperasoft.com/xml/url-list"><url href="'+transfer_uri+'"/></url-list>'
              transfer_params['token']=api_faspex.call({:operation=>'POST',:subpath=>"issue-token?direction=down",:headers=>{'Accept'=>'text/plain','Content-Type'=>'application/vnd.aspera.url-list+xml'},:text_body_params=>xmlpayload})[:http].body
            end
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
            transfer_params=self.class.uri_to_transferspec(self.class.get_fasp_uri_from_entry(XmlSimple.xml_in(pkgdatares[:http].body, {"ForceArray" => false})))
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
