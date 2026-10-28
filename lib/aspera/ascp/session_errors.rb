# frozen_string_literal: true

# cspell:ignore reuseaddr sourcelist BUFS ERANGE
require 'aspera/ascp/management'

module Aspera
  module Ascp
    # Error codes of FASP sessions: `errcode` in log lines `Session Start` and `Session Stop` of `ascp`.
    # Not the same numbering as errors of the management port (`Management::ERRORS`): each code maps to one of them.
    # References:
    # `fasp_errno.h` : codes (enum `fasp_errno_e`)
    # `fasp_errno.c` : messages (`fasp_errno2str`)
    # `asmgmt_err.c` : code of management port (`mgmt_fasperr2mgmterr`)
    module SessionErrors
      # Code => name, code of management port (mnemonic in `Management::ERRORS`), category (see CATEGORIES), message
      CODES = {
        1   => ['bad_version',                           'INTERNAL_ERROR',              'configuration',  'Bad version'],
        2   => ['bad_protocol',                          'FASP_PROTO',                  'configuration',  'Bad protocol'],
        3   => ['srcpath_check_failed',                  'BAD_PATH',                    'path',           'Source path check failed'],
        4   => ['dstpath_check_failed',                  'BAD_PATH',                    'path',           'Destination path check failed'],
        5   => ['incompat_mod_proto_vers',               'FASP_PROTO',                  'configuration',  'FASP module protocol versions incompatible'],
        6   => ['incompat_pipeline_depth',               'INTERNAL_ERROR',              'configuration',  'FASP pipeline depths incompatible'],
        7   => ['sess_stopped',                          'USER_CANCEL',                 'aborted',        'Session initiation stopped by application'],
        8   => ['connect_sock',                          'CONNECTION_ERROR',            'udp_setup',      'Unable to connect UDP socket'],
        9   => ['send_stop',                             'CONNECTION_ERROR',            'udp_setup',      'Unable to send STOP message'],
        10  => ['recv_stop',                             'CONNECTION_ERROR',            'udp_setup',      'Unable to recv STOP message'],
        11  => ['c_noresp',                              'CONNECTION_TIMEOUT',          'udp_setup',
                'Client unable to connect to server (check UDP port and firewall)'],
        12  => ['s_noresp',                              'CONNECTION_TIMEOUT',          'udp_setup',
                'Server unable to hear from client (check UDP port and firewall)'],
        13  => ['unconcluded_pmtu_brtt',                 'PMTU_BRTT_ERROR',             'udp_setup',      'Unable to conclude a valid pmtu-brtt value'],
        14  => ['invalid_pmtu_brtt',                     'PMTU_BRTT_ERROR',             'udp_setup',      'Unable to receive a valid stop message (pmtu-brtt)'],
        15  => ['unmatched_tl',                          'SOCK_SETUP',                  'udp_setup',      'Incompatible timer levels between peers'],
        16  => ['unconcluded_bw',                        'BWMEAS_ERROR',                'udp_setup',      'Unable to conclude a valid bw value'],
        17  => ['invalid_bw',                            'BWMEAS_ERROR',                'udp_setup',      'Unable to receive a valid stop message (bwmeas)'],
        18  => ['ds_conn_lost',                          'CONNECTION_LOST',             'network',        'Connection lost in midst of data session'],
        19  => ['peer_aborted_sess',                     'PEER_ABORTED_SESSION',        'aborted',        'Peer aborted session'],
        20  => ['ds_proto_magic_mismatch',               'FASP_PROTO',                  'network',        'Data session protocol error, magic mismatch'],
        21  => ['ds_proto_pdutype_invalid',              'FASP_PROTO',                  'network',        'Data session protocol error, pdu type invalid'],
        22  => ['ds_proto_msg_toosmall',                 'FASP_PROTO',                  'network',        'Data session protocol error, message too small'],
        23  => ['ds_proto_msg_toobig',                   'FASP_PROTO',                  'network',        'Data session protocol error, message too big'],
        24  => ['internal_disk_thread',                  'THREAD_SPAWN',                'storage',        'Internal disk thread error'],
        25  => ['internal_ring',                         'INTERNAL_ERROR',              'other',          'Internal ring error'],
        26  => ['internal_out_of_mem',                   'OUT_OF_MEMORY',               'other',          'Internal memory error'],
        27  => ['sess_other',                            'TRANSFER_ERROR',              'other',          'Other Session error'],
        28  => ['xfer_other',                            'SOME_FILE_ERRS',              'files',          'Other Transfer error'],
        29  => ['sess_internal',                         'INTERNAL_ERROR',              'other',          'Session internal error'],
        30  => ['sess_conn_tmout',                       'CONNECTION_TIMEOUT',          'network',        'Session connection timeout'],
        31  => ['sess_rex_send',                         'RCVR_SEND_ERROR',             'network',        'Retransmit request send error'],
        32  => ['sess_stats_send',                       'RCVR_SEND_ERROR',             'network',        'Stats request send error'],
        33  => ['sess_reception',                        'CONNECTION_LOST',             'network',        'Data reception error'],
        34  => ['xfer_external_abort',                   'PEER_ABORTED_SESSION',        'aborted',        'External abort of transfer'],
        35  => ['xfer_transfer_tmout',                   'DATA_TRANSFER_TIMEOUT',       'network',        'Data transfer timeout'],
        36  => ['sess_transfer_tmout',                   'DATA_TRANSFER_TIMEOUT',       'network',        'Session data transfer timeout'],
        37  => ['xfer_test_internal_abort_err',          'PEER_ABORTED_SESSION',        'other',          'Session internal abort'],
        38  => ['lic_read',                              'LIC_NOLIC',                   'license',        'Unable to read license'],
        39  => ['lic_expired',                           'LIC_EXPIRED',                 'license',        'License expired'],
        40  => ['lic_illegal',                           'LIC_ILLEGAL',                 'license',        'Operation not permitted by license'],
        41  => ['lic_bw_exceeded',                       'LIC_RATE_EXCEEDED',           'license',        'License bandwidth cap exceeded'],
        42  => ['lic_duplicate',                         'LIC_DUP',                     'license',        'Duplicate license'],
        43  => ['sock_addrinfo',                         'SOCK_SETUP',                  'socket',         'Error getting socket information'],
        44  => ['sock_set_reuse',                        'SOCK_SETUP',                  'socket',         'Error setting socket reuseaddr'],
        45  => ['sock_recvbuf',                          'SOCK_SETUP',                  'socket',         'Error setting socket recv buffer size'],
        46  => ['sock_sendbuf',                          'SOCK_SETUP',                  'socket',         'Error setting socket send buffer size'],
        47  => ['sock_bind',                             'SOCK_SETUP',                  'socket',         'Error binding socket to port'],
        48  => ['sock_create',                           'SOCK_SETUP',                  'socket',         'Error creating socket'],
        49  => ['resrc_disk_buf',                        'INTERNAL_ERROR',              'storage',        'Out of disk buffers'],
        50  => ['no_such_file',                          'NO_SUCH_FILE',                'storage',        'No such file or directory'],
        51  => ['no_perms',                              'NO_PERMS',                    'storage',        'Insufficient permissions'],
        52  => ['no_space_left',                         'NO_SPACE_LEFT',               'storage',        'No space left on disk'],
        53  => ['not_dir',                               'NOT_DIR',                     'storage',        'Target must be a directory'],
        54  => ['is_dir',                                'IS_DIR',                      'storage',        'Expected regular file'],
        55  => ['file_table_overflow',                   'FILE_TABLE_OVR',              'storage',        'File table overflow'],
        56  => ['too_many_files',                        'TOO_MANY_FILES',              'storage',        'Too many files open'],
        57  => ['file_too_big',                          'FILE_TOO_BIG',                'storage',        'File too big for filesystem'],
        58  => ['read_only_fs',                          'READ_ONLY_FS',                'storage',        'Read only filesystem'],
        59  => ['disk_read',                             'DISK_READ',                   'storage',        'Disk read failed'],
        60  => ['disk_write',                            'DISK_WRITE',                  'storage',        'Disk write failed'],
        61  => ['srclist_count_invalid',                 'INTERNAL_ERROR',              'path',           'Too many source files specified'],
        62  => ['srclist_not_specified',                 'USAGE',                       'path',           'Source file list not specified'],
        63  => ['srcpath_stat_failed',                   'STAT_FAILS',                  'path',           'Source path stat failed'],
        64  => ['dstpath_does_not_preexist',             'NOT_DIR',                     'path',           'Destination path must preexist'],
        65  => ['dstpath_is_not_dir',                    'NOT_DIR',                     'path',           'Destination path must be a directory'],
        66  => ['dstpath_dir_create_failed',             'BAD_PATH',                    'path',           'Destination directory create failed'],
        67  => ['untranslated_syserrno',                 'INTERNAL_ERROR',              'other',          'Untranslated system errno'],
        68  => ['user_aborted_sess',                     'USER_CANCEL',                 'aborted',        'User aborted session'],
        69  => ['ds_resp_unknown',                       'FASP_PROTO',                  'other',          'Transfer response unknown'],
        70  => ['ds_resp_err_other',                     'FASP_PROTO',                  'other',          'Transfer response other error'],
        71  => ['ds_resp_err_eexist',                    'ALREADY_EXISTS',              'storage',        'File already exists'],
        72  => ['ds_resp_err_aspx',                      'UNAUTHORIZED',                'path',           'File is a .aspx file'],
        73  => ['mgmt_auth_refused',                     'UNAUTHORIZED',                'management',     'Management authorization refused'],
        74  => ['mgmt_conn_lost',                        'CONNECTION_LOST',             'management',     'Management connection lost'],
        75  => ['mgmt_auth_timeout',                     'UNAUTHORIZED',                'management',     'Management authorization timeout'],
        76  => ['had_file_errors',                       'SOME_FILE_ERRS',              'files',          'One or more transfers failed'],
        77  => ['disallowed_path',                       'BAD_PATH',                    'path',           'File location is outside \'docroot\' hierarchy'],
        78  => ['filename_too_long',                     'FILEPATH_TOO_LONG',           'path',           'Filename too long'],
        79  => ['not_regular_file',                      'NOT_REGULAR',                 'storage',        'Not a regular file'],
        80  => ['lic_keyinvalid',                        'LIC_ILLEGAL',                 'license',        'Invalid license key'],
        81  => ['vlink_init_err',                        'VLINK_ERROR',                 'configuration',  'virtual link initialization failed'],
        82  => ['vlink_start_err',                       'VLINK_ERROR',                 'configuration',  'virtual link failed to start up'],
        83  => ['file_encryption_err',                   'FILE_ENCRYPTION_ERROR',       'storage',        'File encryption error'],
        84  => ['dstpath_invalid',                       'BAD_PATH',                    'path',           'Destination path invalid'],
        85  => ['config_file_not_found',                 'BAD_CONFIGURATION',           'configuration',  'Configuration file not found'],
        86  => ['config_file_invalid',                   'BAD_CONFIGURATION',           'configuration',  'Invalid configuration file'],
        87  => ['file_decryption_pass',                  'FILE_DECRYPTION_PASS',        'storage',        'File decryption error, bad passphrase'],
        88  => ['docroot_invalid',                       'BAD_PATH',                    'path',           'Destination path create failed, invalid docroot'],
        89  => ['ssh_auth_failed',                       'AUTH',                        'authentication', 'SSH authentication failed'],
        90  => ['user_aborted_xfer',                     'USER_CANCEL',                 'aborted',        'User aborted transfer'],
        91  => ['cannot_readlink',                       'DISK_READ',                   'storage',        'Cannot readlink'],
        92  => ['cannot_rename_partial',                 'CANNOT_RENAME_PARTIAL',       'storage',        'Cannot rename partial file'],
        93  => ['vlink_stop_err',                        'VLINK_ERROR',                 'configuration',  'virtual link shutdown failure'],
        94  => ['mgmt_lic_timeout',                      'FASP_PROTO',                  'license',        'Management license data timeout'],
        95  => ['too_many_rms',                          'INTERNAL_ERROR',              'configuration',  'Too many rate modules'],
        96  => ['storage_inaccessible',                  'INTERNAL_ERROR',              'storage',        'Storage inaccessible'],
        97  => ['reading_sourcelist',                    'USAGE',                       'path',           'Error reading sourcelist from command line'],
        98  => ['reading_token',                         'USAGE',                       'authentication', 'Error reading token'],
        99  => ['allocating_chunked_token',              'USAGE',                       'authentication', 'Internal error - failed to allocate space for chunked token'],
        100 => ['extracting_master_token',               'USAGE',                       'authentication', 'Invalid token - failed to extract master'],
        101 => ['extracting_subchunk_token',             'USAGE',                       'authentication',
                'Invalid token - token only contains subset of file paths submitted'],
        102 => ['too_many_file_paths',                   'USAGE',                       'path',           'Too many file paths, increase CMDLINE_MAX_BUFS'],
        103 => ['reading_file_stdin',                    'USAGE',                       'path',           'Error reading file list from file/stdin'],
        104 => ['empty_file_list_from_stdin_or_file',    'USAGE',                       'path',           'Empty file list from file/stdin'],
        105 => ['token_filepath_mismatch',               'USAGE',                       'path',           'Token doesn\'t match file-list/file-pair-list'],
        106 => ['usage',                                 'USAGE',                       'configuration',  'Usage error'],
        107 => ['conn_insecure',                         'INSECURE_CONNECTION',         'authentication', 'Remote host is not who we expected'],
        108 => ['start_validation',                      'START_VALIDATION_FAILED',     'validation',     'Start validation failed'],
        109 => ['stop_validation',                       'STOP_VALIDATION_FAILED',      'validation',     'Stop validation failed'],
        110 => ['threshold_validation',                  'THRESHOLD_VALIDATION_FAILED', 'validation',     'Threshold validation failed'],
        111 => ['network_down',                          'CONNECTION_LOST',             'network',        'Network down'],
        112 => ['address_not_available',                 'CONNECTION_ERROR',            'network',        'Address not available'],
        113 => ['out_of_range',                          'CHUNK_MUST_MATCH_ALIGNMENT',  'configuration',  'Value out of expected range (AS_ERANGE)'],
        114 => ['invalid_argument',                      'USAGE',                       'configuration',  'Invalid argument'],
        115 => ['server_multi_session_not_supported',    'USAGE',                       'configuration',  'Server version of multi-session transfer is not supported'],
        116 => ['client_multi_session_not_supported',    'USAGE',                       'configuration',  'Client version of multi-session transfer is not supported'],
        117 => ['illegal_chars_in_path',                 'ILLEGAL_CHARS_IN_PATH',       'path',           'Path contains unsupported characters'],
        118 => ['inconsistent_source_uri',               'USAGE',                       'path',           'All source paths must start with the same URI schema'],
        119 => ['list_uri_not_allowed',                  'USAGE',                       'path',           'file-pair-list destination cannot be a URI'],
        120 => ['persistent_uri_not_allowed',            'USAGE',                       'path',
                'URIs not supported in source or destination management parameters'],
        121 => ['source_archive_mismatch',               'USAGE',                       'path',           'Source and archive paths must start with the same URI schema'],
        122 => ['server_stdio',                          'USAGE',                       'path',           'Stdio/stdio-tar schema not supported on server'],
        123 => ['invalid_docroot_dest_combination',      'USAGE',                       'path',           'Destination cannot be URI if docroot defined'],
        124 => ['token_URI_without_docroot_unsupported', 'USAGE',                       'path',           'Token only supported for URIs using docroot'],
        125 => ['invalid_chunk_size',                    'USAGE',                       'configuration',  'Invalid chunk size'],
        126 => ['fasp_session_open',                     'CONNECTION_ERROR',            'network',        'FASP session open error'],
        127 => ['fasp_session_accept',                   'CONNECTION_ERROR',            'network',        'FASP session accept error'],
        128 => ['sess_transfer_error',                   'CONNECTION_LOST',             'network',        'FASP session transfer error'],
        129 => ['upload_inprogress',                     'UPLOAD_IN_PROGRESS',          'storage',        'File upload already in progress'],
        130 => ['validation_session_abort',              'VALIDATION_SESSION_ABORT',    'validation',     'FASP session stopped, validation error(s)'],
        131 => ['remote_storage_error',                  'REMOTE_STORAGE_ERROR',        'storage',        'FASP session remote storage error'],
        132 => ['lua_session_abort',                     'LUA_SCRIPT_ABORTED_SESSION',  'validation',     'Aborted session'],
        133 => ['auth_setup_incomplete',                 'AUTHORIZATION',               'authentication', 'Authorization setup incomplete'],
        134 => ['ssear_retryable',                       'SSEAR_RETRYABLE',             'storage',        'Server-side Encryption At Rest unavailable'],
        135 => ['ssear_fatal',                           'SSEAR_FATAL',                 'storage',        'Server-side Encryption At Rest failed'],
        136 => ['link_loop',                             'LINK_LOOP',                   'storage',        'Too many levels of symbolic links'],
        137 => ['cipher_non_compat_fips',                'CIPHER_NON_COMPAT_FIPS',      'configuration',  'Cipher not supported with FIPS mode'],
        138 => ['peer_requires_fips',                    'PEER_REQUIRES_FIPS',          'configuration',  'FIPS support required on client and server'],
        139 => ['jobqueue_aborted',                      'LUA_SCRIPT_ABORTED_SESSION',  'aborted',        'Async job aborted by initiator request'],
        140 => ['connection_error_http',                 'CONNECTION_ERROR_HTTP',       'network',        'Connection lost during http session'],
        141 => ['min_version_fail',                      'MIN_VERSION_CHECK',           'configuration',  'Failed to start due to minimum version check.'],
        142 => ['max_ascp',                              'MAX_ASCP',                    'server_limit',   'Failed to start session maximum transfer sessions exceeded'],
        143 => ['incompatible_resume_option',            'USAGE',                       'configuration',
                'The server configuration is not compatible with the specified resume option']
      }.freeze
      # Category => hint for remediation
      CATEGORIES = {
        'udp_setup'      => 'The UDP session could not be established: check that the FASP UDP port (default 33001) is open in firewalls on both sides.',
        'network'        => 'Network problem during the session: check network stability, packet loss, and UDP session timeouts of firewalls.',
        'aborted'        => 'The session was aborted by the user, the peer or the application.',
        'license'        => 'License problem: check the license, e.g. with `ascp -A`.',
        'socket'         => 'Socket error: check that the UDP port is not used by another process, and the system socket limits.',
        'storage'        => 'Storage error: check free space, permissions and access to the storage.',
        'path'           => 'Path error: check source and destination paths, and docroot and restrictions of the transfer user.',
        'authentication' => 'Authentication failure: check credentials, SSH keys or token.',
        'management'     => 'The management connection with the application that controls ascp (e.g. Node API) failed.',
        'files'          => 'Some files failed: see the list of transferred files for the error of each file.',
        'validation'     => 'A validation of the transfer (e.g. a script on the server) refused it.',
        'configuration'  => 'Incompatible versions or configuration of peers: check versions and configuration.',
        'server_limit'   => 'The server refused the session: maximum number of concurrent ascp processes reached.'
      }.freeze
      # Category of codes without a specific cause, and of unknown codes
      OTHER = 'other'

      class << self
        # @param code [Integer] error code
        # @return [String] category of error code, see CATEGORIES
        def category(code)
          CODES.dig(code, 2) || OTHER
        end

        # @param category [String] category of error
        # @return [String, nil] hint for remediation
        def hint(category)
          CATEGORIES[category]
        end

        # @param code [Integer] error code
        # @return [Boolean, nil] true if a new attempt may succeed, as for the code of management port, nil if unknown
        def retryable(code)
          management = CODES.dig(code, 1) or return
          Management.error_by_mnemonic(management)&.fetch(:r)
        end

        # @return [Array<Hash>] information on all error codes
        def list
          CODES.map do |code, (name, management, category, message)|
            {'code' => code, 'name' => name, 'message' => message, 'category' => category, 'management' => management, 'retry' => retryable(code)}
          end
        end
      end
    end
  end
end
