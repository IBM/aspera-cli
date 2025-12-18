# frozen_string_literal: true

require_relative '../build/lib/build_tools'
include BuildTools
include Paths

namespace :tools do
  desc 'Show changes since latest tag'
  task changes: [] do
    latest_tag = run(%w[git describe --tags --abbrev=0], capture: true).chomp
    puts "Changes since #{latest_tag}"
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

  desc 'Remove all gems'
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
    (TOP / 'Gemfile.lock').delete
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

# beta:
#	cd $(ASPERA_CLI_TEST_PRIVATE) && make beta
###################################
## Gem build
# $(PATH_GEMFILE): ensure_gems_installed
#	gem build $(GEMSPEC)
#	gem specification $(PATH_GEMFILE) version
## force rebuild of gem and sign it, then check signature
# signed_gem: gem_check_signing_key clean_gem ensure_gems_installed $(PATH_GEMFILE)
#	@tar tf $(PATH_GEMFILE)|grep '\.gz\.sig$$'
#	@echo "Ok: gem is signed"
## build gem without signature for development and test
# unsigned_gem: $(PATH_GEMFILE)
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
#	gem push $(PATH_GEMFILE)
