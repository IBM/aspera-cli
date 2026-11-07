# frozen_string_literal: true

# cspell:words nohear overdriven

module Aspera
  module Ascp
    class LogAnalyzer
      # Advice shared by several diagnostics
      udp_port = 'Open the FASP UDP port in the firewalls and NAT devices on the path, for both directions, then retry: SSH (TCP) alone is not enough. ' \
        'The port is 33001 by default (option `-O` of `ascp`, parameter `bind_udp_port` in `transfer/protocol_options` of `aspera.conf` of the server).'
      udp_flow = 'Check that no firewall or NAT device on the path drops the UDP flow (flood protection) or closes it after a timeout, and that the link was not interrupted. ' \
        'Then retry the transfer, with resume (option `-k` of `ascp`).'
      lower_rate = 'Lower the target rate (option `-l` of `ascp`, or `target_rate` in `bandwidth/flow` of `aspera.conf`) to the capacity of the path, or use fair policy (`--policy=fair`).'
      lower_min = 'Lower the minimum rate (option `-m` of `ascp`, or `min_rate` in `bandwidth/flow` of `aspera.conf`): with fair policy, the minimum rate should stay low.'
      storage_write = 'Check the write speed of the storage of the receiver. Use fair policy, so that storage rate control (`storage_rc/adaptive` in `file_system` of `aspera.conf`) can lower the rate. ' \
        'Write parameters can be tuned: `write_threads` and `write_block_size` in `file_system` of `aspera.conf`, option `-G` of `ascp`.'
      tcp_connection = 'Check that no firewall or NAT device on the path closes or resets the TCP connection of the SSH session, and the stability of the network.'
      storage_access = 'Check that the storage is available and healthy, has free space, and that the transfer user has the permissions on it, then retry.'
      network_storage = 'Check the availability of the network storage (share, mapped drive) and of its network connection, then retry.'
      # Diagnostic identifier => action to take (English text, like messages of diagnostics).
      # Only for diagnostics on which the user can act. See also `NO_RECOMMENDATION`.
      # Not for `error_<category>` (the message of the diagnostic is already the hint for the category of the error: `SessionErrors::CATEGORIES`).
      RECOMMENDATIONS = {
        client_nohear_server:                udp_port,
        server_nohear_client:                udp_port,
        timeout_establishing_udp_connection: udp_port,
        http_fallback:                       "The transfer used HTTP instead of UDP, which is slower (unless forced with option `-yF` of `ascp`). #{udp_port}",
        receiver_data_transfer_timeout:      udp_flow,
        inactivity_timer_fired:              udp_flow,
        reception_interruption:              udp_flow,
        udp_flood_protection:                "Check the UDP flood protection of firewalls, and the rate limits of the path. #{lower_rate}",
        low_efficiency:                      "Retransmissions come from packet loss. #{lower_rate}",
        network_overdriven:                  "#{lower_rate} Check the path for a device that limits or polices the rate.",
        network_overdrive:                   "#{lower_rate} Check the path for shallow queues, or a device that limits the rate of UDP.",
        retransmission_buffer_full:          "#{lower_rate} Check the path for a device that limits or polices the rate.",
        control_message_loss:                "Control messages travel over UDP: their loss shows packet loss on the path. #{lower_rate}",
        feedback_interruption:               udp_flow,
        rex_timer_overflow:                  "The retransmission RTT was excessive: check the path for deep queues, congestion or a clock problem. #{lower_rate}",
        license_rate_limit:                  'Use a license with a higher maximum rate on this system (contact your IBM Aspera representative), or set the target rate to the limit of the license ' \
          '(option `-l` of `ascp`, or `target_rate` in `bandwidth/flow` of `aspera.conf`).',
        license_expiry:                      'Renew the license of this system before its expiry date (contact your IBM Aspera representative).',
        stuck_nack:                          "Packet loss prevents the retransmission requests from being served. #{lower_rate}",
        min_rate_high:                       lower_min,
        min_rate_overdrive:                  lower_min,
        slow_storage_loss:                   storage_write,
        slow_disk_write:                     storage_write,
        disk_buffers:                        storage_write,
        disk_write_speed_exceeded:           storage_write,
        storage_overdrive:                   storage_write,
        slow_storage_read:                   'Check the read speed of the storage of the sender. Read parameters can be tuned: `read_threads` and `read_block_size` in `file_system` of `aspera.conf`, option `-g` of `ascp`.',
        rate_decline:                        "Check for other traffic on the link, and for slow storage on the receiver. #{lower_rate}",
        small_files:                         'Aggregate small files into archives before transfer (`-A zip` of `ascp`), or use a protocol that amortizes the per-file overhead (e.g., HTTP/2 multipart). ' \
          'For many small files, enable concurrent file opens: `write_threads` in `file_system` of `aspera.conf`.',
        reverse_path_skew:                   'If the network is not congested, set `rtt_reverse_infer` to `false` in `transfer/protocol_options` of `aspera.conf`: each peer reads its own `aspera.conf`.',
        clock_problem:                       'Set `rtt_autocorrect` to `true` in `transfer/protocol_options` of `aspera.conf` (auto-correction of the base RTT, for virtual machines), and check the clock of the virtual machine.',
        peer_clock_problem:                  'Ask the administrator of the peer to set `rtt_autocorrect` to `true` in `transfer/protocol_options` of `aspera.conf` (auto-correction of the base RTT, for virtual machines).',
        token_expired:                       'Generate a new token (option `-W` of `ascp`) just before the transfer, and check that the clocks of the system that generates tokens and of the server are synchronized.',
        content_protection:                  'Encrypt files at rest: option `--file-crypt=encrypt` of `ascp`, with the passphrase in environment variable `ASPERA_SCP_FILEPASS`. ' \
          'The server requires it with `content_protection_required` in `transfer/encryption` of `aspera.conf`.',
        insufficient_permissions:            'Check the permissions of the transfer user on the file (operating system), and the access rules of the server: `read_allowed` and `write_allowed` in `file_system/access/paths/path` of `aspera.conf`.',
        out_of_disk:                         'Free space on the destination storage, or check its quota, then retry the transfer with resume (option `-k` of `ascp`).',
        read:                                storage_access,
        write:                               storage_access,
        disk_write_failed:                   storage_access,
        device_not_connected:                network_storage,
        net_error:                           network_storage,
        net_path_not_found:                  network_storage,
        net_name_gone:                       network_storage,
        sharing_violation:                   'Another process (e.g. antivirus, indexer or application) uses the file: close it or exclude the folder from its scan, then retry.',
        out_of_resources:                    'Check the resources of the Windows system (memory, handles) and reduce the number of concurrent transfers.',
        out_of_memory:                       'Check the free memory of the system and reduce the number of concurrent transfers.',
        no_buffer_mem:                       'Reduce the number of concurrent transfers, or the size of UDP socket buffers (`max_sock_buffer` in `transfer/protocol_options` of `aspera.conf`).',
        bind_udp_socket_failed:              'Check that the UDP port (`bind_udp_port`) and the address (`bind_ip_address`) in `transfer/protocol_options` of `aspera.conf` are valid for this system, ' \
          'and that the process is allowed to use them. The error number is in the log line.',
        configuration_error:                 'Correct `aspera.conf` on the system that logged the error (XML syntax and values), or use another file with option `-f` of `ascp`.',
        filename_too_long:                   'Shorten the destination path or the file names, so that the Windows path is not longer than 260 characters.',
        remote_reset:                        tcp_connection,
        ssh_timeout:                         tcp_connection,
        ssh_session_died:                    tcp_connection,
        local_reset:                         'Check the firewall, antivirus and network drivers of this system: they may reset TCP connections.',
        ssh_startup_failed:                  'Check the host name, the TCP port of SSH (option `-P` of `ascp`, `ssh_port` of the server) and the firewalls. ' \
          'Test with option `--mode=test-login` of `ascp`. On a slow network, `ssh_startup_timeout_sec` in `aspera.conf` sets the connection timeout.',
        ssh_key_authentication:              'Check the private key (option `-i` of `ascp`) or the password (environment variable `ASPERA_SCP_PASS`), and that the user is allowed to connect to the server.',
        ssh_session_failed:                  'Check that the SSH server accepts new sessions (load, limits), then retry. Test with option `--mode=test-login` of `ascp`.',
        ssh_command_failed:                  'Check that the user is configured for Aspera on the server (`aspshell`), and the name of the remote command (option `-S` of `ascp`).',
        ssh_forward_failed:                  'Check that the SSH server allows TCP forwarding for the user (e.g. `AllowTcpForwarding` in `sshd_config`).'
      }.freeze
      # Identifiers of `Session::FLAG_DIAGNOSTICS` without recommendation: nothing to do
      NO_RECOMMENDATION = %w[user_abort table_died].freeze
    end
  end
end
