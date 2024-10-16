# frozen_string_literal: true

require 'aspera/log'
require 'aspera/rest'

module Aspera
  module Api
    class Ats < Aspera::Rest
      SERVICE_BASE_URL = 'https://ats.aspera.io'
      # currently supported clouds
      # Note to Aspera: shall be an API call
      CLOUD_NAME = {
        aws:       'Amazon Web Services',
        azure:     'Microsoft Azure',
        google:    'Google Cloud',
        limelight: 'Limelight',
        rackspace: 'Rackspace',
        softlayer: 'IBM Cloud'
      }.freeze

      private_constant :CLOUD_NAME

      def initialize
        super(base_url: "#{SERVICE_BASE_URL}/pub/v1")
        # cache of server data
        @all_servers_cache = nil
      end

      def cloud_names; CLOUD_NAME; end

      # all available ATS servers
      # NOTE to Aspera: an API shall be created to retrieve all servers at once
      def all_servers
        if @all_servers_cache.nil?
          @all_servers_cache = []
          CLOUD_NAME.each_key do |name|
            read("servers/#{name.to_s.upcase}").each do |i|
              @all_servers_cache.push(i)
            end
          end
        end
        return @all_servers_cache
      end
    end
  end
end
