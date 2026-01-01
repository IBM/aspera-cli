# frozen_string_literal: true

require_relative '../build/lib/build_tools'
include BuildTools
include Paths

CLEAN.push(TMP)

namespace :tools do
  desc 'Show changes since latest tag'
  task changes: [] do
    latest_tag = run(%w[git describe --tags --abbrev=0], capture: true).chomp
    log.info("Changes since #{latest_tag}")
    run('git', 'log', "#{latest_tag}..HEAD", '--oneline', env: {'PAGER'=>''})
  end
  # https://github.com/Yelp/detect-secrets
  desc 'Init scan of secrets'
  task scan_init: [] do
    run('detect-secrets', 'scan', '--exclude-files', '^.secrets.baseline$', '--exclude-secrets', '_here_', '--exclude-secrets', '^my_', '--exclude-secrets', '^your ', '--exclude-secrets', 'demoaspera')
  end
  desc 'Scan secrets'
  task scan: [] do
    run('detect-secrets', 'scan', '--baseline', '.secrets.baseline')
  end
  desc 'Rubocop'
  task rubocop: [] do
    run('rubocop', LIB)
  end
  desc 'Reek'
  task reek: [] do
    run('reek', '-c', TOP / '.reek.yml')
  end
  desc 'Semgrep'
  task semgrep: [] do
    run('semgrep', 'scan', '--config', 'auto')
  end

  desc 'Remove all installed gems'
  task clean_gems: [] do
    gems_dir = File.join(Gem.dir, 'gems')
    if Dir.exist?(gems_dir) && !Dir.empty?(gems_dir)
      gem_names =
        Dir.children(gems_dir)
          .map{ |d| d.sub(/-[0-9].*$/, '')}
          .uniq
          .sort
      run('gem', 'uninstall', '-a', '-x', '-I', *gem_names)
    end
    GEMFILE_LOCK.delete
    run('gem', 'install', 'bundler')
  end

  PROTO_PATH = TMP / 'protos'
  GRPC_DEST = LIB
  desc 'Build Transfer SDK stub from proto'
  task grpc: [] do
    PROTO_PATH.mkpath
    download_proto_file(PROTO_PATH)
    run('grpc_tools_ruby_protoc', "--proto_path=#{PROTO_PATH}", "--ruby_out=#{GRPC_DEST}", "--grpc_out=#{GRPC_DEST}", PROTO_PATH / 'transferd.proto')
  end
end

## Gem build
# $(Paths::GEM_PACK_FILE): ensure_gems_installed
#	gem build $(GEMSPEC)
#	gem specification $(Paths::GEM_PACK_FILE) version
## force rebuild of gem and sign it, then check signature
# signed_gem: gem_check_signing_key clean_gem ensure_gems_installed $(Paths::GEM_PACK_FILE)
#	@tar tf $(Paths::GEM_PACK_FILE)|grep '\.gz\.sig$$'
#	@echo "Ok: gem is signed"
## build gem without signature for development and test
# unsigned_gem: $(Paths::GEM_PACK_FILE)
# beta_gem:
#	make GEM_VERSION=$(GEM_VERS_BETA) unsigned_gem
# clean_optional_gems:
#	bundle config set without optional
#	bundle install
#	bundle clean --force
# install_dev_gems:
#	gem install bundler
#	bundle config set with development
#	bundle install
## install optional gems and
# install_optional_gems: install_dev_gems
#	bundle config set with optional
#	bundle install
#
###################################
## Gem publish
## in case of big problem on released gem version, it can be deleted from rubygems
## gem yank -v $(GEM_VERSION) $(GEM_NAME)
# release: all
#	gem push $(Paths::GEM_PACK_FILE)

namespace :todo do
  GEM_VERS_BETA = "#{GEM_VERSION}.#{Time.now.strftime('%Y%m%d%H%M')}"

  desc 'Install development gems'
  task :install_dev_gems do
    sh 'gem install bundler'
    sh 'bundle config set with development'
    sh 'bundle install'
  end

  desc 'Install optional gems'
  task install_optional_gems: [:install_dev_gems] do
    sh 'bundle config set with optional'
    sh 'bundle install'
  end

  desc 'Build unsigned gem'
  task unsigned_gem: [Paths::GEM_PACK_FILE.to_s]

  file Paths::GEM_PACK_FILE.to_s => [:ensure_gems_installed] do
    sh "gem build #{GEMSPEC}"
    sh "gem specification #{Paths::GEM_PACK_FILE} version"
  end

  desc 'Build signed gem'
  task signed_gem: %i[gem_check_signing_key clean_gem ensure_gems_installed unsigned_gem] do
    sh "tar tf #{Paths::GEM_PACK_FILE} | grep '.gz.sig$'"
    puts 'Ok: gem is signed'
  end

  desc 'Check signing key presence'
  task :gem_check_signing_key do
    key_path = ENV['SIGNING_KEY']
    abort 'Error: Missing env var SIGNING_KEY' if key_path.nil? || key_path.empty?
    abort "Error: No such file: #{key_path}" unless File.exist?(key_path)
  end

  desc 'Release gem to RubyGems'
  task release: [:default] do
    cmd = Gem::Commands::PushCommand.new
    cmd.handle_options([Paths::GEM_PACK_FILE.to_s])
    cmd.execute
  end

  desc 'Show gem version'
  task :version do
    puts GEM_VERSION
  end
end
