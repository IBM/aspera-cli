require 'uri'
require 'resolv'
require 'erb'

module Aspera
  # evaluate a proxy autoconfig script
  class ProxyAutoConfig
    # template file is read once, it contains functions that can be used in a proxy autoconf script
    PAC_FUNC_TEMPLATE=File.read(__FILE__.gsub(/\.rb$/,'.erb.js'))
    private_constant :PAC_FUNC_TEMPLATE
    # @param proxy_auto_config the proxy auto config script to be evaluated
    def initialize(proxy_auto_config)
      @proxy_auto_config=proxy_auto_config
    end

    # execut proxy auto config script for the given URL
    def get_proxy(service_url)
      # require at runtime, in case there is no js engine
      require 'execjs'
      # variables starting with "context_" are replaced in the ERB template file
      # I did not find an easy way for the javascript to callback ruby
      # and anyway, it only needs to get DNS translation
      context_self='127.0.0.1'
      context_host=URI.parse(service_url).host
      context_ip=nil
      Resolv::DNS.open{|dns|dns.each_address(context_host){|r_addr|context_ip=r_addr.to_s if r_addr.is_a?(Resolv::IPv4)}}
      raise "DNS name not found: #{context_host}" if context_ip.nil?
      pac_functions=ERB.new(PAC_FUNC_TEMPLATE).result(binding)
      context = ExecJS.compile(pac_functions+@proxy_auto_config)
      return context.call("FindProxyForURL", service_url, context_host)
    end
  end
end

