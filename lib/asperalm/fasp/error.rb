module Asperalm
  module Fasp
    # error raised if transfer fails
    class Error < StandardError
      # from https://www.google.com/search?q=FASP+error+codes
      # columns: code name descr msg retryable
      # Note that the fact that an error is retryable is user defined, not by protocol
      FASP_ERROR_CODES = [
        [],
        [ 1,  'ERR_FASP_PROTO',            "Generic fasp(tm) protocol error",                "fasp(tm) error",                                                    false ],
        [ 2,  'ERR_ASCP',                  "Generic SCP error",                              "ASCP error",                                                        false ],
        [ 3,  'ERR_AMBIGUOUS_TARGET',      "Target incorrectly specified",                   "Ambiguous target",                                                  false ],
        [ 4,  'ERR_NO_SUCH_FILE',          "No such file or directory",                      "No such file or directory",                                         false ],
        [ 5,  'ERR_NO_PERMS',              "Insufficient permission to read or write",       "Insufficient permissions",                                          false ],
        [ 6,  'ERR_NOT_DIR',               "Target is not a directory",                      "Target must be a directory",                                        false ],
        [ 7,  'ERR_IS_DIR',                "File is a directory - expected regular file",    "Expected regular file",                                             false ],
        [ 8,  'ERR_USAGE',                 "Incorrect usage of scp command",                 "Incorrect usage of Aspera scp command",                             false ],
        [ 9,  'ERR_LIC_DUP',               "Duplicate license",                              "Duplicate license",                                                 false ],
        [ 10, 'ERR_LIC_RATE_EXCEEDED',     "Rate exceeds the cap imposed by license",        "Rate exceeds cap imposed by license",                               false ],
        [ 11, 'ERR_INTERNAL_ERROR',        "Internal error (unexpected error)",              "Internal error",                                                    false ],
        [ 12, 'ERR_TRANSFER_ERROR',        "Error establishing control connection",          "Error establishing SSH connection (check SSH port and firewall)",   true ],
        [ 13, 'ERR_TRANSFER_TIMEOUT',      "Timeout establishing control connection",        "Timeout establishing SSH connection (check SSH port and firewall)", true ],
        [ 14, 'ERR_CONNECTION_ERROR',      "Error establishing data connection",             "Error establishing UDP connection (check UDP port and firewall)",   true ],
        [ 15, 'ERR_CONNECTION_TIMEOUT',    "Timeout establishing data connection",           "Timeout establishing UDP connection (check UDP port and firewall)", true ],
        [ 16, 'ERR_CONNECTION_LOST',       "Connection lost",                                "Connection lost",                                                   true ],
        [ 17, 'ERR_RCVR_SEND_ERROR',       "Receiver fails to send feedback",                "Network failure (receiver can't send feedback)",                    true ],
        [ 18, 'ERR_RCVR_RECV_ERROR',       "Receiver fails to receive data packets",         "Network failure (receiver can't receive UDP data)",                 true ],
        [ 19, 'ERR_AUTH',                  "Authentication failure",                         "Authentication failure",                                            false ],
        [ 20, 'ERR_NOTHING',               "Nothing to transfer",                            "Nothing to transfer",                                               false ],
        [ 21, 'ERR_NOT_REGULAR',           "Not a regular file (special file)",              "Not a regular file",                                                false ],
        [ 22, 'ERR_FILE_TABLE_OVR',        "File table overflow",                            "File table overflow",                                               false ],
        [ 23, 'ERR_TOO_MANY_FILES',        "Too many files open",                            "Too many files open",                                               true ],
        [ 24, 'ERR_FILE_TOO_BIG',          "File too big for file system",                   "File too big for filesystem",                                       false ],
        [ 25, 'ERR_NO_SPACE_LEFT',         "No space left on disk",                          "No space left on disk",                                             false ],
        [ 26, 'ERR_READ_ONLY_FS',          "Read only file system",                          "Read only filesystem",                                              false ],
        [ 27, 'ERR_SOME_FILE_ERRS',        "Some individual files failed",                   "One or more files failed",                                          false ],
        [ 28, 'ERR_USER_CANCEL',           "Cancelled by user",                              "Cancelled by user",                                                 false ],
        [ 29, 'ERR_LIC_NOLIC',             "License not found or unable to access",          "Unable to access license info",                                     false ],
        [ 30, 'ERR_LIC_EXPIRED',           "License expired",                                "License expired",                                                   false ],
        [ 31, 'ERR_SOCK_SETUP',            "Unable to setup socket (create, bind, etc ...)", "Unable to set up socket",                                           false ],
        [ 32, 'ERR_OUT_OF_MEMORY',         "Out of memory, unable to allocate",              "Out of memory",                                                     true ],
        [ 33, 'ERR_THREAD_SPAWN',          "Can't spawn thread",                             "Unable to spawn thread",                                            true ],
        [ 34, 'ERR_UNAUTHORIZED',          "Unauthorized by external auth server",           "Unauthorized",                                                      false ],
        [ 35, 'ERR_DISK_READ',             "Error reading source file from disk",            "Disk read error",                                                   true ],
        [ 36, 'ERR_DISK_WRITE',            "Error writing to disk",                          "Disk write error",                                                  true ],
        [ 37, 'ERR_AUTHORIZATION',         "Used interchangeably with <strong>ERR_UNAUTHORIZED</strong>", "Authorization failure",                          true ],
        [ 38, 'ERR_LIC_ILLEGAL',           "Operation not permitted by license",                          "Operation not permitted by license",             false ],
        [ 39, 'ERR_PEER_ABORTED_SESSION',  "Remote peer terminated session",                              "Peer aborted session",                           true ],
        [ 40, 'ERR_DATA_TRANSFER_TIMEOUT', "Transfer stalled, timed out",                                 "Data transfer stalled, timed out",               true ],
        [ 41, 'ERR_BAD_PATH',              "Path violates docroot containment",                           "File location is outside 'docroot' hierarchy",   false ],
        [ 42, 'ERR_ALREADY_EXISTS',        "File or directory already exists",                            "File or directory already exists",               false ],
        [ 43, 'ERR_STAT_FAILS',            "Cannot stat file",                                            "Cannot collect details about file or directory", false ],
        [ 44, 'ERR_PMTU_BRTT_ERROR',       "UDP session initiation fatal error",                          "UDP session initiation fatal error",             true ],
        [ 45, 'ERR_BWMEAS_ERROR',          "Bandwidth measurement fatal error",                           "Bandwidth measurement fatal error",              true ],
        [ 46, 'ERR_VLINK_ERROR',           "Virtual link error",                                          "Virtual link error",                             false ],
        [ 47, 'ERR_CONNECTION_ERROR_HTTP', "Error establishing HTTP connection",       "Error establishing HTTP connection (check HTTP port and firewall)", false ],
        [ 48, 'ERR_FILE_ENCRYPTION_ERROR', "File encryption error, e.g. corrupt file", "File encryption/decryption error, e.g. corrupt file",               false ],
        [ 49, 'ERR_FILE_DECRYPTION_PASS',  "File encryption/decryption error, e.g. corrupt file", "File decryption error, bad passphrase", false ],
        [ 50, 'ERR_BAD_CONFIGURATION',     "Aspera.conf contains invalid data and was rejected",  "Invalid configuration",                 false ],
        [ 51, 'ERR_UNDEFINED',             "Should never happen, report to Aspera",               "Undefined error",                       false ],
      ]

      def self.fasp_error_retryable?(err_code)
        return false if !err_code.is_a?(Integer) or err_code < 1 or err_code > FASP_ERROR_CODES.length
        return FASP_ERROR_CODES[err_code][4]
      end
      attr_reader :err_code

      def initialize(message,err_code=nil)
        super(message)
        @err_code = err_code
      end
    end
  end
end
