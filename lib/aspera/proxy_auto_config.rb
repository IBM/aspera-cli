require 'uri'
require 'resolv'
require 'erb'

module Aspera
  # Evaluate a proxy autoconfig script
  class ProxyAutoConfig
    # template file is read once, it contains functions that can be used in a proxy autoconf script
    # it is similar to mozilla ascii_pac_utils.inc
    PAC_FUNC_TEMPLATE=File.read(__FILE__.gsub(/\.rb$/,'.erb.js')).freeze
    PAC_MAIN_FUNCTION='FindProxyForURL'.freeze
    private_constant :PAC_FUNC_TEMPLATE,:PAC_MAIN_FUNCTION

    private
    # variables starting with "context_" are replaced in the ERB template file
    # I did not find an easy way for the javascript to callback ruby
    # and anyway, it only needs to get DNS translation
    def build_binding(context_host)
      context_self='127.0.0.1'
      context_ip=nil
      Resolv::DNS.open{|dns|dns.each_address(context_host){|r_addr|context_ip=r_addr.to_s if r_addr.is_a?(Resolv::IPv4)}}
      raise "DNS name not found: #{context_host}" if context_ip.nil?
      # Kernel.binding contains current local variables
      return Kernel.binding
    end

    public

    # @param proxy_auto_config the proxy auto config script to be evaluated
    def initialize(proxy_auto_config)
      @proxy_auto_config=proxy_auto_config
      @cache={}
    end

    # execute proxy auto config script for the given URL : https://en.wikipedia.org/wiki/Proxy_auto-config
    # @return either nil, or a String formated following PAC standard
    def find_proxy_for_url(service_url)
      uri=URI.parse(service_url)
      simple_url="#{uri.scheme}://#{uri.host}"
      if !@cache.has_key?(simple_url)
        # require at runtime, in case there is no js engine
        require 'execjs'
        # generate javascript library
        pac_functions=ERB.new(PAC_FUNC_TEMPLATE).result(build_binding(uri.host))
        js_to_execute=pac_functions+@proxy_auto_config
        js_context = ExecJS.compile(js_to_execute)
        @cache[simple_url]=js_context.call(PAC_MAIN_FUNCTION, simple_url, uri.host)
      end
      return @cache[simple_url]
    end

    # used to replace URI::Generic.find_proxy
    # @return Array of URI, possibly empty
    def get_proxies(service_url)
      # prepare result
      uri_list=[]
      # execute PAC script
      proxy_list_str=find_proxy_for_url(service_url)
      if !proxy_list_str.is_a?(String)
        Log.log.warn("PAC: did not return a String, returned #{proxy_list_str.class}")
        return uri_list
      end
      proxy_list_str.strip!
      proxy_list_str.gsub!(/\s+/,' ')
      proxy_list_str.split(';').each do |item|
        # strip and split by space
        parts=item.strip.split(' ')
        case parts.shift
        when 'DIRECT'
          raise 'DIRECT has no param' unless parts.empty?
        when 'PROXY'
          addr_port=parts.shift
          raise 'PROXY shall have one param' unless addr_port.is_a?(String) and parts.empty?
          # typically, PAC addresses are <host>:<port>, but we want to return URIs, so add dummy scheme
          addr_port="proxy://#{addr_port}" unless addr_port.include?('://')
          begin
            uri_list.push(URI.parse(addr_port))
          rescue
            Log.log.warn("PAC: cannot parse #{addr_port}")
          end
        else Log.log.warn("PAC: ignoring proxy type #{parts.first}: not supported")
        end
      end
      return uri_list
    end
  end
end

