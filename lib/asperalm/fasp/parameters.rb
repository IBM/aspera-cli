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

      # returns the value from transfer spec and mark parameter as used
      def use_parameter(ts_name,mandatory=false)
        raise TransferError.new("mandatory parameter: #{ts_name}") if mandatory and !@state[:transfer_spec].has_key?(ts_name)
        @state[:used_names].push(ts_name)
        return @state[:transfer_spec][ts_name]
      end
      alias_method(:ignore_parameter,:use_parameter)

      # define ascp parameter in env var from transfer spec
      def set_param_env(ts_name,env_name)
        value=use_parameter(ts_name)
        @state[:result][:env][env_name] = value if !value.nil?
      end

      # ts_name : key in transfer spec
      # ascp_option : option on ascp command line
      # transform : transformation function for transfer spec value to option value
      # if transfer_spec value is an array, applies option many times
      def set_param_value(ts_name,ascp_option,&transform)
        value=use_parameter(ts_name)
        if !value.nil?
          if transform
            newvalue=transform.call(value)
            if newvalue.nil?
              TransferError.new("unsupported #{ts_name}: #{value}")
            else
              value=newvalue
            end
          end
          value=value.to_s if value.is_a?(Integer)
          value=[value] if value.is_a?(String)
          value.each{|v|@state[:result][:args].push(ascp_option,v)}
        end
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
        set_param_env('password','ASPERA_SCP_PASS')
        set_param_env('token','ASPERA_SCP_TOKEN')
        set_param_env('cookie','ASPERA_SCP_COOKIE')
        set_param_env('EX_ssh_key_value','ASPERA_SCP_KEY')
        set_param_env('EX_at_rest_password','ASPERA_SCP_FILEPASS')
        set_param_env('EX_proxy_password','ASPERA_PROXY_PASS')

        # TODO : -c argument ?, what about "none"
        value=use_parameter('cipher')
        case value
        when nil;# nothing to put on command line, encryption by default
        when 'aes-128','aes128';# nothing to put on command line (or faspe: link), encryption by default
        else raise TransferError.new("unsupported cipher: #{value}")
        end

        value=use_parameter('create_dir')
        case value
        when nil,false# nothing to put on command line, no creation by default
        when true; @state[:result][:args].push('-d')
        else raise TransferError.new("unsupported create_dir: #{value}")
        end

        value=use_parameter('EX_quiet')
        case value
        when nil,false# nothing to put on command line, not quiet
        when true; @state[:result][:args].push('-q')
        else raise TransferError.new("unsupported EX_quiet: #{value}")
        end

        set_param_value('direction','--mode'){|v|{'receive'=>'recv','send'=>'send'}[v]}
        set_param_value('remote_user','--user')
        set_param_value('remote_host','--host')
        set_param_value('ssh_port','-P')
        set_param_value('fasp_port','-O')
        set_param_value('target_rate_kbps','-l')
        set_param_value('min_rate_kbps','-m')
        set_param_value('rate_policy','--policy')
        set_param_value('http_fallback','-y'){|v|{'force'=>'F',true=>1,false=>0}[v]}
        set_param_value('http_fallback_port','-t')
        set_param_value('source_root','--source-prefix64'){|prefix|Base64.strict_encode64(prefix)}
        set_param_value('sshfp','--check-sshfp')
        set_param_value('symlink_policy','--symbolic-links')
        set_param_value('overwrite','--overwrite')

        set_param_value('EX_fallback_key','-Y')
        set_param_value('EX_fallback_cert','-I')
        set_param_value('EX_fasp_proxy_url','--proxy')
        set_param_value('EX_http_proxy_url','-x')
        set_param_value('EX_ssh_key_paths','-i')

        # TODO: manage those parameters, some are for connect only ? node api ?
        ignore_parameter('target_rate_cap_kbps')
        ignore_parameter('target_rate_percentage') # -wf -l<rate>p
        ignore_parameter('min_rate_cap_kbps')
        ignore_parameter('rate_policy_allowed')
        ignore_parameter('fasp_url')
        ignore_parameter('lock_rate_policy')
        ignore_parameter('lock_min_rate')
        ignore_parameter('lock_target_rate')
        ignore_parameter('authentication') # = token
        ignore_parameter('https_fallback_port') # same as http fallback, option -t ?
        ignore_parameter('content_protection')
        ignore_parameter('cipher_allowed')

        # optional tags (  additional option to generate: {:space=>' ',:object_nl=>' ',:space_before=>'+',:array_nl=>'1'}  )
        set_param_value('tags','--tags64'){|tags| Base64.strict_encode64(JSON.generate(tags)) }
        set_param_value('tags64','--tags64') # from faspe link

        # optional args
        value=use_parameter('EX_ascp_args')
        @state[:result][:args].push(*value) if !value.nil?

        # destination will be base64 encoded, put before path arguments
        @state[:result][:args].push('--dest64')

        # source list: TODO : use file list or file pair list, avoid command line lists
        value=use_parameter('paths',true)
        @state[:result][:args].push(*value.map{|i|i['source']})

        # destination, use base64 encoding, as defined previously
        value=use_parameter('destination_root',true)
        @state[:result][:args].push(Base64.strict_encode64(value))

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
