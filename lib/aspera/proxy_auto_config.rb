require 'uri'
require 'resolv'
require 'erb'

module Aspera
  # evaluate a proxy autoconfig script
  class ProxyAutoConfig
    # template file is read once, it contains functions that can be used in a proxy autoconf script
    PAC_FUNC_TEMPLATE=File.read(__FILE__.gsub(/\.rb$/,'.erb.js')).freeze
    private_constant :PAC_FUNC_TEMPLATE
    # @param proxy_auto_config the proxy auto config script to be evaluated
    def initialize(proxy_auto_config)
      @proxy_auto_config=proxy_auto_config
      @cache={}
    end

    # execute proxy auto config script for the given URL
    # @return either nil, or a String
    def get_proxy(service_url)
      uri=URI.parse(service_url)
      simple_url="#{uri.scheme}://#{uri.host}"
      if !@cache.has_key?(simple_url)
        # require at runtime, in case there is no js engine
        require 'execjs'
        # variables starting with "context_" are replaced in the ERB template file
        # I did not find an easy way for the javascript to callback ruby
        # and anyway, it only needs to get DNS translation
        context_self='127.0.0.1'
        context_host=uri.host
        context_ip=nil
        Resolv::DNS.open{|dns|dns.each_address(context_host){|r_addr|context_ip=r_addr.to_s if r_addr.is_a?(Resolv::IPv4)}}
        raise "DNS name not found: #{context_host}" if context_ip.nil?
        # Kernel.binding contains current local variables
        pac_functions=ERB.new(PAC_FUNC_TEMPLATE).result(binding)
        js_to_execute=pac_functions+@proxy_auto_config
        js_context = ExecJS.compile(js_to_execute)
        @cache[simple_url]=js_context.call('FindProxyForURL', simple_url, context_host)
      end
      return @cache[simple_url]
    end

    # @return Array of URI
    def get_proxies(service_url)
      result=[]
      strlist=get_proxy(service_url)
      return result if strlist.nil?
      raise 'expect String' unless strlist.is_a?(String)
      strlist.split(';').each do |one|
        d=one.strip.gsub(/\s+/,' ').split(' ')
        case d[0]
        when 'DIRECT'
          raise 'DIRECT has no param' unless d.length.eql?(1)
        when 'PROXY'
          raise 'PROXY shall have one param' unless d.length.eql?(2)
          d[1]='proxy://'+d[1] unless d[1].include?('://')
          result.push(URI.parse(d[1])) rescue nil
        else Log.log.warn("proxy type #{d.first} not supported")
        end
      end
      return result
    end
  end
end

