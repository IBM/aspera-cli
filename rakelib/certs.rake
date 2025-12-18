# Rakefile
# frozen_string_literal: true

require 'rake'
require 'openssl'
require 'pathname'
require 'singleton'

require_relative '../build/lib/build_tools'
include BuildTools

class Signer
  include Singleton

  def private_key_path
    raise 'SIGNING_KEY env var required' unless ENV.key?('SIGNING_KEY')
    key_path = Pathname.new(ENV['SIGNING_KEY'])
    raise 'SIGNING_KEY file not found' unless key_path.exist?
    key_path
  end

  def cert_path
    cert_file = @spec.cert_chain&.first or abort('spec.cert_chain missing')
    Paths::TOP / cert_file
  end

  def admin_email
    Array(@spec.email).first or abort('spec.email missing')
  end

  def cert_days
    1100
  end

  def private_key
    OpenSSL::PKey.read(private_key_path.read)
  end

  def cert
    OpenSSL::X509::Certificate.new(cert_path.read)
  end

  attr_reader :spec

  private

  def initialize
    @spec = Gem::Specification.load(Paths::GEMSPEC.to_s) or abort("Failed to load gemspec: #{Paths::GEMSPEC}")
  end
end

namespace :certs do
  desc 'Info'
  task :info do
    puts "Maintainer:  #{Signer.instance.admin_email}"
    puts "Key:         #{Signer.instance.private_key_path rescue 'not set'}"
    puts "Certificate: #{Signer.instance.cert_path}"
    puts "Duration:    #{Signer.instance.cert_days}"
  end

  desc 'Update existing certificate'
  task :update do
    run('gem', 'cert', '--re-sign', '--certificate', Signer.instance.cert_path.to_s, '--private-key', Signer.instance.private_key_path.to_s, '--days', Signer.instance.cert_days)
  end

  desc 'Create new certificate'
  task :new do
    run('gem', 'cert', '--build', Signer.instance.admin_email, '--private-key', Signer.instance.private_key_path.to_s, '--days', Signer.instance.cert_days)
    File.rename('gem-public_cert.pem', Signer.instance.cert_path.to_s)
  end

  desc 'Show certificate info'
  task :show do
    puts Signer.instance.cert.to_text.lines.first(13).join
  end

  desc 'Verify certificate matches private key'
  task :check_key do
    if Signer.instance.cert.public_key.to_der == Signer.instance.private_key.public_key.to_der
      puts 'Ok: certificate and key match'
    else
      abort 'Error: certificate and key do not match'.red
    end
  end
end
