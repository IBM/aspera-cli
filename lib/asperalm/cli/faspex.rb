require 'optparse'
require 'pp'
require 'asperalm/rest'
require 'asperalm/colors'
require 'asperalm/opt_parser'

module Asperalm
  module Cli
    class Faspex
      def opt_names; [:url,:username,:password]; end

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
      def xml_to_transferspec(xml)
        xmldata=XmlSimple.xml_in(xml, {"ForceArray" => false})
        fasplink=(xmldata['link'].select{|e| e["rel"].eql?("package")}).first["href"]
        transfer_uri=URI.parse(fasplink)
        transfer_data=URI::decode_www_form(transfer_uri.query).to_h
        transfer_params={}
        transfer_data.each { |i| transfer_params[i[0]] = i[1] }
        transfer_params['remote_host']=transfer_uri.host
        transfer_params['remote_user']=transfer_uri.user
        transfer_params['srcList']=[URI.decode_www_form_component(transfer_uri.path)]
        return transfer_params
      end

      def go(argv,defaults)
        begin
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
          @opt_parser.on("--raw","display raw result") { @raw_result=true }
          @opt_parser.on_tail("-h", "--help", "Show this message") { @opt_parser.exit_with_usage }
          @opt_parser.parse_ex!(argv)

          results=''

          command=OptParser.get_next_arg_from_list(argv,'command',[ :send, :recv_publink, :packages ])

          case command
          when :send
            api_faspex=Rest.new(@logger,@opt_parser.get_option_mandatory(:url)+'/aspera/faspex',{:basic_auth=>{:user=>@opt_parser.get_option_mandatory(:username), :password=>@opt_parser.get_option_mandatory(:password)}})

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
          when :recv_publink
            require 'xmlsimple'
            thelink=OptParser.get_next_arg_value(argv,"Faspex public URL for a package")
            link_data=get_link_data(thelink)
            api_faspex=Rest.new(@logger,link_data[:faspex_base_url],{})
            pkgdatares=api_faspex.call({:operation=>'GET',:subpath=>link_data[:subpath],:url_params=>{:passcode=>link_data[:passcode]},:headers=>{'Accept'=>'application/xml'}})
            transfer_params=xml_to_transferspec(pkgdatares[:http].body)
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
            require 'xmlsimple'
            require 'formatador'
            default_fields=['title','id']
            api_faspex=Rest.new(@logger,@opt_parser.get_option_mandatory(:url)+'/aspera/faspex',{:basic_auth=>{:user=>@opt_parser.get_option_mandatory(:username), :password=>@opt_parser.get_option_mandatory(:password)}})
            all_inbox_xml=api_faspex.call({:operation=>'GET',:subpath=>"inbox.atom"})[:http].body
            results=XmlSimple.xml_in(all_inbox_xml, {"ForceArray" => true})
            if @raw_result.nil? then
              results=results['entry'].map { |e| default_fields.inject({}) { |m,v| m[v.to_sym] = e[v][0]; m } }
              Formatador.display_table(results)
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
  end # Cli
end # Asperalm
