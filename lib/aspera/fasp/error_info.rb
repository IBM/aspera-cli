# frozen_string_literal: true

module Aspera
  module Fasp
    # from https://www.google.com/search?q=FASP+error+codes
    # Note that the fact that an error is retryable is not internally defined by protocol, it's client-side responsibility
    ERROR_INFO = {
      # id   retryable      mnemo                       message                                              additional info
      1  => { r: false, c: 'FASP_PROTO',                  m: 'Generic fasp(tm) protocol error',                a: 'fasp(tm) error'},
      2  => { r: false, c: 'ASCP',                        m: 'Generic SCP error',                              a: 'ASCP error'},
      3  => { r: false, c: 'AMBIGUOUS_TARGET',            m: 'Target incorrectly specified',                   a: 'Ambiguous target'},
      4  => { r: false, c: 'NO_SUCH_FILE',                m: 'No such file or directory',                      a: 'No such file or directory'},
      5  => { r: false, c: 'NO_PERMS',                    m: 'Insufficient permission to read or write',       a: 'Insufficient permissions'},
      6  => { r: false, c: 'NOT_DIR',                     m: 'Target is not a directory',                      a: 'Target must be a directory'},
      7  => { r: false, c: 'IS_DIR',                      m: 'File is a directory - expected regular file',    a: 'Expected regular file'},
      8  => { r: false, c: 'USAGE',                       m: 'Incorrect usage of scp command',                 a: 'Incorrect usage of Aspera scp command'},
      9  => { r: false, c: 'LIC_DUP',                     m: 'Duplicate license',                              a: 'Duplicate license'},
      10 => { r: false, c: 'LIC_RATE_EXCEEDED',           m: 'Rate exceeds the cap imposed by license',        a: 'Rate exceeds cap imposed by license'},
      11 => { r: false, c: 'INTERNAL_ERROR',              m: 'Internal error (unexpected error)',              a: 'Internal error'},
      12 => { r: true,  c: 'TRANSFER_ERROR',              m: 'Error establishing control connection',
                                                          a: 'Error establishing SSH connection (check SSH port and firewall)'},
      13 => { r: true,  c: 'TRANSFER_TIMEOUT',            m: 'Timeout establishing control connection',
                                                          a: 'Timeout establishing SSH connection (check SSH port and firewall)'},
      14 => { r: true,  c: 'CONNECTION_ERROR',            m: 'Error establishing data connection',
                                                          a: 'Error establishing UDP connection (check UDP port and firewall)'},
      15 => { r: true,  c: 'CONNECTION_TIMEOUT',          m: 'Timeout establishing data connection',
                                                          a: 'Timeout establishing UDP connection (check UDP port and firewall)'},
      16 => { r: true,  c: 'CONNECTION_LOST',             m: 'Connection lost',                                a: 'Connection lost'},
      17 => { r: true,  c: 'RCVR_SEND_ERROR',             m: 'Receiver fails to send feedback',                a: 'Network failure (receiver can\'t send feedback)'},
      18 => { r: true,  c: 'RCVR_RECV_ERROR',             m: 'Receiver fails to receive data packets',         a: 'Network failure (receiver can\'t receive UDP data)'},
      19 => { r: false, c: 'AUTH',                        m: 'Authentication failure',                         a: 'Authentication failure'},
      20 => { r: false, c: 'NOTHING',                     m: 'Nothing to transfer',                            a: 'Nothing to transfer'},
      21 => { r: false, c: 'NOT_REGULAR',                 m: 'Not a regular file (special file)',              a: 'Not a regular file'},
      22 => { r: false, c: 'FILE_TABLE_OVR',              m: 'File table overflow',                            a: 'File table overflow'},
      23 => { r: true,  c: 'TOO_MANY_FILES',              m: 'Too many files open',                            a: 'Too many files open'},
      24 => { r: false, c: 'FILE_TOO_BIG',                m: 'File too big for file system',                   a: 'File too big for filesystem'},
      25 => { r: false, c: 'NO_SPACE_LEFT',               m: 'No space left on disk',                          a: 'No space left on disk'},
      26 => { r: false, c: 'READ_ONLY_FS',                m: 'Read only file system',                          a: 'Read only filesystem'},
      27 => { r: false, c: 'SOME_FILE_ERRS',              m: 'Some individual files failed',                   a: 'One or more files failed'},
      28 => { r: false, c: 'USER_CANCEL',                 m: 'Cancelled by user',                              a: 'Cancelled by user'},
      29 => { r: false, c: 'LIC_NOLIC',                   m: 'License not found or unable to access',          a: 'Unable to access license info'},
      30 => { r: false, c: 'LIC_EXPIRED',                 m: 'License expired',                                a: 'License expired'},
      31 => { r: false, c: 'SOCK_SETUP',                  m: 'Unable to setup socket (create, bind, etc ...)', a: 'Unable to set up socket'},
      32 => { r: true,  c: 'OUT_OF_MEMORY',               m: 'Out of memory, unable to allocate',              a: 'Out of memory'},
      33 => { r: true,  c: 'THREAD_SPAWN',                m: 'Can\'t spawn thread',                            a: 'Unable to spawn thread'},
      34 => { r: false, c: 'UNAUTHORIZED',                m: 'Unauthorized by external auth server',           a: 'Unauthorized'},
      35 => { r: true,  c: 'DISK_READ',                   m: 'Error reading source file from disk',            a: 'Disk read error'},
      36 => { r: true,  c: 'DISK_WRITE',                  m: 'Error writing to disk',                          a: 'Disk write error'},
      37 => { r: true,  c: 'AUTHORIZATION',               m: 'Used interchangeably with ERR_UNAUTHORIZED',     a: 'Authorization failure'},
      38 => { r: false, c: 'LIC_ILLEGAL',                 m: 'Operation not permitted by license',             a: 'Operation not permitted by license'},
      39 => { r: true,  c: 'PEER_ABORTED_SESSION',        m: 'Remote peer terminated session',                 a: 'Peer aborted session'},
      40 => { r: true,  c: 'DATA_TRANSFER_TIMEOUT',       m: 'Transfer stalled, timed out',                    a: 'Data transfer stalled, timed out'},
      41 => { r: false, c: 'BAD_PATH',                    m: 'Path violates docroot containment',              a: 'File location is outside \'docroot\' hierarchy'},
      42 => { r: false, c: 'ALREADY_EXISTS',              m: 'File or directory already exists',               a: 'File or directory already exists'},
      43 => { r: false, c: 'STAT_FAILS',                  m: 'Cannot stat file',                               a: 'Cannot collect details about file or directory'},
      44 => { r: true,  c: 'PMTU_BRTT_ERROR',             m: 'UDP session initiation fatal error',             a: 'UDP session initiation fatal error'},
      45 => { r: true,  c: 'BWMEAS_ERROR',                m: 'Bandwidth measurement fatal error',              a: 'Bandwidth measurement fatal error'},
      46 => { r: false, c: 'VLINK_ERROR',                 m: 'Virtual link error',                             a: 'Virtual link error'},
      47 => { r: false, c: 'CONNECTION_ERROR_HTTP',       m: 'Error establishing HTTP connection',
                                                          a: 'Error establishing HTTP connection (check HTTP port and firewall)'},
      48 => { r: false, c: 'FILE_ENCRYPTION_ERROR',       m: 'File encryption error, e.g. corrupt file',
                                                          a: 'File encryption/decryption error, e.g. corrupt file'},
      49 => { r: false, c: 'FILE_DECRYPTION_PASS',        m: 'File encryption/decryption error, e.g. corrupt file', a: 'File decryption error, bad passphrase'},
      50 => { r: false, c: 'BAD_CONFIGURATION',           m: 'Aspera.conf contains invalid data and was rejected',  a: 'Invalid configuration'},
      51 => { r: false, c: 'INSECURE_CONNECTION',         m: 'Remote-host key check failure',                  a: 'Remote host is not who we expected'},
      52 => { r: false, c: 'START_VALIDATION_FAILED',     m: 'File start validation failed',                   a: 'File start validation failed'},
      53 => { r: false, c: 'STOP_VALIDATION_FAILED',      m: 'File stop validation failed',                    a: 'File stop validation failed'},
      54 => { r: false, c: 'THRESHOLD_VALIDATION_FAILED', m: 'File threshold validation failed',               a: 'File threshold validation failed'},
      55 => { r: false, c: 'FILEPATH_TOO_LONG',           m: 'File path/name too long for underlying file system', a: 'File path exceeds underlying file system limit'},
      56 => { r: false, c: 'ILLEGAL_CHARS_IN_PATH',       m: 'Windows path contains illegal characters',
                                                          a: 'Path being written to Windows file system contains illegal characters'},
      57 => { r: false, c: 'CHUNK_MUST_MATCH_ALIGNMENT',  m: 'Chunk size/start must be aligned with storage',  a: 'Chunk size/start must be aligned with storage'},
      58 => { r: false, c: 'VALIDATION_SESSION_ABORT',    m: 'Session aborted to due to validation error',     a: 'Session aborted to due validation error'},
      59 => { r: false, c: 'REMOTE_STORAGE_ERROR',        m: 'Remote storage errored',                         a: 'Remote storage errored'},
      60 => { r: false, c: 'LUA_SCRIPT_ABORTED_SESSION',  m: 'Session aborted due to Lua script abort',        a: 'Session aborted due to Lua script abort'},
      61 => { r: true,  c: 'SSEAR_RETRYABLE',             m: 'Transfer failed because of a retryable Encryption at Rest error',
                                                          a: 'Transfer failed because of a retryable Encryption at Rest error'},
      62 => { r: false, c: 'SSEAR_FATAL',                 m: 'Transfer failed because of a fatal Encryption at Rest error',
                                                          a: 'Transfer failed because of a fatal Encryption at Rest error'},
      63 => { r: false, c: 'LINK_LOOP',                   m: 'Path refers to a symbolic link loop',            a: 'Path refers to a symbolic link loop'},
      64 => { r: false, c: 'CANNOT_RENAME_PARTIAL_FILES', m: 'Can\'t rename a partial file',                   a: 'Can\'t rename a partial file.'},
      65 => { r: false, c: 'CIPHER_NON_COMPAT_FIPS',      m: 'Can\'t use this cipher with FIPS mode enabled',  a: 'Can\'t use this cipher with FIPS mode enabled'},
      66 => { r: false, c: 'PEER_REQUIRES_FIPS',          m: 'Peer rejects cipher due to FIPS mode enabled on peer',
                                                          a: 'Peer rejects cipher due to FIPS mode enabled on peer'}
    }.freeze
  end
end
