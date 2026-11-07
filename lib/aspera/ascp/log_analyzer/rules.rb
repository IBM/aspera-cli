# frozen_string_literal: true

# cspell:ignore alloc ossl aspmover bdrate brcvd dups rcvd sndr aspsimplesync astokengen fdlimit filewrite pulseaudio sesserr varation
module Aspera
  module Ascp
    class LogAnalyzer
      # Timestamp at beginning of log line: `May 29 06:53:47` (syslog) or `2017-05-24 02:33:56` (log file)
      LINE_TIME = /^((?:\w+\s+\d+|\d+-\d+-\d+)\s+\d\d:\d\d:\d\d)/
      # Timestamp of sessions and samples
      STAMP = /^(.*?(?:\s+\d+[^:])?\s+\d\d:\d\d:\d\d)/
      # Process identifier: `ascp[1234]` (syslog) or `[4c58-140234]` (log file: process-thread)
      PID = /^.*?\[(\w+)(?:-\w+)?\]/
      # Error message: `ascp[1234]: ERR <message>` or `[4c58-140234] ERR <message>`
      LOG_ERROR = /\]:?\s+ERR\s+(.+)/
      # Process name in syslog line: `host ascp[1234]:` (none in `ascp` log files)
      PROCESS = /\s([\w.-]+)\[\d+\]:/
      # Processes whose lines are analyzed (other processes: only time is used)
      ASCP_PROCESS = /\Aascp\d*\z/
      # Lines that are never relevant: containing one of these texts, or matching
      IGNORED_TEXTS = [
        'async[', 'LOG Queue:', 'snmpd', 'asconfigurator', 'asuserdata', 'message repeated', 'asperacentral', 'ERR Unrecognized FASP TLV',
        'LOG fdlimit set', 'astokengen', 'varation_index', 'LOG brtt', 'Action command:', 'meta_cmp_attrs:'
      ].freeze
      IGNORED_LINES = Regexp.union(/pulseaudio\[\d+\]/, /\s+DBG\s+/, /10061$/, /kernel:(?!\s*ascp)/, /sshd.*?Failed password/)
      # Lines of other Aspera processes, when they contain the PID
      OTHER_PROCESSES = /prepost|aspmover|aspsimplesync/
      SESSION_START_STOP = /#{STAMP.source}.*?Session\s+(Start|Stop)/
      ERRSTR = /errstr="([^"]*)"(?:.*?errstr="([^"]*)")?/
      # Error code and message of `Session Stop`: local, then peer
      ERRCODE = /errcode=(\d+) errstr="([^"]*)"/
      # Transport ciphers (`FASP_TRANSPORT_CIPHER_*` of ascp), by identifier
      CIPHERS = %w[none aes-128 aes-192 aes-256 aes-128-cfb aes-192-cfb aes-256-cfb aes-128-gcm aes-192-gcm aes-256-gcm].freeze
      # `Session Params` field => session data
      SESSION_PARAMS = {
        'user' => :user, 'targetrate' => :target_rate, 'minrate' => :min_rate, 'rate_policy' => :policy, 'cipher' => :secure,
        'resume' => :resume, 'ovr' => :overwrite, 'rd_sz' => :read_block_size, 'wr_sz' => :write_block_size,
        'xfer_id' => :xfer_id, 'cluster_num_nodes' => :cluster_nodes, 'cluster_node_id' => :cluster_node
      }.freeze
      # License in `Initializing FASP version` line: maximum rate in Mbps (none if unlimited), expiry date (none if no expiry)
      LICENSE_RATE = /\bmax rate=(\d+) Mbps/
      LICENSE_EXPIRES = /\blicense expires on (\w{3} \w{3} +\d+ [\d:]+ \d{4})/
      AS_BUF_IO = /ERR as_buf_io:\s+IO/
      SERVER_MGMT_RESET = {set: %i[server_management_connection_reset], clear: %i[peer_abort]}.freeze
      DATA_TIMEOUT = %i[data_transfer_timeout].freeze

      # Log line conditions, and their effect on the session. Only the first matching rule applies.
      # match: Regexp, or Array of Regexp that must all match
      # set: flags to set, clear: flags to clear, error: session error, status: session status
      # unless: flags that cancel the effect, call: method of LogFile called with (session, MatchData)
      # No effect: line is recognized, so that a later rule does not match it
      LINE_RULES = [
        [/\sLOG (?:IBM )?(Aspera [\w -]+?) version \d/,                              {call: :product_name}],
        [/\sLOG ASPERA_AUTH_TOKEN is set to TOKEN/,                                  {call: :token_auth}],
        [/\sLOG Node storage access_key=/,                                           {call: :node_auth}],
        [/end File Transfer statistics/,                                            {call: :end_of_statistics}],
        [/(?:Receiver|Sender)\s+bl\b/,                                              {call: :add_sample}],
        [/LOG Falling back to HTTP/,                                                {set: %i[http_fallback]}],
        [/Transfer\s+Stop\s+(.*)/,                                                  {call: :transfer_stop}],
        [/base\s+RTT\s+reset/,                                                      {call: :brtt_reset}],
        [/(Peer requested|Negotiated) rate params.*?target_rate\s+(\d+)\s+min_rate\s+(\d+)\s+(?:transfer_)?policy\s+(\w+)/, {call: :rate_params}],
        [/pMTU:\s+(\d+).*?start_brtt:\s(\d+)/, {call: :path_mtu}],
        [/server configuration specifies transit encryption cipher (\d+), user requests (\d+)/, {call: :cipher_override}],
        [/Downgrading resume policy to (\S+)/, {call: :resume_downgrade}],
        [/changing session job size from (\d+) to (\d+) to match server configuration/, {call: :job_size_change}],
        [/vlink init: id=(\d+), type=(\w+), capacity=(\d+)/,                        {call: :vlink_init}],
        [/datagram size\s+(\d+)B, block size (\d+)B(?:, path MTU (\d+)B)?/,         {call: :datagram_size}],
        [/User aborted session/,                                                    {set: %i[user_abort]}],
        [/FASP session cancelled/,                                                  {set: %i[user_abort]}],
        [/ERR Server unable to hear from client/i,                                  {set: %i[server_nohear_client]}],
        [/ERR Client unable to connect to server/i,                                 {set: %i[client_nohear_server]}],
        [/ERR.*?Token expired\s+\d+\s+seconds ago/i,                                {set: %i[token_expired]}],
        [/ERR\s+Invalid argument/i,                                                 {set: %i[invalid_argument]}],
        [/ERR\sInvalid configuration file/i,                                        {set: %i[invalid_conf_file]}],
        [/ERR Disk read failed/i,                                                   {set: %i[read]}],
        [/ERR Disk write failed/i,                                                  {set: %i[write]}],
        [/Timeout receiving data \(60 sec\)/,                                       {set: %i[receiver_data_transfer_timeout] + DATA_TIMEOUT, error: 'Receiver data transfer timeout'}],
        [/Timeout establishing UDP connection/,                                     {set: %i[timeout_establishing_udp_connection]}],
        [/ERR failed to find a valid pair of \(pMTU, brtt\)/,                       {set: %i[timeout_establishing_udp_connection]}],
        [/bind udp socket failed/,                                                  {set: %i[bind_udp_socket_failed]}],
        [/ERR Sender network failure \(UDP recv got "No route to host"\)/,          {set: %i[send_no_route]}],
        [/Transmitter inactivity timer fired/,                                      {set: %i[inactivity_timer_fired] + DATA_TIMEOUT, error: 'Data transfer timeout - inactivity timer fired'}],
        [/fc_filewrite_sz:.*errno=11672/,                                           {set: %i[device_not_connected]}],
        [/fc_filewrite_sz:.*errno=(?:28|39|112)/,                                   {set: %i[out_of_disk]}],
        [/fc_filewrite_sz:.*errno=59/,                                              {set: %i[net_error]}],
        [/ReadFile failed.*error=53/,                                               {set: %i[net_path_not_found]}],
        [/fc_filewrite_sz:.*errno=64/,                                              {set: %i[net_name_gone]}],
        [/errno=1450/,                                                              {set: %i[out_of_resources]}],
        [/errcode\s+-2009/,                                                         {set: %i[decryption_error]}],
        [/Insufficient system resources/,                                           {set: %i[out_of_resources]}],
        [/ERR Could not open.*?errno 32/,                                           {set: %i[sharing_violation], error: 'Sharing violation'}],
        [/Insufficient permissions/,                                                {set: %i[insufficient_permissions], unless: %i[sharing_violation]}],
        [/ERR fc_create: failed to alloc cache/,                                    {set: %i[out_of_memory]}],
        [/ERR fc_filewrite_sz: Could not write cache bytes/,                        {set: %i[disk_write_failed]}],
        [/ERR Server requires content protection/,                                  {set: %i[content_protection]}],
        [/ERR required management connection to localhost:\d+/,                     {set: %i[cannot_connect_to_management_socket]}],
        [/ERR Failed to connect to management socket, exiting/,                     {set: %i[cannot_connect_to_management_socket], status: 'failed', error: 'Cannot connect to management socket'}],
        [/ERR aspera.conf parsing error\)?(.*)/,                                    {call: :conf_parse_error}],
        [/ERR\s+Mandatory management socket localhost:\d+, Connection reset by peer\s+\(server\)/, SERVER_MGMT_RESET],
        [/ERR.*?Mandatory management socket localhost:\d+, An existing connection was forcibly closed by the remote host.\s+\(server\)/, SERVER_MGMT_RESET],
        [/ERR Cannot read from management socket localhost.*?server/,               SERVER_MGMT_RESET],
        [/ERR\s+Server aborted session: Failed to connect to management socket/,    SERVER_MGMT_RESET],
        [/ERR\s+Cannot write to management socket\s+localhost:\d+.*?Broken pipe.*?server/, SERVER_MGMT_RESET],
        [/ERR\s+Cannot write to management socket\s+localhost:\d+.*?Broken pipe/, {}],
        [/ERR cannot write to management socket localhost:\d+, Unknown error \(server\)/, {set: %i[server_management_connection_reset]}],
        [/ERR\s+Cannot write to management socket localhost:\d+.*\(client\)/, {set: %i[client_management_connection_reset]}],
        [/ERR PEER ABORT: Received sesserr notification from peer, reason FASP_ABORT_LOCAL/, {set: %i[peer_abort]}],
        [/ERR Peer aborted session/,                                                {set: %i[peer_abort]}],
        [/ERR Mandatory management socket localhost:\d+, Connection reset by peer/, {}],
        [/ERR Cannot read from management socket localhost:\d+, Connection reset by peer/, {}],
        [/ERR Cannot read from management socket localhost.*?client/,               {set: %i[client_management_connection_lost]}],
        [/ERR Server aborted session: Cannot connect to management port localhost/, {set: %i[server_management_connection_reset]}],
        [[AS_BUF_IO, /errno=10054/],                                                {set: %i[remote_reset]}],
        [[AS_BUF_IO, /errno=10053/],                                                {set: %i[local_reset]}],
        [[AS_BUF_IO, /errno=10055/],                                                {set: %i[no_buffer_mem], error: 'Out of buffer memory'}],
        [AS_BUF_IO,                                                                 {set: %i[as_buf_io]}],
        [/ERR Connection lost in midst of data session/,                            {set: %i[ssh_timeout]}],
        [/\[asssh\] SSH connection startup failed/,                                 {set: %i[ssh_startup_failed]}],
        [/\[asssh\] failure during public-key authentication/,                      {set: %i[ssh_key_authentication]}],
        [/\[asssh\] SSH session open failed/,                                       {set: %i[ssh_session_failed]}],
        [/Failed to start remote command, libssh2 result/,                          {set: %i[ssh_command_failed]}],
        [%r{\[asssh\] Remote failed to forward TCP/IP},                             {set: %i[ssh_forward_failed]}],
        [/\[asssh\] (?:channel|session) [a-z ]+ rc=-?\d+/,                          {call: :ssh_disconnect_error}],
        [/speed exceeded/,                                                          {set: %i[exceeded]}],
        [/segfault/,                                                                {call: :segfault}],
        [/(Receiver|Sender) has not received a packet for (\d+) seconds/,           {call: :no_data}],
        [/ERR \S*ossl-modules not found/,                                           {set: %i[ossl_modules_missing]}],
        [/ERR Warning: unable to submit change event/,                              {set: %i[change_event_failed]}],
        [/Warning: rex timer overflow auto-adjusted/,                               {call: :rex_timer_overflow}],
        [/\bFASP Session Statistics \[\w+\] (.*)/,                                  {call: :session_statistics}]
      ].freeze

      # When the session stop error is `Undefined`: first matching flag sets the error
      UNDEFINED_ERROR_RULES = [
        [%i[invalid_conf_file], {}],
        [%i[send_no_route],     {error: 'No route to host'}],
        [%i[peer_abort],        {error: 'Peer aborted session'}]
      ].freeze

      # Session stop errors of failed sessions, refined with flags: first matching rule applies
      ERROR_REFINEMENTS = {
        'No error' => [
          [%i[write],                              {error: 'Disk write failed'}],
          [%i[client_management_connection_reset], {error: 'Client connection to management socket reset'}],
          [%i[client_management_connection_lost],  {error: 'Client management connection lost'}],
          [%i[user_abort],                         {error: 'User aborted session'}],
          [%i[peer_abort],                         {error: 'Peer aborted session'}]
        ]
      }.freeze

      # Sample lines: `Receiver bl t/o/r/d/ts/c/h=1/2/3/4/5/6/7 rex_rtt l/h/s/o=...`: group, field names, values
      SAMPLE = /#{STAMP.source}.*?\[(\w+)(?:-\w+)?\].*?(Receiver|Sender)\s+(bl\b.*)/
      # Sample value => path in sample records
      SAMPLE_COMMON = {
        blocks: %w[bl t], orig: %w[bl o], rex: %w[bl r], target_rate: %w[rate t], min_rate: %w[rate m], calc_rate: %w[rate c],
        tx_bytes: %w[prog t], written: %w[prog f], elapsed_us: %w[prog e]
      }.freeze
      RECEIVER_SAMPLE = SAMPLE_COMMON.merge(
        rex_srtt: %w[rex_rtt s], brtt: %w[rate_rtt b], rtt_high: %w[rate_rtt h], srtt: %w[rate_rtt s], brtt_resets: %w[rate_rtt r],
        rex_count: %w[rex n], lost: %w[bl2 l], ooo: %w[bl2 o], ring_high: %w[disk h], ring_full: %w[disk b],
        net_rate: %w[rate n], vlink_local: %w[rate vl], vlink_remote: %w[rate vr], disk_rate: %w[rate r]
      ).freeze
      # Sender: rates of the receiver (ascp 4): network, virtual links, disk
      SENDER_SAMPLE = SAMPLE_COMMON.merge(
        rex_received: %w[rex b], rex_count: %w[rex n],
        peer_net_rate: %w[rate n], peer_vlink_local: %w[rate vl], peer_vlink_remote: %w[rate vr], peer_disk_rate: %w[rate r]
      ).freeze
    end
  end
end
