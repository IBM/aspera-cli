# frozen_string_literal: true

require 'aspera/web_server_simple'
require 'aspera/log'
require 'json'

module Aspera
  # this class answers the Faspex /send API and creates a package on Aspera on Cloud
  class Faspex4GWServlet < WEBrick::HTTPServlet::AbstractServlet
    # @param app_api [Aspera::AoC]
    # @param app_context [String]
    def initialize(_server, app_api, app_context)
      super
      # typed: Aspera::AoC
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
      created_package = @app_api.create_package_simple(package_data, true, @new_user_option)
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
      package = @app_api.create('packages', package_data)[:data]
      # TODO: option to send from remote source or httpgw
      transfer_spec = @app_api.call(
        operation:   'POST',
        subpath:     "packages/#{package['id']}/transfer_spec/upload",
        headers:     {'Accept' => 'application/json'},
        url_params:  {transfer_type: Aspera::Cli::Plugins::Faspex5::TRANSFER_CONNECT},
        json_params: {paths: [{'destination'=>'/'}]}
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
          faspex_package_create_result =
            if @app_api.is_a?(Aspera::AoC)
              faspex4_send_to_aoc(faspex_pkg_parameters)
            elsif @app_api.is_a?(Aspera::Rest)
              faspex4_send_to_faspex5(faspex_pkg_parameters)
            else
              raise "No such adapter: #{@app_api.class}"
            end
          Log.log.info{"faspex_package_create_result=#{faspex_package_create_result}"}
          response.status = 200
          response.content_type = 'application/json'
          response.body = JSON.generate(faspex_package_create_result)
        rescue => e
          response.status = 500
          response['Content-Type'] = 'application/json'
          response.body = {error: e.message}.to_json
          Log.log.error(e.message)
        end
      else
        response.status = 400
        response['Content-Type'] = 'application/json'
        response.body = {error: 'Bad request'}.to_json
      end
    end
  end # Faspex4GWServlet
end # AsperaLm
