# frozen_string_literal: true

require 'aspera/log'
require 'aspera/assert'
require 'webrick'
require 'json'

module Aspera
  # Simulate the Faspex 4 /send API and creates a package on Aspera on Cloud or Faspex 5
  class Faspex4GWServlet < WEBrick::HTTPServlet::AbstractServlet
    # @param app_api
    # @param app_context [String]
    def initialize(server, app_api, app_context)
      Aspera.assert_values(app_api.class.name, ['Aspera::Api::AoC', 'Aspera::Rest'])
      super(server)
      @app_api = app_api
      @app_context = app_context
    end

    # Map Faspex 4 /send API to AoC package create
    # parameters from user to Faspex API call
    # https://developer.ibm.com/apis/catalog/aspera--aspera-faspex-client-sdk/Sending%20Packages%20(API%20v.3)
    def faspex4_send_to_aoc(faspex_pkg_parameters)
      faspex_pkg_delivery = faspex_pkg_parameters['delivery']
      package_data = {
        # 'file_names'   => faspex_pkg_delivery['sources'][0]['paths'],
        'name'         => faspex_pkg_delivery['title'],
        'note'         => faspex_pkg_delivery['note'],
        'recipients'   => faspex_pkg_delivery['recipients'],
        'workspace_id' => @app_context
      }
      created_package = @app_api.create_package_simple(package_data, true, nil)
      # but we place it in a Faspex package creation response
      return {
        'links'         => { 'status' => 'unused' },
        'xfer_sessions' => [created_package[:spec]]
      }
    end

    def faspex4_send_to_faspex5(faspex_pkg_parameters)
      faspex_pkg_delivery = faspex_pkg_parameters['delivery']
      package_data = {
        'title'      => faspex_pkg_delivery['title'],
        'note'       => faspex_pkg_delivery['note'],
        'recipients' => faspex_pkg_delivery['recipients'].map{|name|{'name'=>name}}
      }
      package = @app_api.create('packages', package_data)
      # TODO: option to send from remote source or httpgw
      transfer_spec = @app_api.call(
        operation:   'POST',
        subpath:     "packages/#{package['id']}/transfer_spec/upload",
        headers:     {'Accept' => 'application/json'},
        query:       {transfer_type: Cli::Plugins::Faspex5::TRANSFER_CONNECT},
        body:        {paths: [{'destination'=>'/'}]},
        body_type:   :json
      )[:data]
      transfer_spec.delete('authentication')
      # but we place it in a Faspex package creation response
      return {
        'links'         => { 'status' => 'unused' },
        'xfer_sessions' => [transfer_spec]
      }
    end

    def do_POST(request, response)
      case request.path
      when '/aspera/faspex/send'
        begin
          raise 'no payload' if request.body.nil?
          faspex_pkg_parameters = JSON.parse(request.body)
          Log.log.debug{"faspex pkg create parameters=#{faspex_pkg_parameters}"}
          # compare string, as class is not yet known here
          faspex_package_create_result =
            case @app_api.class.name
            when 'Aspera::Api::AoC'
              faspex4_send_to_aoc(faspex_pkg_parameters)
            when 'Aspera::Rest'
              faspex4_send_to_faspex5(faspex_pkg_parameters)
            else Aspera.error_unexpected_value(@app_api.class.name)
            end
          Log.log.info{"faspex_package_create_result=#{faspex_package_create_result}"}
          response.status = 200
          response.content_type = 'application/json'
          response.body = JSON.generate(faspex_package_create_result)
        rescue => e
          response.status = 500
          response['Content-Type'] = 'application/json'
          response.body = {error: e.message, stacktrace: e.backtrace}.to_json
          Log.log.error(e.message)
          Log.log.debug{e.backtrace.join("\n")}
        end
      else
        response.status = 400
        response['Content-Type'] = 'application/json'
        response.body = {error: 'Unsupported endpoint'}.to_json
      end
    end
  end
end
