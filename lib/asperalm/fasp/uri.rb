require "asperalm/log"

module Asperalm
  module Fasp
    # translates a "faspe:" URI into transfer spec hash
    class Uri
      def self.fasp_uri_to_transfer_spec(fasplink)
        transfer_uri=URI.parse(fasplink)
        transfer_spec={}
        transfer_spec['remote_host']=transfer_uri.host
        transfer_spec['remote_user']=transfer_uri.user
        transfer_spec['ssh_port']=transfer_uri.port
        transfer_spec['paths']=[{"source"=>URI.decode_www_form_component(transfer_uri.path)}]

        URI::decode_www_form(transfer_uri.query).each do |i|
          name=i[0]
          value=i[1]
          case name
          when 'cookie'; transfer_spec['cookie']=value
          when 'token'; transfer_spec['token']=value
          when 'policy'; transfer_spec['rate_policy']=value
          when 'httpport'; transfer_spec['http_fallback_port']=value
          when 'targetrate'; transfer_spec['target_rate_kbps']=value
          when 'minrate'; transfer_spec['min_rate_kbps']=value
          when 'port'; transfer_spec['fasp_port']=value
          when 'enc'; transfer_spec['cipher']=value
          when 'tags64'; transfer_spec['tags64']=value
          when 'bwcap'; transfer_spec['target_rate_cap_kbps']=value
          when 'createpath'; transfer_spec['create_dir']=yes_to_true(value)
          when 'fallback'; transfer_spec['http_fallback']=yes_to_true(value)
          when 'lockpolicy'; transfer_spec['lock_rate_policy']=value
          when 'lockminrate'; transfer_spec['lock_min_rate']=value
          when 'auth'; Log.log.debug("ignoring #{name}=#{value}") # TODO: translate into transfer spec ?
          when 'v'; Log.log.debug("ignoring #{name}=#{value}") # TODO: translate into transfer spec ?
          when 'protect'; Log.log.debug("ignoring #{name}=#{value}") # TODO: translate into transfer spec ?
          else Log.log.error("non managed URI value: #{name} = #{value}")
          end
        end
        return transfer_spec
      end
    end # Parameters
  end # Fasp
end # Asperalm
