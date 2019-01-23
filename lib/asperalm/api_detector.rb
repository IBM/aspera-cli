require 'asperalm/log'
require 'asperalm/rest'

module Asperalm
  class ApiDetector
    def self.discover_product(url)
      #uri=URI.parse(url)
      api=Rest.new({:base_url=>url})
      # Node
      begin
        result=api.call({:operation=>'GET',:subpath=>'ping'})
        if result[:http].body.eql?('')
          return {:product=>:node,:version=>'unknown'}
        end
      rescue SocketError => e
        raise e
      rescue => e
        Log.log.debug("not node (#{e.class}: #{e})")
      end
      # AoC
      begin
        result=api.call({:operation=>'GET',:subpath=>'',:headers=>{'Accept'=>'text/html'}})
        if result[:http].body.include?('content="AoC"')
          return {:product=>:aoc,:version=>'unknown'}
        end
      rescue SocketError => e
        raise e
      rescue => e
        Log.log.debug("not aoc (#{e.class}: #{e})")
      end
      # Faspex
      begin
        result=api.call({:operation=>'POST',:subpath=>'aspera/faspex',:headers=>{'Accept'=>'application/xrds+xml'},:text_body_params=>''})
        if result[:http].body.start_with?('<?xml')
          res_s=XmlSimple.xml_in(result[:http].body, {"ForceArray" => false})
          version=res_s['XRD']['application']['version']
          #return JSON.pretty_generate(res_s)
        end
        return {:product=>:faspex,:version=>version}
      rescue
        Log.log.debug("not faspex")
      end
      # Shares
      begin
        result=api.read('node_api/app')
        Log.log.warn("not supposed to work")
      rescue RestCallError => e
        if e.response.code.to_s.eql?('401') and e.response.body.eql?('{"error":{"user_message":"API user authentication failed"}}')
          return {:product=>:shares,:version=>'unknown'}
        end
        Log.log.warn("not shares: #{e.response.code} #{e.response.body}")
      rescue
      end
      return {:product=>:unknown,:version=>'unknown'}
    end
  end
end