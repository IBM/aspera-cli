require 'optparse'
require 'pp'
require 'asperalm/rest'
require 'asperalm/colors'
require 'asperalm/opt_parser'
require 'formatador'

module Asperalm
  module Cli
    module Plugins
      class Console
        def opt_names; [:url,:username,:password]; end

        attr_accessor :logger
        attr_accessor :faspmanager

        def initialize(logger)
          @logger=logger
        end

        def go(argv,defaults)
          begin
            @opt_parser = OptParser.new(self)
            @opt_parser.set_defaults(defaults)
            @opt_parser.banner = "NAME\n\t#{$0} -- a command line tool for Aspera Applications\n\n"
            @opt_parser.separator "SYNOPSIS"
            @opt_parser.separator "\t#{$0} ... node [OPTIONS] COMMAND [ARGS]..."
            @opt_parser.separator ""
            @opt_parser.separator "OPTIONS"
            @opt_parser.add_opt_simple(:url,"-wURI", "--url=URI","URL of application, e.g. http://org.asperafiles.com")
            @opt_parser.add_opt_simple(:username,"-uSTRING", "--username=STRING","username to log in")
            @opt_parser.add_opt_simple(:password,"-pSTRING", "--password=STRING","password")
            @opt_parser.on_tail("-h", "--help", "Show this message") { @opt_parser.exit_with_usage }
            @opt_parser.parse_ex!(argv)

            results=''

            command=OptParser.get_next_arg_from_list(argv,'command',[ :transfers ])

            api_console=Rest.new(@logger,@opt_parser.get_option_mandatory(:url),{:basic_auth=>{:user=>@opt_parser.get_option_mandatory(:username), :password=>@opt_parser.get_option_mandatory(:password)}})

            case command
            when :transfers
              default_fields=['id','contact','name','status']
              command=OptParser.get_next_arg_from_list(argv,'command',[ :list ])
              resp=api_console.call({:operation=>'GET',:subpath=>'transfers',:headers=>{'Accept'=>'application/json'},:url_params=>{'from'=>(Time.now - 3600).strftime("%Y-%m-%d %H:%M:%S")}})
              results=resp[:data]
              results.each { |i| i.select! { |k| default_fields.include?(k) } }
              Formatador.display_table(results,default_fields)
            end

            if ! results.nil? then
              puts PP.pp(results,'')
              #puts results
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
