require "asperalm/cli/plugin"
require "asperalm/version"
require "asperalm/log"
require 'yaml'
require 'text-table'
require 'pp'
require 'fileutils'

module Asperalm
  module Cli
    class Main < Plugin
      def opt_names; [:logtype,:loglevel,:config_name,:config_file]; end

      def get_logtypes; [:syslog,:stdout]; end

      def get_loglevels; Log.levels; end

      def get_formats; [:ruby,:text]; end

      def set_logtype(logtype)
        Log.setlogger(logtype)
        set_loglevel(:warn)
      end

      def set_loglevel(loglevel)
        Log.level = loglevel
      end

      def get_loglevel
        Log.log.level
      end

      def set_config_file(v)
        Log.log.debug "loading #{v}"
        @loaded_config=YAML.load_file(v)
        self.set_defaults(@loaded_config[:global])
      end

      def command_list
        Plugin.get_plugin_list.push(:config)
      end

      def set_options
        self.separator ""
        self.separator "DESCRIPTION"
        self.separator "\tUse Aspera application to perform operations on command line."
        self.separator "\tOAuth 2.0 is used for authentication in Files, Several authentication methods are provided."
        self.separator ""
        self.separator "EXAMPLES"
        self.separator "\t#{$PROGRAM_NAME} files events"
        self.separator "\t#{$PROGRAM_NAME} --log-level=debug --config-name=myfaspex send 200KB.1"
        self.separator "\t#{$PROGRAM_NAME} -ntj files set_client_key LA-8RrEjw @file:data/myid"
        self.separator "\nSPECIAL OPTION VALUES\n\tif an option value begins with @env: or @file:, value is taken from env var or file"
        self.separator ""
        self.add_opt_list(:loglevel,"Log level",'-lTYPE','--log-level=TYPE')
        self.add_opt_list(:logtype,"log method",'-qTYPE','--logger=TYPE')
        self.add_opt_simple(:config_file,"-fSTRING", "--config-file=STRING","read parameters from file in JSON format")
        self.add_opt_simple(:config_name,"-nSTRING", "--config-name=STRING","name of configuration in config file")
        self.add_opt_on(:rest_debug,"-r", "--rest-debug","more debug for HTTP calls") { Rest.set_debug(true) }
        self.set_option(:format,:text)
        self.add_opt_list(:format,"output format",'--format=TYPE')
      end

      def dojob(command,argv)
        case command
        when :config
          subcommand=self.class.get_next_arg_from_list(argv,'action',[:ls,:init])
          case subcommand
          when :init
            raise StandardError,"Folder already exists: #{$PROGRAM_FOLDER}" if Dir.exist?($PROGRAM_FOLDER)
            FileUtils::mkdir_p($PROGRAM_FOLDER)
            sample_config={
              :global=>{"default"=>{:loglevel=>:warn}},
              :files=>{
              "default"=>{:auth=>:jwt, :url=>"https://myorg.asperafiles.com", :client_id=>"MyClientId", :client_secret=>"MySecretMySecretMySecretMySecretMySecretMySecretMySecretMySecretMySecret", :private_key=>"@file:~/.aspera/aslmcli/filesapikey", :username=>"user@example.com"},
              "web"=>{:auth=>:web, :url=>"https://myorg.asperafiles.com", :client_id=>"MyClientId", :client_secret=>"MySecretMySecretMySecretMySecretMySecretMySecretMySecretMySecretMySecret", :redirect_uri=>"http://local.connectme.us:12345"}
              },:faspex=>{
              "default"=>{:url=>"https://myfaspex.mycompany.com/aspera/faspex", :username=>"admin", :password=>"MyP@ssw0rd"},
              "app2"=>{:url=>"https://faspex.other.com/aspera/faspex", :username=>"john@example", :password=>"yM7FmjfGN$J4"}
              },:shares=>{"default"=>{:url=>"https://10.25.0.6", :username=>"admin", :password=>"MyP@ssw0rd"}
              },:node=>{"default"=>{:url=>"https://10.25.0.8:9092", :username=>"node_user", :password=>"MyP@ssw0rd", :transfer_filter=>"t['status'].eql?('completed') and t['start_spec']['remote_user'].eql?('faspex')", :file_filter=>"f['status'].eql?('completed') and 0 != f['size'] and t['start_spec']['direction'].eql?('send')"}
              }, :console=>{"default"=>{:url=>"https://console.myorg.com/aspera/console", :username=>"admin", :password=>"xxxxx"}}
            }
            File.write($DEFAULT_CONFIG_FILE,sample_config.to_yaml)
            return "initialized: #{$PROGRAM_FOLDER}"
          when :ls
            sections=Plugin.get_plugin_list.unshift(:global)
            if argv.empty?
              # just list plugins
              results={ :fields => ['plugin'], :values=>sections.map { |i| { 'plugin' => i.to_s } } }
            else
              plugin=self.class.get_next_arg_from_list(argv,'plugin',sections)
              names=@loaded_config[plugin].keys.map { |i| i.to_sym }
              if argv.empty?
                # list names for tool
                results={ :fields => ['name'], :values=>names.map { |i| { 'name' => i.to_s } } }
              else
                # list parameters
                configname=self.class.get_next_arg_from_list(argv,'config',names)
                results={ :fields => ['param','value'], :values=>@loaded_config[plugin][configname.to_s].keys.map { |i| { 'param' => i.to_s, 'value' => @loaded_config[plugin][configname.to_s][i] } } }
              end
            end
          end
        else
          # execute plugin
          default_config=@loaded_config[command][self.get_option_mandatory(:config_name)] if !@loaded_config.nil? and @loaded_config.has_key?(command)
          application=Plugin.new_plugin(command)
          results=application.go(argv,default_config)
        end
        if results.is_a?(Hash) and results.has_key?(:values) and results.has_key?(:fields) then
          case self.get_option_mandatory(:format)
          when :ruby
            puts PP.pp(results[:values],'')
          when :text
            #results[:values].each { |i| i.select! { |k| results[:fields].include?(k) } }
            rows=results[:values].map{ |r| results[:fields].map { |c| r[c].to_s } }
            puts Text::Table.new(:head => results[:fields], :rows => rows, :vertical_boundary  => '.', :horizontal_boundary => ':', :boundary_intersection => ':')
            #Formatador.display_compact_table(results[:values],results[:fields])
          end
        else
          if results.is_a?(String)
            $stdout.write(results)
          elsif results.nil?
            Log.log.debug("result=nil")
          else
            puts ">result>#{PP.pp(results,'')}"
          end
        end
        if !argv.empty?
          raise OptionParser::InvalidArgument,"unprocessed values: #{argv}"
        end
        return ""
      end

      #################################
      # MAIN
      #--------------------------------
      $PROGRAM_NAME = 'aslmcli'
      $ASPERA_HOME_FOLDERNAME='.aspera'
      $ASPERA_HOME_FOLDERPATH=File.join(Dir.home,$ASPERA_HOME_FOLDERNAME)
      $PROGRAM_FOLDER=File.join($ASPERA_HOME_FOLDERPATH,$PROGRAM_NAME)
      $DEFAULT_CONFIG_FILE=File.join($PROGRAM_FOLDER,'config.yaml')

      def self.start
        defaults={
          :logtype => :stdout,
          :loglevel => :warn,
          :config_name => 'default'
        }
        config_file=$DEFAULT_CONFIG_FILE
        Log.log.debug("config file=#{config_file}")
        defaults[:config_file]=config_file if File.exist?(config_file)
        tool=self.new
        begin
          tool.go(ARGV,defaults)
          rescue StandardError => e
            tool.exit_with_usage(e)
        end
      end
    end
  end
end
