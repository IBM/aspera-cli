require "asperalm/log"
require "asperalm/fasp/parameters"

module Asperalm
  module Fasp
    # translates a "faspe:" URI into transfer spec hash
    class Uri
      def initialize(fasplink)
        @fasp_uri=URI.parse(fasplink)
      end
      def transfer_spec
        result_ts={}
        result_ts['remote_host']=@fasp_uri.host
        result_ts['remote_user']=@fasp_uri.user
        result_ts['ssh_port']=@fasp_uri.port
        result_ts['paths']=[{"source"=>URI.decode_www_form_component(@fasp_uri.path)}]

        URI::decode_www_form(@fasp_uri.query).each do |i|
          name=i[0]
          value=i[1]
          case name
          when 'cookie'; result_ts['cookie']=value
          when 'token'; result_ts['token']=value
          when 'policy'; result_ts['rate_policy']=value
          when 'httpport'; result_ts['http_fallback_port']=value.to_i
          when 'targetrate'; result_ts['target_rate_kbps']=value.to_i
          when 'minrate'; result_ts['min_rate_kbps']=value.to_i
          when 'port'; result_ts['fasp_port']=value.to_i
          when 'enc'; result_ts['cipher']=value
          when 'tags64'; result_ts['tags64']=value
          when 'bwcap'; result_ts['target_rate_cap_kbps']=value
          when 'createpath'; result_ts['create_dir']=Parameters.yes_to_true(value)
          when 'fallback'; result_ts['http_fallback']=Parameters.yes_to_true(value)
          when 'lockpolicy'; result_ts['lock_rate_policy']=value
          when 'lockminrate'; result_ts['lock_min_rate']=value
          when 'auth'; Log.log.debug("ignoring #{name}=#{value}") # TODO: translate into transfer spec ?
          when 'v'; Log.log.debug("ignoring #{name}=#{value}") # TODO: translate into transfer spec ?
          when 'protect'; Log.log.debug("ignoring #{name}=#{value}") # TODO: translate into transfer spec ?
          else Log.log.error("non managed URI value: #{name} = #{value}")
          end
        end
        return result_ts
      end
    end # Parameters
  end # Fasp
end # Asperalm
