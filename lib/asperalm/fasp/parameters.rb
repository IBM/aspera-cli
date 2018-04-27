require 'securerandom'
require "asperalm/log"
require "base64"
require "json"

module Asperalm
  module Fasp
    # translate transfer specification to ascp parameter list
    class Parameters
      # temp files are created here, change to go elsewhere
      @@file_list_folder='.'
      def self.file_list_folder; @@file_list_folder;end

      def self.file_list_folder=(v); @@file_list_folder=v;end

      def initialize(transfer_spec)
        @transfer_spec=transfer_spec.clone # shallow copy is sufficient
        @result_env={}
        @result_args=[]
        @used_ts_keys=[]
        @created_files=[]
      end

      def compute_args
        transfer_spec_to_args_env
      end

      def cleanup_files
        @created_files.each do |filepath|
          File.delete(filepath)
        end
        @created_files=[]
      end

      private

      BOOLEAN_CLASSES=[TrueClass,FalseClass]

      def temp_filelist_path
        FileUtils::mkdir_p(@@file_list_folder) unless Dir.exist?(@@file_list_folder)
        new_file=File.join(@@file_list_folder,SecureRandom.uuid)
        @created_files.push(new_file)
        return new_file
      end

      # Process a parameter from transfer specification
      # @param ts_name : key in transfer spec
      # @param option_type : type of processing
      # @param options : options for type
      def process_param(ts_name,option_type,options={})
        options[:mandatory]||=false
        options[:accepted_types]||=option_type.eql?(:opt_without_arg)?[*BOOLEAN_CLASSES]:[String]

        # check mandatory parameter (nil is valid value)
        raise Fasp::Error.new("mandatory parameter: #{ts_name}") if options[:mandatory] and !@transfer_spec.has_key?(ts_name)
        parameter_value=@transfer_spec[ts_name]
        parameter_value=options[:default] if parameter_value.nil? and !options[:default].nil?
        raise Fasp::Error.new("#{ts_name} is : #{parameter_value.class} (#{parameter_value}), shall be #{options[:accepted_types]}, ") unless parameter_value.nil? or options[:accepted_types].inject(false){|m,v|m or parameter_value.is_a?(v)}
        @used_ts_keys.push(ts_name)

        # process only non-nil values
        return nil if parameter_value.nil?
        #Log.log.debug("process_param #{ts_name} #{parameter_value} #{options}")

        if options.has_key?(:translate_values)
          # translate using conversion table
          new_value=options[:translate_values][parameter_value]
          raise "unsupported value: #{parameter_value}" if new_value.nil?
          parameter_value=new_value
        end
        raise "unsupported value: #{parameter_value}" unless options[:accepted_values].nil? or options[:accepted_values].include?(parameter_value)
        if options[:encode]
          newvalue=options[:encode].call(parameter_value)
          raise Fasp::Error.new("unsupported #{ts_name}: #{parameter_value}") if newvalue.nil?
          parameter_value=newvalue
        end

        case option_type
        when :ignore
          return
        when :get_value
          return parameter_value
        when :envvar
          # define ascp parameter in env var from transfer spec
          @result_env[options[:variable]] = parameter_value
        when :opt_without_arg # if present and true : just add option without value
          add_param=false
          case parameter_value
          when false# nothing to put on command line, no creation by default
          when true; add_param=true
          else raise Fasp::Error.new("unsupported #{ts_name}: #{parameter_value}")
          end
          add_param=!add_param if options[:add_on_false]
          add_ascp_options([options[:option_switch]]) if add_param
        when :opt_with_arg
          #parameter_value=parameter_value.to_s if parameter_value.is_a?(Integer)
          parameter_value=[parameter_value] unless parameter_value.is_a?(Array)
          # if transfer_spec value is an array, applies option many times
          parameter_value.each{|v|add_ascp_options([options[:option_switch],v])}
        else
          raise "Error"
        end
      end

      # add options directly to ascp command line
      def add_ascp_options(options)
        return if options.nil?
        options.each{|o|@result_args.push(o.to_s)}
      end

      # translate transfer spec to env vars and command line arguments for ascp
      # NOTE: parameters starting with "EX_" (extended) are not standard
      def transfer_spec_to_args_env
        # some ssh credentials are required to avoid interactive password input
        if !@transfer_spec.has_key?('remote_password') and
        !@transfer_spec.has_key?('EX_ssh_key_value') and
        !@transfer_spec.has_key?('EX_ssh_key_paths') then
          raise Fasp::Error.new('required: ssh key (value or path) or password')
        end

        # parameters with env vars
        process_param('remote_password',:envvar,:variable=>'ASPERA_SCP_PASS')
        process_param('token',:envvar,:variable=>'ASPERA_SCP_TOKEN')
        process_param('cookie',:envvar,:variable=>'ASPERA_SCP_COOKIE')
        process_param('EX_ssh_key_value',:envvar,:variable=>'ASPERA_SCP_KEY')
        process_param('EX_at_rest_password',:envvar,:variable=>'ASPERA_SCP_FILEPASS')
        process_param('EX_proxy_password',:envvar,:variable=>'ASPERA_PROXY_PASS')

        process_param('create_dir',:opt_without_arg,:option_switch=>'-d')
        process_param('precalculate_job_size',:opt_without_arg,:option_switch=>'--precalculate-job-size')
        process_param('EX_quiet',:opt_without_arg,:option_switch=>'-q')

        process_param('cipher',:opt_with_arg,:option_switch=>'-c',:accepted_types=>[String],:translate_values=>{'aes128'=>'aes128','aes-128'=>'aes128','aes192'=>'aes192','aes-192'=>'aes192','aes256'=>'aes256','aes-256'=>'aes256','none'=>'none'})
        process_param('resume_policy',:opt_with_arg,:option_switch=>'-k',:accepted_types=>[String],:default=>'sparse_csum',:translate_values=>{'none'=>0,'attrs'=>1,'sparse_csum'=>2,'full_csum'=>3})
        process_param('direction',:opt_with_arg,:option_switch=>'--mode',:accepted_types=>[String],:translate_values=>{'receive'=>'recv','send'=>'send'})
        process_param('remote_user',:opt_with_arg,:option_switch=>'--user',:accepted_types=>[String])
        process_param('remote_host',:opt_with_arg,:option_switch=>'--host',:accepted_types=>[String])
        process_param('ssh_port',:opt_with_arg,:option_switch=>'-P',:accepted_types=>[Integer])
        process_param('fasp_port',:opt_with_arg,:option_switch=>'-O',:accepted_types=>[Integer])
        process_param('dgram_size',:opt_with_arg,:option_switch=>'-Z',:accepted_types=>[Integer])
        process_param('target_rate_kbps',:opt_with_arg,:option_switch=>'-l',:accepted_types=>[Integer])
        process_param('min_rate_kbps',:opt_with_arg,:option_switch=>'-m',:accepted_types=>[Integer])
        process_param('rate_policy',:opt_with_arg,:option_switch=>'--policy',:accepted_types=>[String])
        process_param('http_fallback',:opt_with_arg,:option_switch=>'-y',:accepted_types=>[String,*BOOLEAN_CLASSES],:translate_values=>{'force'=>'F',true=>1,false=>0})
        process_param('http_fallback_port',:opt_with_arg,:option_switch=>'-t',:accepted_types=>[Integer])
        process_param('source_root',:opt_with_arg,:option_switch=>'--source-prefix64',:accepted_types=>[String],:encode=>lambda{|prefix|Base64.strict_encode64(prefix)})
        process_param('sshfp',:opt_with_arg,:option_switch=>'--check-sshfp',:accepted_types=>[String])
        process_param('symlink_policy',:opt_with_arg,:option_switch=>'--symbolic-links',:accepted_types=>[String])
        process_param('overwrite',:opt_with_arg,:option_switch=>'--overwrite',:accepted_types=>[String])

        process_param('EX_fallback_key',:opt_with_arg,:option_switch=>'-Y',:accepted_types=>[String])
        process_param('EX_fallback_cert',:opt_with_arg,:option_switch=>'-I',:accepted_types=>[String])
        process_param('EX_fasp_proxy_url',:opt_with_arg,:option_switch=>'--proxy',:accepted_types=>[String])
        process_param('EX_http_proxy_url',:opt_with_arg,:option_switch=>'-x',:accepted_types=>[String])
        process_param('EX_ssh_key_paths',:opt_with_arg,:option_switch=>'-i',:accepted_types=>[Array])
        process_param('EX_http_transfer_jpeg',:opt_with_arg,:option_switch=>'-j',:accepted_types=>[Integer])

        # TODO: manage those parameters, some are for connect only ? node api ?
        process_param('target_rate_cap_kbps',:ignore,:accepted_types=>[Integer])
        process_param('target_rate_percentage',:ignore,:accepted_types=>[String]) # -wf -l<rate>p
        process_param('min_rate_cap_kbps',:ignore,:accepted_types=>[Integer])
        process_param('rate_policy_allowed',:ignore,:accepted_types=>[String])
        process_param('fasp_url',:ignore,:accepted_types=>[String])
        process_param('lock_rate_policy',:ignore,:accepted_types=>[*BOOLEAN_CLASSES])
        process_param('lock_min_rate',:ignore,:accepted_types=>[*BOOLEAN_CLASSES])
        process_param('lock_target_rate',:ignore,:accepted_types=>[*BOOLEAN_CLASSES])
        process_param('authentication',:ignore,:accepted_types=>[String]) # = token
        process_param('https_fallback_port',:ignore,:accepted_types=>[Integer]) # same as http fallback, option -t ?
        process_param('content_protection',:ignore,:accepted_types=>[String])
        process_param('cipher_allowed',:ignore,:accepted_types=>[String])
        process_param('multi_session',:ignore,:accepted_types=>[Integer])
        process_param('multi_session_threshold',:ignore,:accepted_types=>[Integer])

        # optional tags (  additional option to generate: {:space=>' ',:object_nl=>' ',:space_before=>'+',:array_nl=>'1'}  )
        process_param('tags',:opt_with_arg,:option_switch=>'--tags64',:accepted_types=>[Hash],:encode=>lambda{|tags|Base64.strict_encode64(JSON.generate(tags))})

        # optional args, at the end to override previous ones (to allow override)
        add_ascp_options(process_param('EX_ascp_args',:get_value,:accepted_types=>[Array]))

        # destination will be base64 encoded, put before path arguments
        add_ascp_options(['--dest64'])

        # source list: TODO : use file list or file pair list, avoid command line lists
        add_ascp_options(process_param('paths',:get_value,:accepted_types=>[Array],:mandatory=>true).map{|i|i['source']})

        # destination, use base64 encoding, as defined previously
        add_ascp_options([Base64.strict_encode64(process_param('destination_root',:get_value,:accepted_types=>[String],:mandatory=>true))])

        # symbol must be index of Installation.paths
        ascp_version=process_param('use_ascp4',:get_value) ? :ascp4 : :ascp

        # warn about non translated arguments
        @transfer_spec.each_pair{|key,val|Log.log.error("unhandled parameter: #{key} = \"#{val}\"") if !@used_ts_keys.include?(key)}

        return {:args=>@result_args,:env=>@result_env,:ascp_version=>ascp_version}
      end

      def self.yes_to_true(value)
        case value
        when 'yes'; return true
        when 'no'; return false
        end
        raise "unsupported value: #{value}"
      end

    end # Parameters
  end # Fasp
end # Asperalm
