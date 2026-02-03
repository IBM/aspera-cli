# frozen_string_literal: true

require_relative '../build/lib/build_tools'
include BuildTools
include Paths

namespace :tools do
  desc 'Show changes since latest tag'
  task changes: [] do
    latest_tag = run(*%w[git describe --tags --abbrev=0], capture: true).chomp
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

  task :check_signature do
    run('gem', 'specification', Paths::GEM_PACK_FILE, 'signing_key', 'cert_chain', 'version')
  end

  desc 'Show gem build version'
  task :version do
    puts BuildTools.build_version
  end

  desc 'Prepare beta version'
  task :version_override, [:version] do |_t, args|
    Aspera.assert(!args[:version].to_s.empty?){'Version argument is required for beta task'}
    OVERRIDE_VERSION_FILE.write(args[:version])
    puts("Beta version set to: #{BuildTools.build_version}")
  end
end
