# frozen_string_literal: true

# cspell:ignore peeros peerver rexreqs
# Tests for Aspera::Ascp::LogAnalyzer with real anonymized log fixtures.

require_relative '../lib/aspera/ascp/log_analyzer'
require 'bundler/setup'

RSpec.describe(Aspera::Ascp::LogAnalyzer) do
  fixtures_dir = File.expand_path('fixtures/ascp_logs', __dir__)

  describe 'real log fixtures' do
    {
      'cipher_server.log'            => %w[cipher_set_by_server job_size_changed low_efficiency control_message_loss],
      'disk_speed_exceeded.log'      => %w[old_version rate_change user_abort disk_write_speed_exceeded disk_buffers],
      'error_files.log'              => %w[error_files],
      'error_license.log'            => %w[error_license job_size_changed],
      'error_storage_read.log'       => %w[error_storage cipher_set_by_server job_size_changed vlink read receiver_limit],
      'error_storage_write.log'      => %w[error_storage cipher_set_by_server job_size_changed vlink write],
      'error_udp_setup.log'          => %w[error_udp_setup cipher_set_by_server job_size_changed client_nohear_server],
      'high_rtt.log'                 => %w[cipher_set_by_server job_size_changed brtt_reset high_rtt high_retransmission_rtt low_efficiency control_message_loss control_message_loss rex_timer_overflow rate_decline],
      'http_fallback.log'            => %w[error_configuration http_fallback],
      'inactivity_timer.log'         => %w[old_version inactivity_timer_fired feedback_interruption io_wait control_message_loss],
      'insufficient_permissions.log' => %w[old_version insufficient_permissions control_message_loss],
      'network_overdrive.log'        => %w[old_version network_overdrive io_wait],
      'pair_client.log'              => %w[cipher_set_by_server job_size_changed ssh_session_died],
      'pair_server.log'              => [],
      'retry.log'                    => %w[error_aborted retried cipher_set_by_server resume_lowered job_size_changed user_abort control_message_loss retry cipher_set_by_server resume_lowered job_size_changed],
      'slow_storage_loss.log'        => %w[old_version job_size_changed vlink rate_change user_abort slow_disk_write slow_storage_loss low_efficiency control_message_loss],
      'ssh_command_failed.log'       => %w[error_authentication ssh_command_failed ssh_not_closed],
      'ssh_key_auth.log'             => %w[error_authentication ssh_key_authentication],
      'ssh_startup_failed.log'       => %w[ssh_startup_failed],
      'ssh_timeout.log'              => %w[error_network ssh_timeout low_efficiency],
      'stuck_nack.log'               => %w[old_version vlink vlink io_wait low_efficiency old_version vlink rate_change remote_reset stuck_nack]
    }.each do |fixture, expected_diagnostic_ids|
      it "extracts expected diagnostics from #{fixture}" do
        analyzer = described_class.new.add(File.join(fixtures_dir, fixture))
        actual_diagnostic_ids = analyzer.diagnostics.map { |d| d['id'] }
        expect(actual_diagnostic_ids).to(eq(expected_diagnostic_ids))
      end
    end

    it 'joins client and server logs of the same transfer session' do
      analyzer = described_class.new
      analyzer.add(File.join(fixtures_dir, 'pair_client.log'))
      analyzer.add(File.join(fixtures_dir, 'pair_server.log'))
      sessions = analyzer.sessions
      expect(sessions.size).to(eq(2))
      client_side = sessions.find { |s| s['pid'] == '15c2b' }
      server_side = sessions.find { |s| s['pid'] == '3799898' }
      expect(client_side['peer_side']).to(include('pid' => '3799898', 'role' => 'server', 'status' => 'success'))
      expect(server_side['peer_side']).to(include('pid' => '15c2b', 'role' => 'server', 'status' => 'success'))
    end
  end
end
