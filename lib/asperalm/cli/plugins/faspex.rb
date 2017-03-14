require 'optparse'
require 'pp'
require 'asperalm/rest'
require 'asperalm/colors'
require 'asperalm/opt_parser'
require 'xmlsimple'
require 'formatador'

module Asperalm
  module Cli
    module Plugins
      class Faspex
        def opt_names; [:url,:username,:password]; end

        def get_pkgboxs; [:inbox,:sent,:archive]; end

        @pkgbox=:inbox
        attr_accessor :logger
        attr_accessor :faspmanager

        def initialize(logger)
          @logger=logger
        end

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
          return Rest.new(@logger,@opt_parser.get_option_mandatory(:url),{:basic_auth=>{:user=>@opt_parser.get_option_mandatory(:username), :password=>@opt_parser.get_option_mandatory(:password)}})
        end

        def go(argv,defaults)
          begin
            @pkgbox=:inbox
            @opt_parser = OptParser.new(self)
            @opt_parser.set_defaults(defaults)
            @opt_parser.banner = "NAME\n\tascli -- a command line tool for Aspera Applications\n\n"
            @opt_parser.separator "SYNOPSIS"
            @opt_parser.separator "\tascli ... faspex [OPTIONS] COMMAND [ARGS]..."
            @opt_parser.separator ""
            @opt_parser.separator "OPTIONS"
            @opt_parser.add_opt_simple(:url,"-wURI", "--url=URI","URL of application, e.g. http://org.asperafiles.com")
            @opt_parser.add_opt_simple(:username,"-uSTRING", "--username=STRING","username to log in")
            @opt_parser.add_opt_simple(:password,"-pSTRING", "--password=STRING","password")
            @opt_parser.add_opt_list(:pkgbox,"package box",'--box=TYPE')
            @opt_parser.on("--raw","display raw result") { @option_raw_result=true }
            @opt_parser.on_tail("-h", "--help", "Show this message") { @opt_parser.exit_with_usage }
            @opt_parser.parse_ex!(argv)

            results=''

            command=OptParser.get_next_arg_from_list(argv,'command',[ :send, :recv, :recv_publink, :packages ])

            case command
            when :send
              api_faspex=get_faspex_authenticated_api

              filelist = argv
              @logger.info("file list=#{filelist}")
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
                pkguuid=OptParser.get_next_arg_value(argv,"Package sequence ID")
                all_inbox_xml=api_faspex.call({:operation=>'GET',:subpath=>"#{@pkgbox.to_s}.atom",:headers=>{'Accept'=>'application/xml'}})[:http].body
                allinbox=XmlSimple.xml_in(all_inbox_xml, {"ForceArray" => true})
                results=allinbox['entry'].select { |e| pkguuid.eql?(e['id'].first)}
                if results.length != 1
                  raise "no such uuid"
                end
                results=results.first
              else
                delivid=OptParser.get_next_arg_value(argv,"Package delivery ID")
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
              thelink=OptParser.get_next_arg_value(argv,"Faspex public URL for a package")
              link_data=get_link_data(thelink)
              # unauthenticated API
              api_faspex=Rest.new(@logger,link_data[:faspex_base_url],{})
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
              if @option_raw_result.nil? then
                if all_inbox_data.has_key?('entry')
                  results=all_inbox_data['entry'].map { |e| default_fields.inject({}) { |m,v|
                      if "recipient_delivery_id".eql?(v) then
                        m[v.to_sym] = e['to'][0][v][0]
                      else
                        m[v.to_sym] = e[v][0];
                      end
                      m } }
                  Formatador.display_table(results)
                end
                results=nil
              end
            end # command

            if ! results.nil? then
              puts PP.pp(results,'')
            end

          rescue OptionParser::InvalidArgument => e
            STDERR.puts "ERROR:".bg_red().gray()+" #{e}\n\n"
            @opt_parser.exit_with_usage
          end
          return
        end
      end
    end
  end # Cli
end # Asperalm
