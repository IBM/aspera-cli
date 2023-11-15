# frozen_string_literal: true

module Aspera
  module Fasp
    # executes a local "ascp", connects mgt port, equivalent of "Fasp Manager"
    class Management
      # cspell: disable
      OPERATIONS = %w[
        NOP
        START
        QUERY
        QUERYRSP
        STATS
        STOP
        ERROR
        CANCEL
        DONE
        RATE
        FILEERROR
        SESSION
        NOTIFICATION
        INIT
        VLINK
        NOTIFICATION
        PUT
        WRITE
        CLOSE
        SKIP
        ARGSTOP
      ]

      PARAMETERS = %w[
        Type
        File
        Size
        Written
        Bytescont
        Rate
        Loss
        Query
        Code
        Password
        Progress
        Remaining
        Elapsed
        RexInfo
        BlockInfo
        DiskInfo
        RateInfo
        MinRate
        Description
        Elapsedusec
        ServiceLevel
        SessionId
        User
        Host
        Encryption
        Adaptive
        Direction
        Remote
        Port
        UserStr
        CommandId
        StartByte
        EndByte
        Token
        Cookie
        QueryResponse
        Source
        Destination
        BWMeasurement
        BWInfo
        PMTU
        TransferBytes
        FileBytes
        Operation
        Delay
        PreTransferFiles
        PreTransferDirs
        PreTransferSpecial
        PreTransferFailed
        PartialPreTransferBytes
        PreTransferBytes
        Priority
        Transport
        VlinkID
        VlinkOn
        VlinkCapIn
        VlinkCapOut
        ManifestFile
        ArgScansAttempted
        ArgScansCompleted
        PathScansAttempted
        PathScansFailed
        PathScansIrregular
        PathScansExcluded
        DirScansCompleted
        FileScansCompleted
        DirCreatesAttempted
        DirCreatesFailed
        DirCreatesPassed
        TransfersAttempted
        TransfersFailed
        TransfersPassed
        TransfersSkipped
        FallbackProtocol
        RetryTimeout
        PreTransferExcluded
        XferId
        XferRetry
        Tags
        FaspFileArgIndex
        ArgTransfersStatus
        ArgTransfersAttempted
        ArgTransfersFailed
        ArgTransfersPassed
        ArgTransfersSkipped
        FaspFileID
        RateCap
        MinRateCap
        PolicyCap
        PriorityCap
        RateLock
        MinRateLock
        PolicyLock
        FileChecksum
        ServerHostname
        ServerNodeId
        ClientNodeId
        ServerClusterId
        ClientClusterId
        FileChecksumType
        ServerDocroot
        ClientDocroot
        NodeUser
        ClientUser
        SourcePrefix
        RemoteAddress
        TCPPort
        Cipher
        ResumePolicy
        CreatePolicy
        ManifestPolicy
        Precalc
        OverwritePolicy
        RTTAutocorrect
        TimePolicy
        ManifestPath
        ManifestInprogress
        PartialFiles
        FilesEncrypt
        FilesDecrypt
        DatagramSize
        PrepostCommand
        XoptFlags
        VLinkVersion
        PeerVLinkVersion
        VLinkLocalEnabled
        VLinkLocalId
        VLinkLocalCL
        VLinkRemoteEnabled
        VLinkRemoteId
        VLRemoteCL
        DSPipelineDepth
        PeerDSPipelineDepth
        LocalIP
        SourceBase
        ReadBlockSize
        WriteBlockSize
        ClusterNumNodes
        ClusterNodeId
        MoveRange
        MoveRangeLow
        MoveRangeHigh
        Keepalive
        TestLogin
        UseProxy
        ProxyIP
        RateControlAlgorithm
        ClientMacAddress
        Offset
        ChunkSize
        PostTransferValidation
        OverwritePolicyCap
        ExtraCreatePolicy]
      # Management port start message
      MGT_HEADER = 'FASPMGR 2'
      # fields description for JSON generation
      # spellchecker: disable
      INTEGER_FIELDS = %w[Bytescont FaspFileArgIndex StartByte Rate MinRate Port Priority RateCap MinRateCap TCPPort CreatePolicy TimePolicy
                          DatagramSize XoptFlags VLinkVersion PeerVLinkVersion DSPipelineDepth PeerDSPipelineDepth ReadBlockSize WriteBlockSize
                          ClusterNumNodes ClusterNodeId Size Written Loss FileBytes PreTransferBytes TransferBytes PMTU Elapsedusec ArgScansAttempted
                          ArgScansCompleted PathScansAttempted FileScansCompleted TransfersAttempted TransfersPassed Delay].freeze
      BOOLEAN_FIELDS = %w[Encryption Remote RateLock MinRateLock PolicyLock FilesEncrypt FilesDecrypt VLinkLocalEnabled VLinkRemoteEnabled
                          MoveRange Keepalive TestLogin UseProxy Precalc RTTAutocorrect].freeze
      # cspell: enable

      class << self
        # translates legacy event into enhanced (JSON) event
        def enhanced_event_format(event)
          return event.keys.each_with_object({}) do |e, h|
            # capital_to_snake_case
            new_name = e
                .gsub(/([a-z\d])([A-Z])/, '\1_\2')
                .gsub(/([a-z\d])(usec)$/, '\1_\2')
                .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
                .downcase
            value = event[e]
            value = value.to_i if INTEGER_FIELDS.include?(e)
            value = value.eql?('Yes') if BOOLEAN_FIELDS.include?(e)
            h[new_name] = value
          end
        end
end # class << self
      def initialize
        @event_build = nil
        @last_event = nil
      end
      attr_reader :last_event

      def process_line(line)
        # Log.log.debug{"line=[#{line}]"}
        case line
        when MGT_HEADER
          # begin event
          @event_build = {}
        when /^([^:]+): (.*)$/
          # event field
          @event_build[Regexp.last_match(1)] = Regexp.last_match(2)
        when ''
          # empty line is separator to end event information
          raise 'unexpected empty line' if @event_build.nil?
          @last_event = @event_build
          @event_build = nil
          return @last_event
        else
          raise "unexpected line:[#{line}]"
        end # case
        return nil
      end
    end
  end
end
