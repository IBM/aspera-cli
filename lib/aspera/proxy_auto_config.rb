# frozen_string_literal: true

require 'aspera/log'
require 'aspera/assert'
require 'uri'
require 'resolv'

module URI
  class Generic
    # save original method that finds proxy in URI::Generic, it uses env var http_proxy
    alias_method :find_proxy_orig, :find_proxy
    class << self
      def register_proxy_finder
        Aspera.assert(block_given?)
        # overload the method in URI : call user's provided block and fallback to original method
        define_method(:find_proxy) {|env_vars=ENV| yield(to_s) || find_proxy_orig(env_vars)}
      end
    end
  end
end

module Aspera
  # Evaluate a proxy auto config script
  class ProxyAutoConfig
    # template file is read once, it contains functions that can be used in a proxy autoconf script
    # it is similar to mozilla ascii_pac_utils.inc
    PAC_FUNCTIONS_FILE = __FILE__.gsub(/\.rb$/, '.js').freeze
    PAC_MAIN_FUNCTION = 'FindProxyForURL'
    private_constant :PAC_FUNCTIONS_FILE, :PAC_MAIN_FUNCTION

    private

    # variables starting with "context_" are replaced in the ERB template file
    # I did not find an easy way for the javascript to callback ruby
    # and anyway, it only needs to get DNS translation
    def pac_dns_functions(context_host)
      context_self = '127.0.0.1'
      context_ip = nil
      Resolv::DNS.open{|dns|dns.each_address(context_host){|r_addr|context_ip = r_addr.to_s if r_addr.is_a?(Resolv::IPv4)}}
      raise "DNS name not found: #{context_host}" if context_ip.nil?
      # NOTE: Javascript code here with string inclusions
      javascript = <<END_OF_JAVASCRIPT
      function dnsResolve(host) {
        if (host == '#{context_host}' || host == '#{context_ip}')
          return '#{context_ip}';
        throw 'only DNS for initial host, not ' + host;
      }
      function myIpAddress() {
        return '#{context_self}';
      }
END_OF_JAVASCRIPT
      return javascript
    end

    public

    attr_writer :proxy_user, :proxy_pass

    # @param proxy_auto_config the proxy auto config script to be evaluated
    def initialize(proxy_auto_config)
      # user provided javascript with FindProxyForURL function
      @proxy_auto_config = proxy_auto_config
      # avoid multiple execution, this does not support load balancing
      @cache = {}
      @proxy_user = @proxy_pass = @pac_functions = nil
    end

    def register_uri_generic
      URI::Generic.register_proxy_finder{|url_str|get_proxies(url_str).first}
      # allow chaining
      return self
    end

    # execute proxy auto config script for the given URL : https://en.wikipedia.org/wiki/Proxy_auto-config
    # @return either nil, or a String formatted following PAC standard
    def find_proxy_for_url(service_url)
      uri = URI.parse(service_url)
      simple_url = "#{uri.scheme}://#{uri.host}"
      if !@cache.key?(simple_url)
        Log.log.debug{"PAC: starting javascript for #{service_url}"}
        # require at runtime, in case there is no js engine
        require 'execjs'
        # read template lib
        @pac_functions = File.read(PAC_FUNCTIONS_FILE).freeze if @pac_functions.nil?
        # to be executed is dns + utils + user function
        js_to_execute = "#{pac_dns_functions(uri.host)}#{@pac_functions}#{@proxy_auto_config}"
        executable_js = ExecJS.compile(js_to_execute)
        @cache[simple_url] = executable_js.call(PAC_MAIN_FUNCTION, simple_url, uri.host)
        Log.log.debug{"PAC: result: #{@cache[simple_url]}"}
      end
      return @cache[simple_url]
    end

    # used to replace URI::Generic.find_proxy
    # @return Array of URI, possibly empty
    def get_proxies(service_url)
      # prepare result
      uri_list = []
      # execute PAC script
      proxy_list_str = find_proxy_for_url(service_url)
      if !proxy_list_str.is_a?(String)
        Log.log.warn{"PAC: did not return a String, returned #{proxy_list_str.class}"}
        return uri_list
      end
      proxy_list_str.strip!
      proxy_list_str.gsub!(/\s+/, ' ')
      proxy_list_str.split(';').each do |item|
        # strip and split by space
        parts = item.strip.split
        case parts.shift
        when 'DIRECT'
          Aspera.assert(parts.empty?){'DIRECT has no param'}
          Log.log.debug('ignoring proxy DIRECT')
        when 'PROXY'
          addr_port = parts.shift
          Aspera.assert_type(addr_port, String)
          Aspera.assert(parts.empty?){'PROXY shall have one param'}
          begin
            # PAC proxy addresses are <host>:<port>
            if /:[0-9]+$/.match?(addr_port)
              uri = URI.parse("proxy://#{addr_port}")
              # ruby v>2.6 allows
              uri.user = @proxy_user
              uri.password = @proxy_pass
              uri_list.push(uri)
            else
              Log.log.warn{"PAC: PROXY must be <address>:<port>, ignoring #{addr_port}"}
            end
          rescue StandardError => e
            Log.log.warn{"PAC: cannot parse #{addr_port} #{e}"}
          end
        else Log.log.warn{"PAC: ignoring proxy type #{parts.first}: not supported"}
        end
      end
      Log.log.debug{"Proxies: #{uri_list}"}
      return uri_list
    end
  end
end
