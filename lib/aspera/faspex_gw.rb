# frozen_string_literal: true

require 'aspera/web_server_simple'
require 'aspera/log'
require 'json'

module Aspera
  # this class answers the Faspex /send API and creates a package on Aspera on Cloud
  class Faspex4AoCServlet < WEBrick::HTTPServlet::AbstractServlet
    def initialize(_server, a_aoc_api_user, a_workspace_id)
      super
      # typed: Aspera::AoC
      @aoc_api_user = a_aoc_api_user
      @aoc_workspace_id = a_workspace_id
    end

    # parameters from user to Faspex API call
    # https://developer.ibm.com/apis/catalog/aspera--aspera-faspex-client-sdk/Sending%20Packages%20(API%20v.3)
    def process_faspex_send(request, response)
      raise 'no payload' if request.body.nil?
      faspex_pkg_parameters = JSON.parse(request.body)
      faspex_pkg_delivery = faspex_pkg_parameters['delivery']
      Log.log.debug{"faspex pkg create parameters=#{faspex_pkg_parameters}"}
      package_data = {
        # 'file_names'   => faspex_pkg_delivery['sources'][0]['paths'],
        'name'         => faspex_pkg_delivery['title'],
        'note'         => faspex_pkg_delivery['note'],
        'recipients'   => faspex_pkg_delivery['recipients'],
        'workspace_id' => @aoc_workspace_id
      }
      created_package = @aoc_api_user.create_package_simple(package_data, true, @new_user_option)
      # but we place it in a Faspex package creation response
      faspex_package_create_result = {
        'links'         => { 'status' => 'unused' },
        'xfer_sessions' => [created_package[:spec]]
      }
      Log.log.info{"faspex_package_create_result=#{faspex_package_create_result}"}
      response.status = 200
      response.content_type = 'application/json'
      response.body = JSON.generate(faspex_package_create_result)
    end

    def do_POST(request, response)
      case request.path
      when '/aspera/faspex/send'
        begin
          process_faspex_send(request, response)
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
  end # Faspex4AoCServlet

  class FaspexGW < WebServerSimple
    # @param endpoint_url [String] https://localhost:12345
    def initialize(uri, a_aoc_api_user, a_workspace_id)
      super(uri)
      mount(uri.path, Faspex4AoCServlet, a_aoc_api_user, a_workspace_id)
    end
  end # FaspexGW
end # AsperaLm
