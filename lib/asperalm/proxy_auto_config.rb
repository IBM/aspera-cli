require 'execjs'
require 'uri'
require 'resolv'
require 'erb'

module Asperalm
  class ProxyAutoConfig
    PAC_FUNC_TEMPLATE=File.read(__FILE__.gsub(/\.rb$/,'.erb.js'))
    private_constant :PAC_FUNC_TEMPLATE
    def initialize(proxy_auto_config)
      @proxy_auto_config=proxy_auto_config
    end

    # get string representing proxy configuration
    def get_proxy(service_url)
      # set context for template
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

