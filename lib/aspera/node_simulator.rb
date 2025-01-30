# frozen_string_literal: true

require 'aspera/ascp/installation'
require 'aspera/agent/direct'
require 'aspera/log'
require 'webrick'
require 'json'

module Aspera
  class NodeSimulator
    def initialize
      @agent = Agent::Direct.new(management_cb: ->(event){process_event(event)})
      @sessions = {}
    end

    def start(ts)
      @agent.start_transfer(ts)
    end

    def all_sessions
      @agent.sessions.map { |session| session[:job_id] }.uniq.each.map{|job_id|job_to_transfer(job_id)}
    end

    # status: ('waiting', 'partially_completed', 'unknown', 'waiting(read error)',] 'running', 'completed', 'failed'
    def job_to_transfer(job_id)
      jobs = @agent.sessions_by_job(job_id)
      ts = nil
      sessions = jobs.map do |j|
        ts ||= j[:ts]
        {
          id:                    j[:id],
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
          }
        }
      end
      ts ||= {}
      result = {
        id:                    job_id,
        status:                'running',
        start_spec:            ts,
        sessions:              sessions,
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
      Log.log.trace2{Log.dump(:job, result)}
      return result
    end

    # Process event from manegemtn port
    def process_event(event)
      case event['Type']
      when 'NOP' then Aspera.Log.debug{"event not managed: #{event['Type']}"}
      when 'START' then Aspera.Log.debug{"event not managed: #{event['Type']}"}
      when 'QUERY' then Aspera.Log.debug{"event not managed: #{event['Type']}"}
      when 'QUERYRSP' then Aspera.Log.debug{"event not managed: #{event['Type']}"}
      when 'STATS' then Aspera.Log.debug{"event not managed: #{event['Type']}"}
      when 'STOP' then Aspera.Log.debug{"event not managed: #{event['Type']}"}
      when 'ERROR' then Aspera.Log.debug{"event not managed: #{event['Type']}"}
      when 'CANCEL' then Aspera.Log.debug{"event not managed: #{event['Type']}"}
      when 'DONE' then Aspera.Log.debug{"event not managed: #{event['Type']}"}
      when 'RATE' then Aspera.Log.debug{"event not managed: #{event['Type']}"}
      when 'FILEERROR' then Aspera.Log.debug{"event not managed: #{event['Type']}"}
      when 'SESSION' then Aspera.Log.debug{"event not managed: #{event['Type']}"}
      when 'NOTIFICATION' then Aspera.Log.debug{"event not managed: #{event['Type']}"}
      when 'INIT' then Aspera.Log.debug{"event not managed: #{event['Type']}"}
      when 'VLINK' then Aspera.Log.debug{"event not managed: #{event['Type']}"}
      when 'PUT' then Aspera.Log.debug{"event not managed: #{event['Type']}"}
      when 'WRITE' then Aspera.Log.debug{"event not managed: #{event['Type']}"}
      when 'CLOSE' then Aspera.Log.debug{"event not managed: #{event['Type']}"}
      when 'SKIP' then Aspera.Log.debug{"event not managed: #{event['Type']}"}
      when 'ARGSTOP' then Aspera.Log.debug{"event not managed: #{event['Type']}"}
      else Aspera.error_unreachable_line
      end
    end
  end

  # this class answers the Faspex /send API and creates a package on Aspera on Cloud
  # a new instance is created for each request
  class NodeSimulatorServlet < WEBrick::HTTPServlet::AbstractServlet
    PATH_TRANSFERS = '/ops/transfers'
    PATH_ONE_TRANSFER = %r{/ops/transfers/(.+)$}
    PATH_BROWSE = '/files/browse'
    # @param app_api [Api::AoC]
    # @param app_context [String]
    def initialize(server, credentials, simulator)
      super(server)
      @credentials = credentials
      @simulator = simulator
    end

    require 'json'
    require 'time'

    def folder_to_structure(folder_path)
      raise "Path does not exist or is not a directory: #{folder_path}" unless Dir.exist?(folder_path)

      # Build self structure
      folder_stat = File.stat(folder_path)
      structure = {
        'self'  => {
          'path'        => folder_path,
          'basename'    => File.basename(folder_path),
          'type'        => 'directory',
          'size'        => folder_stat.size,
          'mtime'       => folder_stat.mtime.utc.iso8601,
          'permissions' => [
            { 'name' => 'view' },
            { 'name' => 'edit' },
            { 'name' => 'delete' }
          ]
        },
        'items' => []
      }

      # Iterate over folder contents
      Dir.foreach(folder_path) do |entry|
        next if entry == '.' || entry == '..' # Skip current and parent directory

        item_path = File.join(folder_path, entry)
        item_type = File.ftype(item_path) rescue 'unknown' # Get the type of file
        item_stat = File.lstat(item_path) # Use lstat to handle symbolic links correctly

        item = {
          'path'        => item_path,
          'basename'    => entry,
          'type'        => item_type,
          'size'        => item_stat.size,
          'mtime'       => item_stat.mtime.utc.iso8601,
          'permissions' => [
            { 'name' => 'view' },
            { 'name' => 'edit' },
            { 'name' => 'delete' }
          ]
        }

        # Add additional details for specific types
        case item_type
        when 'file'
          item['partial_file'] = false
        when 'link'
          item['target'] = File.readlink(item_path) rescue nil # Add the target of the symlink
        when 'unknown'
          item['note'] = 'File type could not be determined'
        end

        structure['items'] << item
      end

      structure
    end

    def do_POST(request, response)
      case request.path
      when PATH_TRANSFERS
        job_id = @simulator.start(JSON.parse(request.body))
        sleep(0.5)
        set_json_response(request, response, @simulator.job_to_transfer(job_id))
      when PATH_BROWSE
        req = JSON.parse(request.body)
        # req['count']
        set_json_response(request, response, folder_to_structure(req['path']))
      else
        set_json_response(request, response, [{error: 'Bad request'}], code: 400)
      end
    end

    def do_GET(request, response)
      case request.path
      when '/info'
        info = Ascp::Installation.instance.ascp_info
        set_json_response(request, response, {
          application:                           'node',
          current_time:                          Time.now.utc.iso8601(0),
          version:                               info['sdk_ascp_version'].gsub(/ .*$/, ''),
          license_expiration_date:               info['expiration_date'],
          license_max_rate:                      info['maximum_bandwidth'],
          os:                                    %x(uname -srv).chomp,
          aej_status:                            'disconnected',
          async_reporting:                       'no',
          transfer_activity_reporting:           'no',
          transfer_user:                         'xfer',
          docroot:                               'file:////data/aoc/eudemo-sedemo',
          node_id:                               '2bbdcc39-f789-4d47-8163-6767fc14f421',
          cluster_id:                            '6dae2844-d1a9-47a5-916d-9b3eac3ea466',
          acls:                                  ['impersonation'],
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
        set_json_response(request, response, @simulator.all_sessions)
      when PATH_ONE_TRANSFER
        job_id = request.path.match(PATH_ONE_TRANSFER)[1]
        set_json_response(request, response, @simulator.job_to_transfer(job_id))
      else
        set_json_response(request, response, [{error: 'Unknown request'}], code: 400)
      end
    end

    def set_json_response(request, response, json, code: 200)
      response.status = code
      response['Content-Type'] = 'application/json'
      response.body = json.to_json
      Log.log.trace1{Log.dump("response for #{request.request_method} #{request.path}", json)}
    end
  end
end
