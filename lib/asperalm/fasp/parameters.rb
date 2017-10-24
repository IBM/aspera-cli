require "asperalm/log"

module Asperalm
  module Fasp
    # translate transfer spec to ascp parameter list
    class Parameters
      def initialize(transfer_spec)
        @state={
          :transfer_spec=>transfer_spec,
          :result => {
          :args=>[],
          :env=>{}
          },
          :used_names=>[]
        }
      end

      def compute_args
        transfer_spec_to_args_env
      end

      private

      RESUME_POLICIES=['none','attrs','sparse_csum','full_csum']

      # returns the value from transfer spec and mark parameter as used
      def use_parameter(ts_name,p_classes,mandatory=false)
        raise TransferError.new("mandatory parameter: #{ts_name}") if mandatory and !@state[:transfer_spec].has_key?(ts_name)
        raise TransferError.new("#{ts_name} is : #{@state[:transfer_spec][ts_name].class}, shall be #{p_classes}, ") unless @state[:transfer_spec][ts_name].nil? or p_classes.include?(@state[:transfer_spec][ts_name].class)
        @state[:used_names].push(ts_name)
        return @state[:transfer_spec][ts_name]
      end

      def ignore_parameter(ts_name,p_classes,mandatory=false)
        use_parameter(ts_name,p_classes,mandatory)
      end
      #alias_method(:ignore_parameter,:use_parameter)

      # define ascp parameter in env var from transfer spec
      def param_string_env(ts_name,env_name)
        value=use_parameter(ts_name,[String])
        @state[:result][:env][env_name] = value if !value.nil?
      end

      # parameter is added only if value is true
      # if positive==false, param added if value is false
      def set_param_boolean(ts_name,ascp_option,positive=true)
        value=use_parameter(ts_name,[TrueClass,FalseClass])
        add_param=false
        case value
        when nil,false# nothing to put on command line, no creation by default
        when true; add_param=true
        else raise TransferError.new("unsupported #{ts_name}: #{value}")
        end
        add_param=!add_param if !positive
        if add_param
          add_ascp_options(ascp_option)
        end
      end

      # ts_name : key in transfer spec
      # ascp_option : option on ascp command line
      # transform : transformation function for transfer spec value to option value
      # if transfer_spec value is an array, applies option many times
      def set_param_value(ts_name,ascp_option,p_classes,&transform)
        value=use_parameter(ts_name,p_classes)
        if !value.nil?
          if transform
            newvalue=transform.call(value)
            if newvalue.nil?
              raise TransferError.new("unsupported #{ts_name}: #{value}")
            else
              value=newvalue
            end
          end
          value=value.to_s if value.is_a?(Integer)
          value=[value] if value.is_a?(String)
          value.each{|v|add_ascp_options(ascp_option,v)}
        end
      end

      def set_param_list_num(ts_name,ascp_option,values,default)
        Log.log.debug("HERE: #{ts_name}".bg_red)
        value=use_parameter(ts_name,[String])
        value=default if value.nil?
        if !value.nil?
          numeric=values.find_index(value)
          if numeric.nil?
            raise TransferError.new("unsupported value #{value} for #{ts_name}, expecting #{values}")
          end
          add_ascp_options(ascp_option,numeric)
        end
      end
      
      def add_ascp_options(*options)
        @state[:result][:args].push(*options.map{|v|v.to_s})
      end

      # translate transfer spec to env vars and command line arguments for ascp
      # NOTE: parameters starting with "EX_" (extended) are not standard
      def transfer_spec_to_args_env
        # transformation  input, output, validation

        # some ssh credentials are required to avoid interactive password input
        if !@state[:transfer_spec].has_key?('password') and
        !@state[:transfer_spec].has_key?('EX_ssh_key_value') and
        !@state[:transfer_spec].has_key?('EX_ssh_key_paths') then
          raise TransferError.new('required: ssh key (value or path) or password')
        end

        # parameters with env vars
        param_string_env('password','ASPERA_SCP_PASS')
        param_string_env('token','ASPERA_SCP_TOKEN')
        param_string_env('cookie','ASPERA_SCP_COOKIE')
        param_string_env('EX_ssh_key_value','ASPERA_SCP_KEY')
        param_string_env('EX_at_rest_password','ASPERA_SCP_FILEPASS')
        param_string_env('EX_proxy_password','ASPERA_PROXY_PASS')

        # TODO : -c argument ?, what about "none"
        value=use_parameter('cipher',[String])
        case value
        when nil;# nothing to put on command line, encryption by default
        when 'aes-128','aes128';# nothing to put on command line (or faspe: link), encryption by default
        else raise TransferError.new("unsupported cipher: #{value}")
        end

        set_param_boolean('create_dir','-d')
        set_param_boolean('precalculate_job_size','--precalculate-job-size')
        set_param_boolean('EX_quiet','-q')

        set_param_list_num('resume_policy','-k',RESUME_POLICIES,'sparse_csum')

        set_param_value('direction','--mode',[String]){|v|{'receive'=>'recv','send'=>'send'}[v]}
        set_param_value('remote_user','--user',[String])
        set_param_value('remote_host','--host',[String])
        set_param_value('ssh_port','-P',[Integer])
        set_param_value('fasp_port','-O',[Integer])
        set_param_value('target_rate_kbps','-l',[Integer])
        set_param_value('min_rate_kbps','-m',[Integer])
        set_param_value('rate_policy','--policy',[String])
        set_param_value('http_fallback','-y',[String,TrueClass,FalseClass]){|v|{'force'=>'F',true=>1,false=>0}[v]}
        set_param_value('http_fallback_port','-t',[Integer])
        set_param_value('source_root','--source-prefix64',[String]){|prefix|Base64.strict_encode64(prefix)}
        set_param_value('sshfp','--check-sshfp',[String])
        set_param_value('symlink_policy','--symbolic-links',[String])
        set_param_value('overwrite','--overwrite',[String])

        set_param_value('EX_fallback_key','-Y',[String])
        set_param_value('EX_fallback_cert','-I',[String])
        set_param_value('EX_fasp_proxy_url','--proxy',[String])
        set_param_value('EX_http_proxy_url','-x',[String])
        set_param_value('EX_ssh_key_paths','-i',[Array])

        # TODO: manage those parameters, some are for connect only ? node api ?
        ignore_parameter('target_rate_cap_kbps',[String])
        ignore_parameter('target_rate_percentage',[String]) # -wf -l<rate>p
        ignore_parameter('min_rate_cap_kbps',[String])
        ignore_parameter('rate_policy_allowed',[String])
        ignore_parameter('fasp_url',[String])
        ignore_parameter('lock_rate_policy',[String])
        ignore_parameter('lock_min_rate',[String])
        ignore_parameter('lock_target_rate',[String])
        ignore_parameter('authentication',[String]) # = token
        ignore_parameter('https_fallback_port',[String]) # same as http fallback, option -t ?
        ignore_parameter('content_protection',[String])
        ignore_parameter('cipher_allowed',[String])

        # optional tags (  additional option to generate: {:space=>' ',:object_nl=>' ',:space_before=>'+',:array_nl=>'1'}  )
        set_param_value('tags','--tags64',[Hash]){|tags| Base64.strict_encode64(JSON.generate(tags)) }
        set_param_value('tags64','--tags64',[String]) # from faspe link

        # optional args, at the end to override previou ones
        value=use_parameter('EX_ascp_args',[Array])
        add_ascp_options(*value) if !value.nil?

        # destination will be base64 encoded, put before path arguments
        add_ascp_options('--dest64')

        # source list: TODO : use file list or file pair list, avoid command line lists
        value=use_parameter('paths',[Array],true)
        add_ascp_options(*value.map{|i|i['source']})

        # destination, use base64 encoding, as defined previously
        value=use_parameter('destination_root',[String],true)
        add_ascp_options(Base64.strict_encode64(value))

        # warn about non translated arguments
        @state[:transfer_spec].each_pair { |key,value|
          if !@state[:used_names].include?(key)
            Log.log.error("unhandled parameter: #{key} = \"#{value}\"")
          end
        }

        return @state[:result]
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
