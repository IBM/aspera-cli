# frozen_string_literal: true

# cspell:ignore precalc noxfer euid gettime
require 'aspera/assert'
require 'aspera/mime'
require 'aspera/ascp/installation'
require 'aspera/agent/transferd'
require 'aspera/transfer/spec'
require 'aspera/transfer/error'
require 'aspera/secret_hider'
require 'aspera/string_ext'
require 'aspera/log'
require 'webrick'
require 'openssl'
require 'etc'
require 'securerandom'
require 'json'
require 'time'

module Aspera
  # Node API transfers executed by transferd.
  # Only transfers started through the emulator are known (kept in memory).
  class NodeEmulator
    # transferd status → Node API transfer status
    STATUS = {
      UNKNOWN_STATUS: 'waiting',
      QUEUED:         'waiting',
      RUNNING:        'running',
      COMPLETED:      'completed',
      FAILED:         'failed',
      ORPHANED:       'failed',
      CANCELED:       'canceled',
      PAUSED:         'paused'
    }.freeze
    # transferd statuses after which no event is received
    TERMINAL = %i[COMPLETED FAILED CANCELED ORPHANED].freeze
    # Node API statuses of active transfers and sessions
    ACTIVE = %w[waiting running].freeze
    # transferd session status (lowercase) → Node API, others are only lowercased
    SESSION_STATUS = {'draft' => 'waiting'}.freeze
    # transferd file status (lowercase) → Node API, others are only lowercased
    FILE_STATUS = {'transferring' => 'running', 'finished' => 'completed'}.freeze
    # transferd field → Node API field, when not the snake case of it (`nil`: ignored)
    TRANSFER_OVERRIDES = {'averageRateKbps' => 'avg_rate_kbps', 'errorDescription' => 'error_desc'}.freeze
    SESSION_OVERRIDES = {'id' => nil, 'sessionId' => 'id'}.freeze
    FILE_OVERRIDES = {'fileId' => 'id', 'errorDescription' => 'error_desc', 'fileType' => 'type', 'fileChecksumType' => 'checksum_type'}.freeze
    # Node API fields taken as is from transferd (after renaming)
    TRANSFER_FIELDS = %w[bytes_transferred bytes_written bytes_lost avg_rate_kbps files_completed directories_completed elapsed_usec].freeze
    SESSION_FIELDS = %w[
      id client_node_id server_node_id client_ip_address server_ip_address start_time_usec end_time_usec elapsed_usec
      bytes_transferred bytes_written bytes_lost files_completed directories_completed
      target_rate_kbps min_rate_kbps calc_rate_kbps network_delay_usec error_code error_desc
    ].freeze
    FILE_FIELDS = %w[id path start_time_usec elapsed_usec error_code error_desc size type checksum_type checksum start_byte bytes_written session_id].freeze
    # Node API session `source_statistics` field → transferd session field
    SOURCE_STATISTICS = {
      'args_scan_attempted'  => 'arg_scans_attempted',
      'args_scan_completed'  => 'arg_scans_completed',
      'paths_scan_attempted' => 'source_paths_scan_attempted',
      'paths_scan_failed'    => 'source_paths_scan_failed',
      'paths_scan_excluded'  => 'source_paths_scan_excluded',
      'files_scan_completed' => 'source_paths_scan_completed',
      'dirs_scan_completed'  => 'dir_scans_completed',
      'dirs_xfer_attempted'  => 'dir_creates_attempted',
      'dirs_xfer_fail'       => 'dir_creates_failed',
      'files_xfer_attempted' => 'transfers_attempted',
      'files_xfer_fail'      => 'transfers_failed',
      'files_xfer_noxfer'    => 'transfers_skipped'
    }.freeze
    # Node API `precalc` field → transferd session field
    PRECALC = {
      'bytes_expected'       => 'pre_transfer_bytes',
      'files_expected'       => 'pre_transfer_files',
      'directories_expected' => 'pre_transfer_dirs',
      'files_special'        => 'pre_transfer_special'
    }.freeze
    # transferd fills fields `*TimeUsec` (except `elapsedUsec`) with milliseconds: values below are not microseconds
    MAX_MSEC = 10**14
    # Max wait for the first event of a new transfer
    START_TIMEOUT_SEC = 10
    # `File.ftype` → Node API item type, others are unchanged
    FILE_TYPES = {'link' => 'symbolic_link'}.freeze
    # Node API node information not provided by transferd
    # The emulator has no access key, AEJ, watch folder, sync, file id API (gen4), `files/page` or file operations
    INFO_STATIC = {
      'aej_status'                            => 'disconnected',
      'async_reporting'                       => 'no',
      'transfer_activity_reporting'           => 'no',
      'acls'                                  => [],
      'access_key_configuration_capabilities' => {'transfer' => [], 'server' => []},
      'capabilities'                          => [
        {'name' => 'sync', 'value' => false},
        {'name' => 'watchfolder', 'value' => false},
        {'name' => 'symbolic_links', 'value' => false},
        {'name' => 'move_file', 'value' => false},
        {'name' => 'move_directory', 'value' => false},
        {'name' => 'filelock', 'value' => false},
        {'name' => 'ssh_fingerprint', 'value' => false},
        {'name' => 'page', 'value' => false},
        {'name' => 'auto_delete', 'value' => false}
      ],
      'settings'                              => [
        {'name' => 'content_protection_required', 'value' => false},
        {'name' => 'content_protection_strong_pass_required', 'value' => false},
        {'name' => 'filelock_restriction', 'value' => 'none'},
        {'name' => 'ssh_fingerprint', 'value' => nil},
        {'name' => 'wss_enabled', 'value' => false},
        {'name' => 'wss_port', 'value' => 443}
      ]
    }.freeze
    private_constant :STATUS, :TERMINAL, :ACTIVE, :SESSION_STATUS, :FILE_STATUS,
      :TRANSFER_OVERRIDES, :SESSION_OVERRIDES, :FILE_OVERRIDES, :TRANSFER_FIELDS, :SESSION_FIELDS, :FILE_FIELDS,
      :SOURCE_STATISTICS, :PRECALC, :MAX_MSEC, :START_TIMEOUT_SEC, :FILE_TYPES, :INFO_STATIC

    class << self
      # Convert a transferd transfer status to a Node API status
      # @param status [Symbol] transferd `TransferStatus`
      # @return [String] Node API transfer status
      def node_status(status)
        STATUS.fetch(status, 'waiting')
      end

      # Convert a transferd message to a hash with Node API field names
      # @param message   [Google::Protobuf::AbstractMessage] transferd message
      # @param overrides [Hash] field name → Node API name (`nil`: ignored)
      # @return [Hash] all fields (including default values), keys in snake case, time stamps in microseconds
      def message_to_hash(message, overrides)
        message.class.descriptor.each_with_object({}) do |field, hash|
          key = overrides.fetch(field.name) { field.name.capital_to_snake }
          next if key.nil?
          value = message[field.name]
          value *= 1000 if key.end_with?('_time_usec') && value.positive? && value < MAX_MSEC
          hash[key] = value
        end
      end

      # Update a store entry with a transferd event
      # @param entry    [Hash] store entry
      # @param response [Transferd::Api::TransferResponse] transferd event
      def update_entry(entry, response)
        entry[:status] = response.status
        entry[:info] = response.transferInfo unless response.transferInfo.nil?
        session = response.sessionInfo
        entry[:sessions][session.sessionId] = session unless session.nil? || session.sessionId.empty?
        # event ARG_STOP has a file without id
        file = response.fileInfo
        entry[:files][file.fileId] = file unless file.nil? || file.fileId.empty?
        entry[:error] = response.error.description unless response.error.nil? || response.error.description.empty?
        # session information keeps the initial rates, the ascp management message has the current ones
        entry[:rates][session.sessionId] = management_rates(response.message) if response.transferEvent.eql?(:RATE_MODIFICATION) && entry[:sessions].key?(session&.sessionId)
      end

      # Build a Node API transfer from a store entry
      # @param id      [String] transfer id
      # @param entry   [Hash]   store entry
      # @param node_id [String] node id of the emulator
      # @return [Hash] Node API transfer (`transferResponseSessionSpec`)
      def transfer_to_node(id, entry, node_id: '')
        info = message_to_hash(entry[:info] || ::Transferd::Api::TransferInfo.new, TRANSFER_OVERRIDES)
        terminal = TERMINAL.include?(entry[:status])
        retry_timeout = xfer_retry(entry[:start_spec])
        sessions = entry[:sessions].map { |session_id, session| session_to_node(session, retry_timeout: retry_timeout, node_id: node_id).merge(entry[:rates].fetch(session_id, {})) }
        error_desc = info['error_desc'].strip
        error_desc = entry[:error].to_s if error_desc.empty?
        precalc = PRECALC.keys.to_h { |field| [field, sessions.sum { |session| session['precalc'][field] }] }
        info.slice(*TRANSFER_FIELDS).merge(
          'id'              => id,
          'status'          => node_status(entry[:status]),
          'start_spec'      => entry[:start_spec],
          'sessions'        => sessions,
          # transferd does not provide the start time of the transfer
          'start_time_usec' => sessions.map { |session| session['start_time_usec'] }.select(&:positive?).min || 0,
          'end_time_usec'   => terminal ? info['end_time_usec'] : 0,
          'error_code'      => info['error_code'].to_i,
          'error_desc'      => error_desc,
          'precalc'         => precalc.merge(
            'enabled' => sessions.any? { |session| session['precalc']['enabled'] },
            'status'  => precalc_status(precalc['bytes_expected'], terminal)
          ),
          'files'           => entry[:files].values.map { |file| file_to_node(file) }
        )
      end

      # Convert a transferd session to a Node API session
      # @param session       [Transferd::Api::SessionTransferInformation]
      # @param retry_timeout [Integer] from the transfer spec
      # @param node_id       [String]  node id of the emulator
      # @return [Hash] Node API session (`transferResponseSessions`)
      def session_to_node(session, retry_timeout: 0, node_id: '')
        source = message_to_hash(session, SESSION_OVERRIDES)
        status = session.status.downcase
        status = SESSION_STATUS.fetch(status, status)
        result = source.slice(*SESSION_FIELDS)
        # transferd provides the address of the remote side only: the server
        result['server_ip_address'] = source['remote_address'] if result['server_ip_address'].empty?
        # transferd provides the node id of the remote side only: the local side is the emulator
        result['client_node_id'] = node_id if result['client_node_id'].empty?
        precalc = PRECALC.transform_values { |field| source[field] }
        result.merge(
          'status'            => status,
          'retry_count'       => 0,
          'retry_timeout'     => retry_timeout,
          'stalled'           => false,
          'avg_rate_kbps'     => source['elapsed_usec'].positive? ? (source['bytes_transferred'] * 8000.0 / source['elapsed_usec']).round(2) : 0,
          'source_statistics' => SOURCE_STATISTICS.transform_values { |field| source[field] },
          'precalc'           => precalc.merge(
            'enabled' => session.precalc.casecmp?('yes'),
            'status'  => precalc_status(precalc['bytes_expected'], !ACTIVE.include?(status))
          )
        )
      end

      # Convert a transferd file to a Node API file
      # @param file [Transferd::Api::FileTransferInformation]
      # @return [Hash] Node API file (`fileMetadata`)
      def file_to_node(file)
        result = message_to_hash(file, FILE_OVERRIDES).slice(*FILE_FIELDS)
        status = file.status.downcase
        result['status'] = FILE_STATUS.fetch(status, status)
        terminal = !result['status'].eql?('running') && result['start_time_usec'].positive?
        result['end_time_usec'] = terminal ? result['start_time_usec'] + result['elapsed_usec'] : 0
        result
      end

      # Build Node API node information from transferd instance information
      # @param info          [Transferd::Api::InstanceInfo]
      # @param node_id       [String] node id of the emulator
      # @param cluster_id    [String] cluster id of the emulator
      # @param docroot       [String] real path of the docroot
      # @param transfer_user [String] system user executing transfers
      # @return [Hash] Node API node information (`info-get-200`)
      def info_to_node(info, node_id:, cluster_id:, docroot:, transfer_user:)
        ascp = info.asperaInfo.find { |binary| binary.asperaBinary.eql?('ascp') } || ::Transferd::Api::AsperaInfo.new
        license = info.licenseInfo || ::Transferd::Api::LicenseInfo.new
        {
          'application'             => 'node',
          # without build id
          'version'                 => ascp.asperaVersion.sub(/ .*$/, ''),
          'current_time'            => Time.now.utc.iso8601(0),
          'license_expiration_date' => license.license[%r{<expiration_date>([^<]*)</expiration_date>}, 1].to_s,
          'license_max_rate'        => license.maxRate,
          'os'                      => ascp.operatingSystem,
          'node_id'                 => node_id,
          'cluster_id'              => cluster_id,
          'transfer_user'           => transfer_user,
          'docroot'                 => "file:///#{docroot}"
        }.merge(INFO_STATIC)
      end

      private

      # Extract the current rates from an ascp management message
      # @param message [String] ascp management message of event `RATE_MODIFICATION` (JSON)
      # @return [Hash] Node API session rates found in the message
      def management_rates(message)
        management = JSON.parse(message)
        {'target_rate_kbps' => management['Rate'], 'min_rate_kbps' => management['MinRate']}.compact.transform_values(&:to_i)
      rescue JSON::ParserError
        {}
      end

      # Compute the status of the pre-calculation of the transfer size
      # @param bytes_expected [Integer] size of the transfer, 0 if not known yet
      # @param terminal       [Boolean] `true` if the transfer or session has ended
      # @return [String] `ready` when the size is known, else `pending`
      def precalc_status(bytes_expected, terminal)
        bytes_expected.positive? || terminal ? 'ready' : 'pending'
      end

      # Get the retry timeout from the tags of the transfer spec
      # @param start_spec [Hash] transfer spec
      # @return [Integer] retry timeout set by `Agent::Node`, or 0
      def xfer_retry(start_spec)
        reserved = start_spec['tags'][Transfer::Spec::TAG_RESERVED] if start_spec['tags'].is_a?(Hash)
        reserved.is_a?(Hash) ? reserved['xfer_retry'].to_i : 0
      end
    end

    # Create an emulator, start a transferd daemon if no client is given
    # @param docroot         [String, nil]  folder of the node files, default: current folder
    # @param transfer_client [Transferd::Api::TransferService::Stub, nil] gRPC client, default: start a transferd daemon
    # @param retention_sec   [Integer]      time a transfer is kept after it ended (CLI default in schema)
    def initialize(retention_sec:, docroot: nil, transfer_client: nil)
      Aspera.assert(retention_sec.is_a?(Integer) && retention_sec.positive?) { "retention_sec must be a positive integer: #{retention_sec.inspect}" }
      # paths of browse and local paths of transfers are relative to it
      @docroot = File.realpath(docroot || Dir.pwd)
      # the daemon is stopped at exit by the agent
      @transfer_client = transfer_client || Agent::Transferd.new.transfer_client
      @retention_sec = retention_sec
      # transfer id → store entry: `start_spec` (secrets hidden), last `status`, last `info`, `sessions` by id, `files` by id, current `rates` by session id, `error`,
      # `ended` (monotonic time of the end), accessed with `store`
      @transfers = {}
      # WEBrick serves each request in a thread, monitoring runs in threads
      @mutex = Mutex.new
      # identifiers of the simulated node, in node information and in sessions
      @node_id = SecureRandom.uuid
      @cluster_id = SecureRandom.uuid
      # transferd runs as the user of the emulator
      @transfer_user = Etc.getpwuid(Process.euid)&.name || Etc.getlogin.to_s
    end

    # Get the node information
    # @return [Hash] Node API node information, from transferd
    def info
      response = @transfer_client.get_info(::Transferd::Api::InstanceInfoRequest.new)
      Log.dump(:get_info_response, response.to_h, level: :trace2)
      Aspera.assert(response.error.nil? || response.error.description.empty?, type: RuntimeError) { response.error.description }
      self.class.info_to_node(response.info || ::Transferd::Api::InstanceInfo.new, node_id: @node_id, cluster_id: @cluster_id, docroot: @docroot, transfer_user: @transfer_user)
    end

    # List a folder of the docroot
    # @param path  [String]  folder to list, relative to the docroot
    # @param skip  [Integer] number of items to skip (paging)
    # @param count [Integer] max number of items returned (paging)
    # @return [Hash] Node API folder content, paths relative to the docroot
    def browse(path, skip: 0, count: nil)
      folder_path = real_path(path)
      # symbolic links shall not lead out of the docroot
      Aspera.assert(in_docroot?(File.realpath(folder_path))) { "Path outside docroot: #{path}" }
      Aspera.assert(File.directory?(folder_path)) { "Not a folder: #{path}" }
      folder_virtual = virtual_path(folder_path)

      # Build self structure
      folder_stat = File.stat(folder_path)
      structure = {
        'self'  => {
          'path'        => folder_virtual,
          'basename'    => File.basename(folder_path),
          'type'        => 'directory',
          # Node API reports 0 for folders
          'size'        => 0,
          'mtime'       => folder_stat.mtime.utc.iso8601,
          'permissions' => permissions(folder_path)
        },
        'items' => []
      }

      # Iterate over folder contents
      Dir.foreach(folder_path) do |entry|
        next if entry == '.' || entry == '..' # Skip current and parent directory

        item_path = File.join(folder_path, entry)
        item_type = File.ftype(item_path) rescue 'unknown' # Get the type of file
        item_type = FILE_TYPES.fetch(item_type, item_type)
        item_stat = File.lstat(item_path) # Use lstat to handle symbolic links correctly

        item = {
          'path'        => File.join(folder_virtual, entry),
          'basename'    => entry,
          'type'        => item_type,
          'size'        => item_type.eql?('directory') ? 0 : item_stat.size,
          'mtime'       => item_stat.mtime.utc.iso8601,
          'permissions' => permissions(item_path)
        }

        # Add additional details for specific types
        case item_type
        when 'file'
          item['partial_file'] = false
        when 'symbolic_link'
          item['target'] = link_target(item_path)
        when 'unknown'
          item['note'] = 'File type could not be determined'
        end

        structure['items'] << item
      end

      # stable order for paging
      all_items = structure['items'].sort_by { |item| item['basename'] }
      structure['items'] = all_items.drop(skip).first(count || all_items.length)
      structure['item_count'] = structure['items'].length
      structure['total_count'] = all_items.length
      structure
    end

    # Start a transfer, and monitor it in a thread until terminated
    # @param transfer_spec [Hash] transfer spec, local paths relative to the docroot (modified)
    # @return [String] transfer id
    def start(transfer_spec)
      Transfer::Spec.fix_transferd_resume_policy(transfer_spec)
      # deep copy, returned in transfer `start_spec`
      start_spec = SecretHider.instance.deep_remove_secret(JSON.parse(transfer_spec.to_json))
      Log.dump(:start_spec, start_spec)
      request = ::Transferd::Api::TransferRequest.new(
        transferType: ::Transferd::Api::TransferType::FILE_REGULAR,
        config:       ::Transferd::Api::TransferConfig.new,
        transferSpec: apply_docroot(transfer_spec).to_json
      )
      first_event = Thread::Queue.new
      Thread.new { monitor(request, start_spec, first_event) }
      result = first_event.pop(timeout: START_TIMEOUT_SEC)
      raise Transfer::Error, "No event from transferd after #{START_TIMEOUT_SEC}s" if result.nil?
      raise result if result.is_a?(Exception)
      return result
    end

    # Get a transfer started by the emulator
    # @param id [String] transfer id
    # @return [Hash, nil] Node API transfer, `nil` if unknown
    def transfer(id)
      entry = store do |transfers|
        found = transfers[id]
        found&.merge(sessions: found[:sessions].dup, files: found[:files].dup, rates: found[:rates].dup)
      end
      return if entry.nil?
      result = self.class.transfer_to_node(id, entry, node_id: @node_id)
      # transferd gives real paths of local files
      result['files'].each { |file| file['path'] = virtual_path(file['path']) if in_docroot?(file['path']) }
      result
    end

    # List the transfers started by the emulator
    # @param active_only [Boolean, nil] `true`: only waiting or running, `false`: only terminated, `nil`: all
    # @param direction   [String, nil]  `send` or `receive`
    # @param count       [Integer, nil] max number of transfers, oldest first
    # @return [Array<Hash>] Node API transfers
    def transfers(active_only: nil, direction: nil, count: nil)
      # a transfer may expire between the two calls
      result = store(&:keys).filter_map { |id| transfer(id) }
      result.select! { |transfer| ACTIVE.include?(transfer['status']).eql?(active_only) } unless active_only.nil?
      result.select! { |transfer| transfer['start_spec']['direction'].eql?(direction) } unless direction.nil?
      count.nil? ? result : result.first(count)
    end

    # Stop a transfer: its status becomes `canceled` when transferd notifies it
    # @param id [String] transfer id
    # @return [Boolean] `false` if unknown
    def cancel(id)
      return false unless known?(id)
      response = @transfer_client.stop_transfer(::Transferd::Api::StopTransferRequest.new(transferId: [id]))
      Log.dump(:stop_response, response.to_h, level: :trace2)
      result = response.stopResult.find { |info| info.transferId.eql?(id) }
      Aspera.assert(result&.stopped, type: Transfer::Error) { result&.error&.description || 'Transfer not stopped by transferd' }
      true
    end

    # Modify the rates or the policy of a transfer
    # @param id      [String] transfer id
    # @param changes [Hash]   new values of transfer spec fields: `target_rate_kbps`, `min_rate_kbps`, `rate_policy`
    # @return [Boolean] `false` if unknown
    def modify(id, changes)
      return false unless known?(id)
      response = @transfer_client.modify_transfer(::Transferd::Api::TransferModificationRequest.new(transferId: id, transferSpec: changes.to_json))
      Log.dump(:modify_response, response.to_h, level: :trace2)
      Aspera.assert(response.error.nil? || response.error.description.empty?, type: Transfer::Error) { response.error.description }
      true
    end

    private

    # Check if a transfer is known
    # @param id [String] transfer id
    # @return [Boolean] `true` if the transfer was started by the emulator
    def known?(id)
      store { |transfers| transfers.key?(id) }
    end

    # Lock the store, and remove the transfers ended for longer than the retention time
    # @yieldparam transfers [Hash] transfer id → store entry
    # @return [Object] result of the block
    def store
      @mutex.synchronize do
        now = monotonic_time
        @transfers.delete_if { |_, entry| entry.key?(:ended) && now - entry[:ended] >= @retention_sec }
        yield(@transfers)
      end
    end

    # @return [Float] current time in seconds, for durations
    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Convert a Node API path to a real path
    # @param path [String] path relative to the docroot, leading `/` optional
    # @return [String] real path, within the docroot
    def real_path(path)
      # `./` prevents expansion of `~`
      real = File.expand_path("./#{path.to_s.sub(%r{\A/+}, '')}", @docroot)
      Aspera.assert(in_docroot?(real)) { "Path outside docroot: #{path}" }
      real
    end

    # Convert a real path to a Node API path
    # @param real [String] real path within the docroot
    # @return [String] path relative to the docroot, with leading `/`
    def virtual_path(real)
      "/#{real.delete_prefix(@docroot).delete_prefix('/')}"
    end

    # Check if a real path is within the docroot
    # @param real [String] real path
    # @return [Boolean] `true` if the path is the docroot or inside it
    def in_docroot?(real)
      real.eql?(@docroot) || real.start_with?(@docroot.end_with?('/') ? @docroot : "#{@docroot}/")
    end

    # Get the Node API permissions of an item
    # @param real [String] real path within the docroot
    # @return [Array<Hash>] Node API permissions, from the access of the emulator on the item
    def permissions(real)
      names = []
      names.push('view') if File.readable?(real)
      names.push('edit') if File.writable?(real)
      # the docroot itself cannot be deleted
      names.push('delete') if !real.eql?(@docroot) && File.writable?(File.dirname(real))
      names.map { |name| {'name' => name} }
    end

    # Get the Node API target of a symbolic link
    # @param link [String] real path of a symbolic link within the docroot
    # @return [Hash] Node API target of the link: only the content of the link if it is dangling or leads out of the docroot
    def link_target(link)
      target = File.realpath(link) rescue nil
      unless target && in_docroot?(target)
        content = File.readlink(link)
        return {'path' => content, 'basename' => File.basename(content)}
      end
      stat = File.stat(target)
      {
        'path'     => virtual_path(target),
        'basename' => File.basename(target),
        'type'     => File.ftype(target),
        'size'     => stat.directory? ? 0 : stat.size
      }
    end

    # Local paths of the transfer spec (sources for `send`, destination for `receive`) are relative to the docroot
    # @param transfer_spec [Hash] modified: local paths are replaced with real paths
    # @return [Hash] the transfer spec
    def apply_docroot(transfer_spec)
      receive = transfer_spec['direction'].eql?(Transfer::Spec::DIRECTION_RECEIVE)
      root_field, path_field = receive ? %w[destination_root destination] : %w[source_root source]
      # a download without destination goes to the docroot
      root = transfer_spec[root_field] || ('/' if receive)
      if root.nil?
        transfer_spec['paths']&.each { |item| item[path_field] = real_path(item[path_field]) if item.key?(path_field) }
      else
        transfer_spec[root_field] = real_path(root)
        # paths are relative to the root: they shall not lead out of the docroot
        transfer_spec['paths']&.each { |item| real_path(File.join(root, item[path_field])) if item.key?(path_field) }
      end
      transfer_spec
    end

    # Start the transfer and update the store with its events, until terminated.
    # Runs in a thread.
    # @param request     [Transferd::Api::TransferRequest]
    # @param start_spec  [Hash] transfer spec without secrets
    # @param first_event [Thread::Queue] receives the transfer id, or the exception if the transfer could not start
    def monitor(request, start_spec, first_event)
      id = nil
      @transfer_client.start_transfer_with_monitor(request) do |response|
        Log.dump(:transferd_event, response.to_h, level: :trace2)
        new_transfer = id.nil?
        if new_transfer
          Aspera.assert(!response.transferId.empty?, type: Transfer::Error) { response.error&.description || 'No transfer id from transferd' }
          id = response.transferId
        end
        store do |transfers|
          entry = (transfers[id] ||= {start_spec: start_spec, sessions: {}, files: {}, rates: {}})
          self.class.update_entry(entry, response)
          # no more event, and so no more retry: retention starts
          entry[:ended] = monotonic_time if TERMINAL.include?(entry[:status])
        end
        first_event.push(id) if new_transfer
        break if TERMINAL.include?(response.status)
      end
      first_event.push(Transfer::Error.new('transferd closed the stream without event')) if id.nil?
    rescue StandardError => e
      if id.nil?
        first_event.push(e)
      else
        Log.log.error { "Transfer #{id}: #{e.message}" }
        store { |transfers| transfers[id].merge!(status: :FAILED, error: e.message, ended: monotonic_time) }
      end
    end
  end

  # Answers a subset of the Node API, transfers are delegated to a NodeEmulator
  # a new instance is created for each request
  class NodeEmulatorServlet < WEBrick::HTTPServlet::AbstractServlet
    PATH_TRANSFERS = '/ops/transfers'
    PATH_ONE_TRANSFER = %r{/ops/transfers/(.+)$}
    PATH_BROWSE = '/files/browse'
    REALM = 'Aspera Node Emulator'
    # `PUT` values of `status` that cancel the transfer (pause and resume are not supported)
    CANCEL_STATUSES = %w[canceled cancelled stopped].freeze
    # `PUT` fields modified by transferd
    MODIFIABLE = %w[target_rate_kbps min_rate_kbps rate_policy].freeze
    # Create the servlet, with optional Basic authentication
    # @param server    [WEBrick::HTTPServer]
    # @param config    [Hash] `username` and `password` (Basic authentication expected from clients, optional)
    # @param simulator [NodeEmulator]
    def initialize(server, config, simulator)
      super(server)
      @simulator = simulator
      @expected_auth = "#{config[:username]}:#{config[:password]}" unless config[:username].nil?
    end

    # Check authentication, dispatch to `do_<verb>`, and send errors in Node API format
    # @param request  [WEBrick::HTTPRequest]
    # @param response [WEBrick::HTTPResponse]
    def service(request, response)
      unless authorized?(request)
        response['WWW-Authenticate'] = %Q(Basic realm="#{REALM}")
        return set_error(request, response, 401, 'Invalid or missing credentials')
      end
      super
    rescue WEBrick::HTTPStatus::Error => e
      set_error(request, response, e.code, e.message)
    rescue JSON::ParserError, AssertError, Transfer::Error => e
      set_error(request, response, 400, e.message)
    rescue Errno::ENOENT => e
      set_error(request, response, 404, e.message)
    rescue StandardError => e
      Log.log.error { "#{request.request_method} #{request.path}: #{e.class}: #{e.message}" }
      set_error(request, response, 500, e.message)
    end

    # Start a transfer, or list a folder
    # @param request  [WEBrick::HTTPRequest]
    # @param response [WEBrick::HTTPResponse]
    def do_POST(request, response)
      case request.path
      when PATH_TRANSFERS
        set_json_response(request, response, @simulator.transfer(@simulator.start(JSON.parse(request.body))))
      when PATH_BROWSE
        req = JSON.parse(request.body)
        set_json_response(request, response, @simulator.browse(req['path'] || '/', skip: req['skip'].to_i, count: req['count']&.to_i))
      else
        set_error(request, response, 404, "Unknown path: #{request.path}")
      end
    end

    # Get the node information, the list of transfers, or one transfer
    # @param request  [WEBrick::HTTPRequest]
    # @param response [WEBrick::HTTPResponse]
    def do_GET(request, response)
      case request.path
      when '/info'
        set_json_response(request, response, @simulator.info)
      when PATH_TRANSFERS
        set_json_response(request, response, @simulator.transfers(
          active_only: query_boolean(request, 'active_only'),
          direction:   request.query['direction']&.to_s,
          count:       query_positive(request, 'count')
        ))
      when PATH_ONE_TRANSFER
        transfer = @simulator.transfer(request.path.match(PATH_ONE_TRANSFER)[1])
        if transfer.nil?
          set_error(request, response, 404, 'Unknown transfer')
        else
          set_json_response(request, response, transfer)
        end
      else
        set_error(request, response, 404, "Unknown path: #{request.path}")
      end
    end

    # Modify a transfer, or cancel it with `status`
    # @param request  [WEBrick::HTTPRequest]
    # @param response [WEBrick::HTTPResponse]
    def do_PUT(request, response)
      id = transfer_id(request)
      changes = JSON.parse(request.body.to_s)
      raise WEBrick::HTTPStatus::BadRequest, 'Body must be a JSON object' unless changes.is_a?(Hash)
      status = changes.delete('status')
      if status.nil?
        unsupported = changes.keys - MODIFIABLE
        raise WEBrick::HTTPStatus::BadRequest, "Cannot modify: #{unsupported.join(', ')}" unless unsupported.empty?
        raise WEBrick::HTTPStatus::BadRequest, 'Nothing to modify' if changes.empty?
        found = @simulator.modify(id, changes)
      else
        raise WEBrick::HTTPStatus::BadRequest, "Unsupported status: #{status}" unless CANCEL_STATUSES.include?(status)
        found = @simulator.cancel(id)
      end
      return set_error(request, response, 404, 'Unknown transfer') unless found
      set_json_response(request, response, @simulator.transfer(id))
    end

    # Node API cancels a transfer with HTTP verb `CANCEL`
    # @param request  [WEBrick::HTTPRequest]
    # @param response [WEBrick::HTTPResponse]
    def do_CANCEL(request, response)
      return set_error(request, response, 404, 'Unknown transfer') unless @simulator.cancel(transfer_id(request))
      response.status = 204
    end

    private

    # Extract the transfer id from the path of the request
    # @param request [WEBrick::HTTPRequest]
    # @return [String] transfer id
    # @raise [WEBrick::HTTPStatus::NotFound] if the path is not the one of a transfer
    def transfer_id(request)
      match = request.path.match(PATH_ONE_TRANSFER)
      raise WEBrick::HTTPStatus::NotFound, "Unknown path: #{request.path}" if match.nil?
      match[1]
    end

    # Read a boolean query parameter
    # @param request [WEBrick::HTTPRequest]
    # @param name    [String] name of the query parameter
    # @return [Boolean, nil] value, `nil` if absent
    # @raise [WEBrick::HTTPStatus::BadRequest] if the value is not `true` or `false`
    def query_boolean(request, name)
      value = request.query[name]&.to_s
      return if value.nil?
      raise WEBrick::HTTPStatus::BadRequest, "Query #{name} must be true or false: #{value}" unless %w[true false].include?(value)
      value.eql?('true')
    end

    # Read a positive integer query parameter
    # @param request [WEBrick::HTTPRequest]
    # @param name    [String] name of the query parameter
    # @return [Integer, nil] value, `nil` if absent
    # @raise [WEBrick::HTTPStatus::BadRequest] if the value is not a positive integer
    def query_positive(request, name)
      value = request.query[name]&.to_s
      return if value.nil?
      number = Integer(value, exception: false)
      raise WEBrick::HTTPStatus::BadRequest, "Query #{name} must be a positive integer: #{value}" unless number&.positive?
      number
    end

    # Set error body in Node API format
    # @param request  [WEBrick::HTTPRequest]
    # @param response [WEBrick::HTTPResponse]
    # @param code     [Integer] HTTP status code
    # @param message  [String]  message for the user
    def set_error(request, response, code, message)
      set_json_response(request, response, {error: {code: code, reason: WEBrick::HTTPStatus.reason_phrase(code), user_message: message}}, code: code)
    end

    # Check the Basic credentials of the request
    # @param request [WEBrick::HTTPRequest]
    # @return [Boolean] `true` if the request has the expected Basic credentials, or if none are expected
    def authorized?(request)
      return true if @expected_auth.nil?
      scheme, value = request['Authorization'].to_s.split(' ', 2)
      # constant time comparison
      scheme.to_s.casecmp?('Basic') && OpenSSL.secure_compare(value.to_s.unpack1('m'), @expected_auth)
    end

    # Set the status and the JSON body of the response
    # @param request  [WEBrick::HTTPRequest] for the log
    # @param response [WEBrick::HTTPResponse]
    # @param json     [Hash, Array] body of the response
    # @param code     [Integer] HTTP status code
    def set_json_response(request, response, json, code: 200)
      response.status = code
      response['Content-Type'] = Mime::JSON
      response.body = json.to_json
      Log.log.trace1 { Log.obj_dump("response for #{request.request_method} #{request.path}", json) }
    end
  end
end
