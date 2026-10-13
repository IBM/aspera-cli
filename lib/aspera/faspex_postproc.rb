# frozen_string_literal: true

require 'json'
require 'timeout'
require 'English'
require 'ipaddr'
require 'openssl'
require 'webrick'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/environment'
require 'aspera/hash_ext'
require 'aspera/mime'
require 'aspera/secret_strength'

module Aspera
  # Start a Faspex-4 style post-processing script using Faspex-5 webhook
  #
  # Security notes:
  # - By default the listener binds to loopback only (url defaults to http://localhost:...).
  #   Use a routable address only when the Faspex containers must reach this host:
  #   then `secret_token` or `allowed_ips` is required (checked by the `faspex5 postprocessing` command).
  # - Use `secret_token` so the token must be present as a `token` query parameter on every
  #   incoming request (configure the webhook URL in Faspex as http://host:port/path?token=VALUE).
  # - Use `allowed_ips` to restrict which source IPs or networks may call the listener.
  # - Only webhook values with a key starting with `faspex_` are passed to the script.
  # - With `lambda` in the URL query, a Ruby script (`.rb`) is evaluated in this process:
  #   it shall return a lambda, called with the webhook values.
  class Faspex4PostProcServlet < WEBrick::HTTPServlet::AbstractServlet
    ALLOWED_PARAMETERS = %i[root script_folder fail_on_error timeout_seconds secret_token secret_token_min_bits allowed_ips].freeze
    # Prefix of keys of webhook values passed as environment variables: Faspex 4 post-processing variables
    ENV_KEY_PREFIX = 'faspex_'
    private_constant :ENV_KEY_PREFIX

    class << self
      # Check parameters and set defaults
      # Called at startup, so that errors are reported before the first request
      # @param parameters [Hash] Parameters of the servlet
      # @return [Hash] Parameters with defaults, and `allowed_ips` as `IPAddr`
      def normalize_parameters(parameters)
        Aspera.assert_type(parameters, Hash)
        parameters = parameters.symbolize_keys
        not_allowed = parameters.keys - ALLOWED_PARAMETERS
        Aspera.assert(not_allowed.empty?) { "unsupported parameters: #{not_allowed.join(', ')}" }
        parameters[:script_folder] ||= '.'
        parameters[:fail_on_error] ||= false
        parameters[:timeout_seconds] ||= 60
        parameters[:secret_token_min_bits] ||= 80
        Aspera.assert(File.directory?(parameters[:script_folder])) { "script_folder not found: #{parameters[:script_folder]}" }
        # An empty token would accept requests without token
        if parameters.key?(:secret_token)
          Aspera.assert(!parameters[:secret_token].to_s.empty?) { 'secret_token must not be empty' }
          bits = SecretStrength.bits(parameters[:secret_token])
          Aspera.assert(bits >= parameters[:secret_token_min_bits]) do
            "secret_token is too weak: about #{bits.round} bits, minimum #{parameters[:secret_token_min_bits]} (secret_token_min_bits). Generate one with: openssl rand -hex 32"
          end
        end
        # allowed_ips: optional IP addresses or networks (CIDR); nil means no restriction
        parameters[:allowed_ips] = Array(parameters[:allowed_ips]).map { |ip| ip_address(ip) } if parameters.key?(:allowed_ips)
        parameters
      end

      private

      # @param ip [String, IPAddr] IP address or network (CIDR)
      # @return [IPAddr] Parsed address
      def ip_address(ip)
        return ip if ip.is_a?(IPAddr)
        IPAddr.new(ip)
      rescue IPAddr::Error
        raise ArgumentError, "allowed_ips: invalid IP address or network: #{ip}"
      end
    end

    # @param server     [WEBrick::HTTPServer] Server
    # @param parameters [Hash] Parameters from `normalize_parameters`: the servlet is created on each request
    def initialize(server, parameters)
      @parameters = parameters
      Log.dump(:post_proc_parameters, @parameters)
      super(server)
      Log.log.debug { 'Faspex4PostProcServlet initialized' }
    end

    # :reek:UncommunicativeMethodName
    def do_POST(request, response)
      Log.log.debug { "request=#{request.path}" }
      # `request.query` only parses a form body for POST: parameters in the URL come from the query string
      url_query = WEBrick::HTTPUtils.parse_query(request.query_string)
      Log.dump(:query, url_query)
      post_proc_pid = nil
      script_path = nil
      begin
        # Check source IP against allowlist when configured
        if @parameters[:allowed_ips]
          client_ip = request.peeraddr[3]
          unless allowed_ip?(client_ip)
            Log.log.warn { "Rejected request from disallowed IP: #{client_ip}" }
            return error_response(response, 403, 'Forbidden')
          end
        end
        # Verify shared secret when configured (expected as ?token=VALUE in the URL)
        if @parameters[:secret_token] && !OpenSSL.secure_compare(url_query['token'].to_s, @parameters[:secret_token].to_s)
          Log.log.warn { 'Rejected request with invalid or missing token' }
          return error_response(response, 401, 'Unauthorized')
        end
        # Only accept requests on the root
        return error_response(response, 400, 'Request outside domain') unless request.path.start_with?(@parameters[:root])
        return error_response(response, 400, 'Empty request') if request.body.nil?
        webhook_parameters =
          begin
            JSON.parse(request.body)
          rescue JSON::ParserError
            nil
          end
        return error_response(response, 400, 'Request body shall be a JSON object') unless webhook_parameters.is_a?(Hash)
        Log.dump(:webhook_parameters, webhook_parameters)
        # build script path by removing domain and adding script folder
        script_file = request.path[@parameters[:root].size..]
        Log.log.debug { "script file=#{script_file}" }
        # Resolve the real path and ensure it stays within script_folder (prevents path traversal)
        resolved_script_folder = File.realpath(@parameters[:script_folder])
        begin
          script_path = File.realpath(File.join(@parameters[:script_folder], script_file))
        rescue Errno::ENOENT, Errno::ENOTDIR
          return error_response(response, 404, 'Script not found')
        end
        unless script_path.start_with?("#{resolved_script_folder}/")
          Log.log.warn { "Rejected script outside script_folder: #{script_path}" }
          return error_response(response, 403, 'Script path traversal attempt detected')
        end
        return error_response(response, 404, 'Script not found') unless File.file?(script_path)
        Log.log.debug { "script=#{script_path}" }
        process_status = nil
        if url_query.key?('lambda')
          return error_response(response, 400, 'lambda requires a Ruby script (.rb)') unless File.extname(script_path).eql?('.rb')
          run_lambda(script_path, webhook_parameters)
        else
          post_proc_pid = Environment.secure_execute(script_path, mode: :background, env: script_environment(webhook_parameters))
          Timeout.timeout(@parameters[:timeout_seconds]) do
            # "wait" for process to avoid zombie
            Process.wait(post_proc_pid)
            post_proc_pid = nil
          end
          process_status = $CHILD_STATUS
          Aspera.assert(process_status.success? || !@parameters[:fail_on_error]) { "script #{script_path} failed with code #{process_status.exitstatus}" }
        end
        response.status = 200
        response.content_type = Mime::JSON
        response.body = JSON.generate({status: 'success', script: script_path, exit_code: process_status&.exitstatus})
        Log.log.debug { 'Script executed successfully' }
      rescue StandardError, ScriptError => e
        # ScriptError: syntax error in lambda script
        Log.log.error("Script failed: #{e.class}:#{e.message}")
        kill_script(post_proc_pid) unless post_proc_pid.nil?
        error_response(response, 500, e.message, script: script_path)
      end
    end

    private

    # Set an error in the response
    # @param response [WEBrick::HTTPResponse] Response to set
    # @param status   [Integer] HTTP status code
    # @param message  [String]  Error message
    # @param info     [Hash]    Additional fields in body
    # @return nil
    def error_response(response, status, message, **info)
      response.status = status
      response['Content-Type'] = Mime::JSON
      response.body = JSON.generate({status: 'error', **info, message: message})
      nil
    end

    # @param client_ip [String] Source IP address of the request
    # @return [Boolean] `true` if the address is in one of `allowed_ips`
    def allowed_ip?(client_ip)
      # IPv4 clients of a dual-stack listener appear as IPv4-mapped IPv6 addresses
      address = IPAddr.new(client_ip).native
      @parameters[:allowed_ips].any? { |allowed| allowed.include?(address) }
    rescue IPAddr::Error
      false
    end

    # Environment variables of the script: same as Faspex 4 post-processing
    # Other keys are ignored: they could change the behavior of the script (e.g. `PATH`, `LD_PRELOAD`)
    # @param webhook_parameters [Hash] Values received in webhook
    # @return [Hash] Environment variables, values are `String`
    def script_environment(webhook_parameters)
      webhook_parameters.each_with_object({}) do |(key, value), env|
        unless key.start_with?(ENV_KEY_PREFIX)
          Log.log.warn { "Ignoring webhook value with key not starting with #{ENV_KEY_PREFIX}: #{key.inspect}" }
          next
        end
        # Structured values are given as JSON
        env[key] = value.is_a?(Hash) || value.is_a?(Array) ? JSON.generate(value) : value.to_s
      end
    end

    # Evaluate a Ruby script in this process, and call the lambda it returns
    # @param script_path        [String] Path of Ruby script
    # @param webhook_parameters [Hash]   Values received in webhook
    def run_lambda(script_path, webhook_parameters)
      Timeout.timeout(@parameters[:timeout_seconds]) do
        code = Environment.secure_eval(File.read(script_path), script_path, 1)
        Aspera.assert(code.respond_to?(:call)) { "script #{script_path} shall return a lambda" }
        code.call(webhook_parameters)
      end
    end

    # Kill the script after a timeout or an error
    # @param pid [Integer] Process id of the script
    def kill_script(pid)
      Process.kill('SIGKILL', pid)
      Process.wait(pid)
      Log.log.error("Killed process: #{pid}")
    rescue SystemCallError
      # already terminated
      nil
    end
  end
end
