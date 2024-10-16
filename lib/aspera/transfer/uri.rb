# frozen_string_literal: true

# cspell:words httpport targetrate minrate bwcap createpath lockpolicy lockminrate faspe

require 'aspera/log'
require 'aspera/rest'
require 'aspera/command_line_builder'

module Aspera
  module Transfer
    # translates a "faspe:" URI (used in Faspex 4) into transfer spec (Hash)
    class Uri
      SCHEME = 'faspe'
      def initialize(fasp_link)
        @fasp_uri = URI.parse(fasp_link.gsub(' ', '%20'))
        Aspera.assert(@fasp_uri.scheme == SCHEME, "Invalid scheme: #{@fasp_uri.scheme}")
      end

      # Generate transfer spec from provided faspe: URL
      def transfer_spec
        result_ts = {}
        result_ts['remote_host'] = @fasp_uri.host
        result_ts['remote_user'] = @fasp_uri.user
        result_ts['ssh_port'] = @fasp_uri.port
        result_ts['paths'] = [{'source' => URI.decode_www_form_component(@fasp_uri.path)}]
        # faspex 4 does not encode trailing base64 padding, fix that to be able to decode properly
        fixed_query = @fasp_uri.query.gsub(/(=+)$/){|trail_equals|'%3D' * trail_equals.length}

        Rest.query_to_h(fixed_query).each do |name, value|
          case name
          when 'cookie'      then result_ts['cookie'] = value
          when 'token'       then result_ts['token'] = value
          when 'sshfp'       then result_ts['sshfp'] = value
          when 'policy'      then result_ts['rate_policy'] = value
          when 'httpport'    then result_ts['http_fallback_port'] = value.to_i
          when 'targetrate'  then result_ts['target_rate_kbps'] = value.to_i
          when 'minrate'     then result_ts['min_rate_kbps'] = value.to_i
          when 'port'        then result_ts['fasp_port'] = value.to_i
          when 'bwcap'       then result_ts['target_rate_cap_kbps'] = value.to_i
          when 'enc'         then result_ts['cipher'] = value.gsub(/^aes/, 'aes-').gsub(/cfb$/, '-cfb').gsub(/gcm$/, '-gcm').gsub('--', '-')
          when 'tags64'      then result_ts['tags'] = JSON.parse(Base64.strict_decode64(value))
          when 'createpath'  then result_ts['create_dir'] = CommandLineBuilder.yes_to_true(value)
          when 'fallback'    then result_ts['http_fallback'] = CommandLineBuilder.yes_to_true(value)
          when 'lockpolicy'  then result_ts['lock_rate_policy'] = CommandLineBuilder.yes_to_true(value)
          when 'lockminrate' then result_ts['lock_min_rate'] = CommandLineBuilder.yes_to_true(value)
          when 'auth'        then Log.log.debug{"ignoring #{name}=#{value}"} # Not used (yes/no)
          when 'v'           then Log.log.debug{"ignoring #{name}=#{value}"} # rubocop:disable Lint/DuplicateBranch Not used (shall be 2)
          when 'protect'     then Log.log.debug{"ignoring #{name}=#{value}"} # rubocop:disable Lint/DuplicateBranch TODO: what is this ?
          else                    Log.log.warn{"URI parameter ignored: #{name} = #{value}"}
          end
        end
        return result_ts
      end
    end
  end
end
