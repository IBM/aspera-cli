# frozen_string_literal: true

require 'json'
require 'timeout'
require 'English'
require 'webrick'
require 'aspera/log'
require 'aspera/assert'

module Aspera
  # this class answers the Faspex /send API and creates a package on Aspera on Cloud
  class Faspex4PostProcServlet < WEBrick::HTTPServlet::AbstractServlet
    ALLOWED_PARAMETERS = %i[root script_folder fail_on_error timeout_seconds].freeze
    def initialize(server, parameters)
      Aspera.assert_type(parameters, Hash)
      @parameters = parameters.symbolize_keys
      Log.log.debug{Log.dump(:post_proc_parameters, @parameters)}
      not_allowed = @parameters.keys - ALLOWED_PARAMETERS
      raise "unsupported parameters: #{not_allowed.join(', ')}" unless not_allowed.empty?
      @parameters[:script_folder] ||= '.'
      @parameters[:fail_on_error] ||= false
      @parameters[:timeout_seconds] ||= 60
      super(server)
      Log.log.debug{'Faspex4PostProcServlet initialized'}
    end

    def do_POST(request, response)
      Log.log.debug{"request=#{request.path}"}
      begin
        # only accept requests on the root
        if !request.path.start_with?(@parameters[:root])
          response.status = 400
          response['Content-Type'] = Rest::MIME_JSON
          response.body = {status: 'error', message: 'Request outside domain'}.to_json
          return
        end
        if request.body.nil?
          response.status = 400
          response['Content-Type'] = Rest::MIME_JSON
          response.body = {status: 'error', message: 'Empty request'}.to_json
          return
        end
        # build script path by removing domain and adding script folder
        script_file = request.path[@parameters[:root].size..]
        Log.log.debug{"script file=#{script_file}"}
        script_path = File.join(@parameters[:script_folder], script_file)
        Log.log.debug{"script=#{script_path}"}
        webhook_parameters = JSON.parse(request.body)
        Log.log.debug{Log.dump(:webhook_parameters, webhook_parameters)}
        # env expects only strings
        environment = webhook_parameters.each_with_object({}){ |(k, v), h| h[k] = v.to_s}
        post_proc_pid = Environment.secure_spawn(env: environment, exec: script_path)
        Timeout.timeout(@parameters[:timeout_seconds]) do
          # "wait" for process to avoid zombie
          Process.wait(post_proc_pid)
          post_proc_pid = nil
        end
        process_status = $CHILD_STATUS
        raise "script #{script_path} failed with code #{process_status.exitstatus}" if !process_status.success? && @parameters[:fail_on_error]
        response.status = 200
        response.content_type = Rest::MIME_JSON
        response.body = JSON.generate({status: 'success', script: script_path, exit_code: process_status.exitstatus})
        Log.log.debug{'Script executed successfully'}
      rescue => e
        Log.log.error("Script failed: #{e.class}:#{e.message}")
        if !post_proc_pid.nil?
          Process.kill('SIGKILL', post_proc_pid)
          Process.wait(post_proc_pid)
          Log.log.error("Killed process: #{post_proc_pid}")
        end
        response.status = 500
        response['Content-Type'] = Rest::MIME_JSON
        response.body = {status: 'error', script: script_path, message: e.message}.to_json
      end
    end
  end
end
