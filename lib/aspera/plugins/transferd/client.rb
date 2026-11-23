# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../assert'
require_relative 'api'

module Aspera
  module Plugins
    module Transferd
      # Calls to a running Transfer Daemon with plain Ruby arguments: builds the gRPC requests, returns the gRPC responses.
      # Used by code that must not know the generated gRPC classes (e.g. the emulator of the bundle `node`).
      class Client
        class << self
          # Empty gRPC message, used as default when no message was received
          # @param name [Symbol] `:transfer_info`, `:instance_info`, `:aspera_info` or `:license_info`
          # @return [Google::Protobuf::AbstractMessage] message with default values
          def empty_message(name)
            case name
            when :transfer_info then ::Transferd::Api::TransferInfo.new
            when :instance_info then ::Transferd::Api::InstanceInfo.new
            when :aspera_info then ::Transferd::Api::AsperaInfo.new
            when :license_info then ::Transferd::Api::LicenseInfo.new
            else Aspera.error_unexpected_value(name)
            end
          end
        end

        # @param stub [Transferd::Api::TransferService::Stub] gRPC client of the daemon
        def initialize(stub)
          @stub = stub
        end

        # @return [Transferd::Api::InstanceInfoResponse] Information on the daemon
        def instance_info
          @stub.get_info(::Transferd::Api::InstanceInfoRequest.new)
        end

        # Start a transfer and yield its events until the stream ends
        # @param transfer_spec_json [String] transfer spec, as JSON
        # @yieldparam response [Transferd::Api::TransferResponse] event
        def start_with_monitor(transfer_spec_json, &block)
          request = ::Transferd::Api::TransferRequest.new(
            transferType: ::Transferd::Api::TransferType::FILE_REGULAR,
            config:       ::Transferd::Api::TransferConfig.new,
            transferSpec: transfer_spec_json
          )
          @stub.start_transfer_with_monitor(request, &block)
        end

        # @param transfer_id [String] transfer to stop
        # @return [Transferd::Api::StopTransferResponse]
        def stop(transfer_id)
          @stub.stop_transfer(::Transferd::Api::StopTransferRequest.new(transferId: [transfer_id]))
        end

        # @param transfer_id        [String] transfer to modify
        # @param changes_json       [String] new values of transfer spec fields, as JSON
        # @return [Transferd::Api::TransferModificationResponse]
        def modify(transfer_id, changes_json)
          @stub.modify_transfer(::Transferd::Api::TransferModificationRequest.new(transferId: transfer_id, transferSpec: changes_json))
        end
      end
    end
  end
end
