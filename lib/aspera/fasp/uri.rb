require 'aspera/log'
require 'aspera/command_line_builder'

module Aspera
  module Fasp
    # translates a "faspe:" URI (used in Faspex) into transfer spec hash
    class Uri
      def initialize(fasplink)
        @fasp_uri=URI.parse(fasplink.gsub(' ','%20'))
        # TODO: check scheme is faspe
      end

      def transfer_spec
        result_ts={}
        result_ts['remote_host']=@fasp_uri.host
        result_ts['remote_user']=@fasp_uri.user
        result_ts['ssh_port']=@fasp_uri.port
        result_ts['paths']=[{'source'=>URI.decode_www_form_component(@fasp_uri.path)}]
        # faspex does not encode trailing base64 encoded tags, fix that
        fixed_query = @fasp_uri.query.gsub(/(=+)$/){|x|'%3D'*x.length}

        URI.decode_www_form(fixed_query).each do |i|
          name=i[0]
          value=i[1]
          case name
          when 'cookie' then result_ts['cookie']=value
          when 'token' then result_ts['token']=value
          when 'sshfp' then result_ts['sshfp']=value
          when 'policy' then result_ts['rate_policy']=value
          when 'httpport' then result_ts['http_fallback_port']=value.to_i
          when 'targetrate' then result_ts['target_rate_kbps']=value.to_i
          when 'minrate' then result_ts['min_rate_kbps']=value.to_i
          when 'port' then result_ts['fasp_port']=value.to_i
          when 'bwcap' then result_ts['target_rate_cap_kbps']=value.to_i
          when 'enc' then result_ts['cipher']=value.gsub(/^aes/,'aes-').gsub(/cfb$/,'-cfb').gsub(/gcm$/,'-gcm').gsub(/--/,'-')
          when 'tags64' then result_ts['tags']=JSON.parse(Base64.strict_decode64(value))
          when 'createpath' then result_ts['create_dir']=CommandLineBuilder.yes_to_true(value)
          when 'fallback' then result_ts['http_fallback']=CommandLineBuilder.yes_to_true(value)
          when 'lockpolicy' then result_ts['lock_rate_policy']=CommandLineBuilder.yes_to_true(value)
          when 'lockminrate' then result_ts['lock_min_rate']=CommandLineBuilder.yes_to_true(value)
          when 'auth' then Log.log.debug("ignoring auth #{name}=#{value}") # TODO: translate into transfer spec ? yes/no
          when 'v' then Log.log.debug("ignoring v #{name}=#{value}") # TODO: translate into transfer spec ? 2
          when 'protect' then Log.log.debug("ignoring protect #{name}=#{value}") # TODO: translate into transfer spec ?
          else Log.log.warn("URI parameter ignored: #{name} = #{value}")
          end
        end
        return result_ts
      end
    end # Uri
  end # Fasp
end # Aspera
