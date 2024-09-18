# frozen_string_literal: true

require 'aspera/ascp/installation'
require 'aspera/agent/direct'
require 'aspera/log'
require 'webrick'
require 'json'

module Aspera
  # this class answers the Faspex /send API and creates a package on Aspera on Cloud
  class NodeSimulatorServlet < WEBrick::HTTPServlet::AbstractServlet
    PATH_TRANSFERS = '/ops/transfers'
    PATH_ONE_TRANSFER = %r{/ops/transfers/(.+)$}
    # @param app_api [Api::AoC]
    # @param app_context [String]
    def initialize(server, credentials, transfer)
      super(server)
      @credentials = credentials
      @xfer_manager = Agent::Direct.new
    end

    def do_POST(request, response)
      case request.path
      when PATH_TRANSFERS
        job_id = @xfer_manager.start_transfer(JSON.parse(request.body))
        session = @xfer_manager.sessions_by_job(job_id).first
        result = session[:ts].clone
        result['id'] = job_id
        set_json_response(response, result)
      else
        set_json_response(response, [{error: 'Bad request'}], code: 400)
      end
    end

    def do_GET(request, response)
      case request.path
      when '/info'
        info = Ascp::Installation.instance.ascp_info
        set_json_response(response, {
          application:                           'node',
          current_time:                          Time.now.utc.iso8601(0),
          version:                               info['sdk_ascp_version'].gsub(/ .*$/, ''),
          license_expiration_date:               info['expiration_date'],
          license_max_rate:                      info['maximum_bandwidth'],
          os:                                    %x(uname -srv).chomp,
          aej_status:                            'disconnected',
          async_reporting:                       'yes',
          transfer_activity_reporting:           'yes',
          transfer_user:                         'xfer',
          docroot:                               'file:////data/aoc/eudemo-sedemo',
          node_id:                               '2bbdcc39-f789-4d47-8163-6767fc14f421',
          cluster_id:                            '6dae2844-d1a9-47a5-916d-9b3eac3ea466',
          acls:                                  [],
          access_key_configuration_capabilities: {
            transfer: %w[
              cipher
              policy
              target_rate_cap_kbps
              target_rate_kbps
              preserve_timestamps
              content_protection_secret
              aggressiveness
              token_encryption_key
              byok_enabled
              bandwidth_flow_network_rc_module
              file_checksum_type],
            server:   %w[
              activity_event_logging
              activity_file_event_logging
              recursive_counts
              aej_logging
              wss_enabled
              activity_transfer_ignore_skipped_files
              activity_files_max
              access_key_credentials_encryption_type
              discovery
              auto_delete
              allow
              deny]
          },
          capabilities:                          [
            {name:  'sync', value: true},
            {name:  'watchfolder', value: true},
            {name:  'symbolic_links', value: true},
            {name:  'move_file', value: true},
            {name:  'move_directory', value: true},
            {name:  'filelock', value: false},
            {name:  'ssh_fingerprint', value: false},
            {name:  'aej_version', value: '1.0'},
            {name:  'page', value: true},
            {name:  'file_id_version', value: '2.0'},
            {name:  'auto_delete', value: false}],
          settings:                              [
            {name:  'content_protection_required', value: false},
            {name:  'content_protection_strong_pass_required', value: false},
            {name:  'filelock_restriction', value: 'none'},
            {name:  'ssh_fingerprint', value: nil},
            {name:  'wss_enabled', value: false},
            {name:  'wss_port', value: 443}
          ]})
      when PATH_TRANSFERS
        result = @xfer_manager.sessions.map { |session| job_to_transfer(session) }
        set_json_response(response, result)
      when PATH_ONE_TRANSFER
        job_id = request.path.match(PATH_ONE_TRANSFER)[1]
        set_json_response(response, job_to_transfer(@xfer_manager.sessions_by_job(job_id).first))
      else
        set_json_response(response, [{error: 'Unknown request'}], code: 400)
      end
    end

    def set_json_response(response, json, code: 200)
      response.status = code
      response['Content-Type'] = 'application/json'
      response.body = json.to_json
      Log.log.trace1{Log.dump('response', json)}
    end

    def job_to_transfer(job)
      session = {
        id:                    'bafc72b8-366c-4501-8095-47208183d6b8',
        client_node_id:        '',
        server_node_id:        '2bbdcc39-f789-4d47-8163-6767fc14f421',
        client_ip_address:     '192.168.0.100',
        server_ip_address:     '5.10.114.4',
        status:                'running',
        retry_timeout:         3600,
        retry_count:           0,
        start_time_usec:       1701094040000000,
        end_time_usec:         nil,
        elapsed_usec:          405312,
        bytes_transferred:     26,
        bytes_written:         26,
        bytes_lost:            0,
        files_completed:       1,
        directories_completed: 0,
        target_rate_kbps:      500000,
        min_rate_kbps:         0,
        calc_rate_kbps:        9900,
        network_delay_usec:    40000,
        avg_rate_kbps:         0.51,
        error_code:            0,
        error_desc:            '',
        source_statistics:     {
          args_scan_attempted:  1,
          args_scan_completed:  1,
          paths_scan_attempted: 1,
          paths_scan_failed:    0,
          paths_scan_skipped:   0,
          paths_scan_excluded:  0,
          dirs_scan_completed:  0,
          files_scan_completed: 1,
          dirs_xfer_attempted:  0,
          dirs_xfer_fail:       0,
          files_xfer_attempted: 1,
          files_xfer_fail:      0,
          files_xfer_noxfer:    0
        },
        precalc:               {
          enabled:              true,
          status:               'ready',
          bytes_expected:       0,
          directories_expected: 0,
          files_expected:       0,
          files_excluded:       0,
          files_special:        0,
          files_failed:         1
        }}
      return {
        id:                    '609a667d-642e-4290-9312-b4d20d3c0159',
        status:                'running',
        start_spec:            job[:ts],
        sessions:              [session],
        bytes_transferred:     26,
        bytes_written:         26,
        bytes_lost:            0,
        avg_rate_kbps:         0.51,
        files_completed:       1,
        files_skipped:         0,
        directories_completed: 0,
        start_time_usec:       1701094040000000,
        end_time_usec:         1701094040405312,
        elapsed_usec:          405312,
        error_code:            0,
        error_desc:            '',
        precalc:               {
          status:               'ready',
          bytes_expected:       0,
          files_expected:       0,
          directories_expected: 0,
          files_special:        0,
          files_failed:         1
        },
        files:                 [{
          id:              'd1b5c112-82b75425-860745fc-93851671-64541bdd',
          path:            '/workspaces/45071/packages/bYA_ilq73g.asp-package/contents/data_file.bin',
          start_time_usec: 1701094040000000,
          elapsed_usec:    105616,
          end_time_usec:   1701094040001355,
          status:          'completed',
          error_code:      0,
          error_desc:      '',
          size:            26,
          type:            'file',
          checksum_type:   'none',
          checksum:        nil,
          start_byte:      0,
          bytes_written:   26,
          session_id:      'bafc72b8-366c-4501-8095-47208183d6b8'}]
      }
    end
  end
end
