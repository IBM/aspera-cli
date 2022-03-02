require 'aspera/rest_error_analyzer'
require 'aspera/log'

module Aspera
  # REST error handlers for various Aspera REST APIs
  class RestErrorsAspera
    # handlers should probably be defined by plugins for modularity
    def self.registerHandlers
      Log.log.debug('registering Aspera REST error handlers')
      # Faspex 4: both user_message and internal_message, and code 200
      # example: missing meta data on package creation
      RestErrorAnalyzer.instance.add_simple_handler('Type 1: error:user_message','error','user_message',true)
      RestErrorAnalyzer.instance.add_simple_handler('Type 2: error:description','error','description')
      RestErrorAnalyzer.instance.add_simple_handler('Type 3: error:internal_message','error','internal_message')
      # AoC Automation
      RestErrorAnalyzer.instance.add_simple_handler('AoC Automation','error')
      RestErrorAnalyzer.instance.add_simple_handler('Type 5','error_description')
      RestErrorAnalyzer.instance.add_simple_handler('Type 6','message')
      RestErrorAnalyzer.instance.add_handler('Type 7: errors[]') do |name,call_context|
        if call_context[:data].is_a?(Hash) and call_context[:data]['errors'].is_a?(Hash)
          call_context[:data]['errors'].each do |k,v|
            RestErrorAnalyzer.add_error(call_context,name,"#{k}: #{v}")
          end
        end
      end
      # call to upload_setup and download_setup of node api
      RestErrorAnalyzer.instance.add_handler('T8:node: *_setup') do |type,call_context|
        if call_context[:data].is_a?(Hash)
          d_t_s=call_context[:data]['transfer_specs']
          if d_t_s.is_a?(Array)
            d_t_s.each do |res|
              #r_err=res['transfer_spec']['error']
              r_err=res['error']
              if r_err.is_a?(Hash)
                RestErrorAnalyzer.add_error(call_context,type,"#{r_err['code']}: #{r_err['reason']}: #{r_err['user_message']}")
              end
            end
          end
        end
      end
      RestErrorAnalyzer.instance.add_simple_handler('T9:IBM cloud IAM','errorMessage')
      RestErrorAnalyzer.instance.add_simple_handler('T10:faspex v4','user_message')
      RestErrorAnalyzer.instance.add_handler('bss graphql') do |type,call_context|
        if call_context[:data].is_a?(Hash)
          d_t_s=call_context[:data]['errors']
          if d_t_s.is_a?(Array)
            d_t_s.each do |res|
              r_err=res['message']
              if r_err.is_a?(String)
                RestErrorAnalyzer.add_error(call_context,type,r_err)
              end
            end
          end
        end
      end
    end # registerErrorTypes
  end
end
