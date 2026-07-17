# Rakefile
# frozen_string_literal: true

require 'rake'
require 'openssl'
require 'pathname'
require 'singleton'
require 'aspera/colors'

require_relative '../build/lib/build_tools'
include BuildTools

# Manages gem signing certificate and private key, loaded from the gemspec.
class Signer
  include Singleton

  # Returns the path to the private key file.
  # Reads the **SIGNING_KEY** env var: if it looks like PEM content (starts with "-----BEGIN "),
  # writes it to a temporary file and returns its path; otherwise treats it as a file path.
  # @return [Pathname] path to the private key file
  def private_key_path
    raise 'SIGNING_KEY env var required' unless ENV.key?('SIGNING_KEY')
    signing_key = ENV.fetch('SIGNING_KEY')
    if signing_key.start_with?('-----BEGIN ')
      key_path = Pathname.new(Dir.home) / '.gem' / 'signing_key.pem'
      key_path.dirname.mkpath
      File.open(key_path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |f| f.write(signing_key) }
      return key_path
    end
    key_path = Pathname.new(signing_key)
    raise 'SIGNING_KEY file not found' unless key_path.exist?
    key_path
  end

  # @return [Pathname] absolute path to the public certificate file, from the gemspec +cert_chain+
  def cert_path
    cert_file = @spec.cert_chain&.first or abort('spec.cert_chain missing')
    Paths::TOP / cert_file
  end

  # @return [String] maintainer email address, from the gemspec +email+ field
  def admin_email
    Array(@spec.email).first or abort('spec.email missing')
  end

  # @return [Integer] certificate validity duration in days
  def cert_days
    730
  end

  # Loads the private key from {private_key_path}.
  # @return [OpenSSL::PKey::PKey] the private key object
  def private_key
    OpenSSL::PKey.read(private_key_path.read)
  end

  # Loads the public certificate from {cert_path}.
  # @return [OpenSSL::X509::Certificate] the current signing certificate
  def cert
    OpenSSL::X509::Certificate.new(cert_path.read)
  end

  # @return [Gem::Specification] the loaded gemspec
  attr_reader :spec

  private

  # Loads the gemspec on initialization.
  def initialize
    @spec = Gem::Specification.load(Paths::GEMSPEC.to_s) or abort("Failed to load gemspec: #{Paths::GEMSPEC}")
  end
end

namespace :certs do
  desc 'Info'
  task :info do
    puts "Maintainer:  #{Signer.instance.admin_email}"
    puts "Key:         #{ENV.fetch('SIGNING_KEY', 'not set')}"
    puts "Certificate: #{Signer.instance.cert_path}"
    puts "Duration:    #{Signer.instance.cert_days}"
    puts "Created:     #{Signer.instance.cert.not_before}"
    expiry = Signer.instance.cert.not_after
    days_left = ((expiry - Time.now) / 86400).to_i
    color = days_left > 0 ? :green : :red
    puts "Expiry:      #{expiry.to_s.send(color)}"
    puts "Days left:   #{days_left.to_s.send(color)}"
  end

  desc 'Print days left before certificate expiry (for CI)'
  task :days_left do
    expiry = Signer.instance.cert.not_after
    puts ((expiry - Time.now) / 86400).to_i
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
