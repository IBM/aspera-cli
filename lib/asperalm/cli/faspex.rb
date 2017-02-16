require 'optparse'
require 'pp'
require 'aspera/rest'
require 'aspera/colors'
require 'aspera/opt_parser'

class CliFaspex
  def opt_names; [:url,:username,:password]; end

  attr_accessor :logger
  attr_accessor :faspmanager

  def initialize(logger)
    @logger=logger
  end

  def go(argv,defaults)
    begin
      @opt_parser = AsperaOptParser.new(self)
      @opt_parser.set_defaults(defaults)
      @opt_parser.banner = "NAME\n\t#{$0} -- a command line tool for Aspera Applications\n\n"
      @opt_parser.separator "SYNOPSIS"
      @opt_parser.separator "\t#{$0} ... faspex [OPTIONS] COMMAND [ARGS]..."
      @opt_parser.separator ""
      @opt_parser.separator "OPTIONS"
      @opt_parser.add_opt_simple(:url,"-wURI", "--url=URI","URL of application, e.g. http://org.asperafiles.com")
      @opt_parser.add_opt_simple(:username,"-uSTRING", "--username=STRING","username to log in")
      @opt_parser.add_opt_simple(:password,"-pSTRING", "--password=STRING","password")
      @opt_parser.on_tail("-h", "--help", "Show this message") { @opt_parser.exit_with_usage }
      @opt_parser.parse_ex!(argv)

      results=''

      command=AsperaOptParser.get_next_arg_from_list(argv,'command',[ :send ])

      filelist = argv
      @logger.info("file list=#{filelist}")
      if filelist.empty? then
        raise OptionParser::InvalidArgument,"missing file list"
      end

      api_faspex=Rest.new(@logger,@opt_parser.get_option_mandatory(:url)+'/aspera/faspex',{:basic_auth=>{:user=>@opt_parser.get_option_mandatory(:username), :password=>@opt_parser.get_option_mandatory(:password)}})

      case command
      when :send
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
      end

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
