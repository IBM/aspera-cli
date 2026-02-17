# frozen_string_literal: true

# cspell:ignore trevents
require 'aspera/cli/plugins/basic_auth'
require 'aspera/preview/generator'
require 'aspera/preview/options'
require 'aspera/preview/utils'
require 'aspera/preview/file_types'
require 'aspera/preview/terminal'
require 'aspera/transfer/spec'
require 'aspera/persistency_action_once'
require 'aspera/temp_file_manager'
require 'aspera/api/node'
require 'aspera/hash_ext'
require 'aspera/timer_limiter'
require 'aspera/id_generator'
require 'aspera/log'
require 'aspera/assert'
require 'securerandom'

module Aspera
  module Cli
    module Plugins
      class Preview < BasicAuth
        # special tag to identify transfers related to generator
        PREV_GEN_TAG = 'preview_generator'
        # defined by node API: suffix for folder containing previews
        PREVIEW_FOLDER_SUFFIX = '.asp-preview'
        # basename of preview files
        PREVIEW_BASENAME = 'preview'
        # subfolder in system tmp folder
        TMP_DIR_PREFIX = 'prev_tmp'
        # same value as in aspera.conf
        DEFAULT_PREVIEWS_FOLDER = 'previews'
        # mark that this is used by a particular access key
        AK_MARKER_FILE = '.aspera_access_key'
        # URL prefix for local storage
        PVCL_LOCAL_STORAGE = 'file:///'
        LOG_LIMITER_SEC = 30.0
        private_constant :PREV_GEN_TAG,
          :PREVIEW_FOLDER_SUFFIX,
          :PREVIEW_BASENAME,
          :TMP_DIR_PREFIX,
          :DEFAULT_PREVIEWS_FOLDER,
          :PVCL_LOCAL_STORAGE,
          :AK_MARKER_FILE,
          :LOG_LIMITER_SEC

        attr_accessor :option_skip_types, :option_previews_folder, :option_folder_reset_cache, :option_skip_folders, :option_overwrite, :option_file_access

        def initialize(**_)
          super
          @option_skip_types = []
          @option_skip_folders = []
          @option_previews_folder = nil
          @option_overwrite = nil
          @option_folder_reset_cache = nil
          # options for generation
          @gen_options = Aspera::Preview::Options.new
          # used to trigger periodic processing
          @periodic = TimerLimiter.new(LOG_LIMITER_SEC)
          # Proc
          @filter_block = nil
          # link CLI options to gen_info attributes
          options.declare(
            :skip_format, 'Skip this preview format',
            allowed: Aspera::Preview::Generator::PREVIEW_FORMATS
          )
          options.declare(
            :folder_reset_cache, 'Force detection of generated preview by refresh cache',
            allowed: %i[no header read],
            handler: {o: self, m: :option_folder_reset_cache},
            default: :no
          )
          options.declare(:skip_types, 'Skip generation for those types of files', handler: {o: self, m: :option_skip_types}, allowed: Allowed::TYPES_SYMBOL_ARRAY + Aspera::Preview::FileTypes::CONVERSION_TYPES)
          options.declare(:previews_folder, 'Preview folder in storage root', handler: {o: self, m: :option_previews_folder}, default: DEFAULT_PREVIEWS_FOLDER)
          options.declare(:skip_folders, 'List of folder to skip', handler: {o: self, m: :option_skip_folders}, allowed: Allowed::TYPES_STRING_ARRAY)
          options.declare(:base, 'Basename of output for for test')
          options.declare(:scan_path, 'Subpath in folder id to start scan in (default=/)')
          options.declare(:scan_id, 'Folder id in storage to start scan in, default is access key main folder id')
          options.declare(:mimemagic, 'Use Mime type detection of gem mimemagic', allowed: Allowed::TYPES_BOOLEAN, default: false)
          options.declare(:overwrite, 'When to overwrite result file', handler: {o: self, m: :option_overwrite}, allowed: %i[always never mtime], default: :mtime)
          options.declare(
            :file_access, 'How to read and write files in repository',
            allowed: %i[local remote],
            handler: {o: self, m: :option_file_access},
            default: :local
          )
          # add other options for generator (and set default values)
          Aspera::Preview::Options::DESCRIPTIONS.each do |opt|
            values = if opt.key?(:values)
              opt[:values]
            elsif Cli::Manager::BOOLEAN_SIMPLE.include?(opt[:default])
              Allowed::TYPES_BOOLEAN
            end
            options.declare(opt[:name], opt[:description].capitalize, allowed: values, handler: {o: @gen_options, m: opt[:name]}, default: opt[:default])
          end

          options.parse_options!
          # by default generate all supported formats (clone, as altered by options)
          @preview_formats_to_generate = Aspera::Preview::Generator::PREVIEW_FORMATS.clone
          skip = options.get_option(:skip_format)
          @preview_formats_to_generate.delete(skip) if skip
          @tmp_folder = File.join(TempFileManager.instance.global_temp, "#{TMP_DIR_PREFIX}.#{SecureRandom.uuid}")
          FileUtils.mkdir_p(@tmp_folder)
          Log.log.debug{"tmpdir: #{@tmp_folder}"}
        end

        # /files/id/files is normally cached in Redis, but we can discard the cache
        # but /files/id is not cached
        def get_folder_entries(file_id, request_args = nil)
          headers = {'Accept' => Mime::JSON}
          headers['X-Aspera-Cache-Control'] = 'no-cache' if @option_folder_reset_cache.eql?(:header)
          return @api_node.read("files/#{file_id}/files", request_args, headers: headers)
        end

        # old version based on folders
        # @param iteration_persistency can be nil
        def process_trevents(iteration_persistency)
          events_filter = {
            'access_key' => @access_key_self['id'],
            'type'       => 'download.ended'
          }
          # optionally add iteration token from persistency
          events_filter['iteration_token'] = iteration_persistency.data.first unless iteration_persistency.nil?
          begin
            events = @api_node.read('events', events_filter)
          rescue RestCallError => e
            if e.message.include?('Invalid iteration_token')
              Log.log.warn{"Retrying without iteration token: #{e}"}
              events_filter.delete('iteration_token')
              retry
            end
            raise e
          end
          return if events.empty?
          events.each do |event|
            if event['data']['direction'].eql?(Transfer::Spec::DIRECTION_RECEIVE) &&
                event['data']['status'].eql?('completed') &&
                event['data']['error_code'].eql?(0) &&
                event['data'].dig('tags', Transfer::Spec::TAG_RESERVED, PREV_GEN_TAG).nil?
              folder_id = event.dig('data', 'tags', Transfer::Spec::TAG_RESERVED, 'node', 'file_id')
              folder_id ||= event.dig('data', 'file_id')
              if !folder_id.nil?
                folder_entry = @api_node.read("files/#{folder_id}") rescue nil
                scan_folder_files(folder_entry) unless folder_entry.nil?
              end
            end
            # log/persist periodically or last one
            next unless @periodic.trigger? || event.equal?(events.last)
            Log.log.debug{"Processed event #{event['id']}"}
            # save checkpoint to avoid losing processing in case of error
            if !iteration_persistency.nil?
              iteration_persistency.data[0] = event['id'].to_s
              iteration_persistency.save
            end
          end
        end

        # requests recent events on node api and process newly modified folders
        def process_events(iteration_persistency)
          # get new file creation by access key (TODO: what if file already existed?)
          events_filter = {
            'access_key' => @access_key_self['id'],
            'type'       => 'file.*'
          }
          # optionally add iteration token from persistency
          events_filter['iteration_token'] = iteration_persistency.data.first unless iteration_persistency.nil?
          events = @api_node.read('events', events_filter)
          return if events.empty?
          events.each do |event|
            # process only files
            if event.dig('data', 'type').eql?('file')
              file_entry = @api_node.read("files/#{event['data']['id']}") rescue nil
              if !file_entry.nil? &&
                  @option_skip_folders.none?{ |d| file_entry['path'].start_with?(d)}
                file_entry['parent_file_id'] = event['data']['parent_file_id']
                Log.log.error('TODO'.red) if event['types'].include?('file.deleted')
                generate_preview(file_entry) if event['types'].include?('file.deleted')
              end
            end
            # log/persist periodically or last one
            next unless @periodic.trigger? || event.equal?(events.last)
            Log.log.debug{"Processing event #{event['id']}"}
            # save checkpoint to avoid losing processing in case of error
            if !iteration_persistency.nil?
              iteration_persistency.data[0] = event['id'].to_s
              iteration_persistency.save
            end
          end
        end

        def do_transfer(direction, folder_id, source_filename, destination = '/')
          Aspera.assert(!(destination.nil? && direction.eql?(Transfer::Spec::DIRECTION_RECEIVE)))
          t_spec = @api_node.transfer_spec_gen4(folder_id, direction, {
            'paths' => [{'source' => source_filename}],
            'tags'  => {Transfer::Spec::TAG_RESERVED => {PREV_GEN_TAG => true}}
          })
          # force destination, need to set this in transfer agent else it gets overwritten, do not do: t_spec['destination_root']=destination
          transfer.user_transfer_spec['destination_root'] = destination
          Main.result_transfer(transfer.start(t_spec))
        end

        def get_infos_local(gen_infos, entry)
          local_original_filepath = File.join(@local_storage_root, entry['path'])
          original_mtime = File.mtime(local_original_filepath)
          # out
          local_entry_preview_dir = File.join(@local_preview_folder, entry_preview_folder_name(entry))
          gen_infos.each do |gen_info|
            gen_info[:src] = local_original_filepath
            gen_info[:dst] = File.join(local_entry_preview_dir, gen_info[:base_dest])
            gen_info[:preview_exist] = File.exist?(gen_info[:dst])
            gen_info[:preview_newer_than_original] = (gen_info[:preview_exist] && (File.mtime(gen_info[:dst]) > original_mtime))
          end
          return local_entry_preview_dir
        end

        def get_infos_remote(gen_infos, entry)
          # store source directly here
          local_original_filepath = File.join(@tmp_folder, entry['name'])
          # require 'date'
          # original_mtime=DateTime.parse(entry['modified_time'])
          # out: where previews are generated
          local_entry_preview_dir = File.join(@tmp_folder, entry_preview_folder_name(entry))
          file_info = @api_node.read("files/#{entry['id']}")
          # TODO: this does not work because previews is hidden in api (gen4)
          # this_preview_folder_entries=get_folder_entries(@previews_folder_entry['id'],{name: @entry_preview_folder_name})
          # TODO: use gen3 api to list files and get date
          gen_infos.each do |gen_info|
            gen_info[:src] = local_original_filepath
            gen_info[:dst] = File.join(local_entry_preview_dir, gen_info[:base_dest])
            # TODO: use this_preview_folder_entries (but it's hidden)
            gen_info[:preview_exist] = file_info.key?('preview')
            # TODO: get change time and compare, useful ?
            gen_info[:preview_newer_than_original] = gen_info[:preview_exist]
          end
          return local_entry_preview_dir
        end

        # defined by node api
        def entry_preview_folder_name(entry)
          "#{entry['id']}#{PREVIEW_FOLDER_SUFFIX}"
        end

        # Generate a file name based on basename and format (extension)
        def preview_filename(preview_format, base_name = nil)
          base_name ||= PREVIEW_BASENAME
          return "#{base_name}.#{preview_format}"
        end

        # generate preview files for one folder entry (file) if necessary
        # entry must contain "parent_file_id" if remote.
        def generate_preview(entry)
          # prepare generic information
          gen_infos = @preview_formats_to_generate.map do |preview_format|
            {
              preview_format: preview_format,
              base_dest:      preview_filename(preview_format)
            }
          end
          # lets gather some infos on possibly existing previews
          # it depends if files access locally or remotely
          # folder where previews will be generated for this particular entry
          local_entry_preview_dir = @access_remote ? get_infos_remote(gen_infos, entry) : get_infos_local(gen_infos, entry)
          # here we have the status on preview files
          # let's find if they need generation
          gen_infos.select! do |gen_info|
            # if it exists, what about overwrite policy ?
            if gen_info[:preview_exist]
              case @option_overwrite
              when :always
                # continue: generate
              when :never
                # never overwrite
                next false
              when :mtime
                # skip if preview is newer than original
                next false if gen_info[:preview_newer_than_original]
              end
            end
            begin
              # need generator for further checks
              gen_info[:generator] = Aspera::Preview::Generator.new(gen_info[:src], gen_info[:dst], @gen_options, @tmp_folder, entry['content_type'])
            rescue
              # no conversion supported
              next false
            end
            # shall we skip it ?
            next false if @option_skip_types.include?(gen_info[:generator].conversion_type)
            # ok we need to generate
            true
          end
          return if gen_infos.empty?
          # create folder if needed
          FileUtils.mkdir_p(local_entry_preview_dir)
          if @access_remote
            Aspera.assert(!entry['parent_file_id'].nil?){'missing parent_file_id in entry'}
            #  download original file to temp folder
            do_transfer(Transfer::Spec::DIRECTION_RECEIVE, entry['parent_file_id'], entry['name'], @tmp_folder)
          end
          Log.log.debug{"source: #{entry['id']}: #{entry['path']}"}
          gen_infos.each do |gen_info|
            gen_info[:generator].generate rescue nil
          end
          if @access_remote
            # upload
            do_transfer(Transfer::Spec::DIRECTION_SEND, @previews_folder_entry['id'], local_entry_preview_dir)
            # cleanup after upload
            FileUtils.rm_rf(local_entry_preview_dir)
            File.delete(File.join(@tmp_folder, entry['name']))
          end
          # force read file updated previews
          @api_node.read("files/#{entry['id']}") if @option_folder_reset_cache.eql?(:read)
        rescue StandardError => e
          Log.log.error{"Ignore: #{e.message}"}
          Log.log.debug(e.backtrace.join("\n").red)
        end

        # scan all files in provided folder entry
        # @param top_path subpath to start folder scan inside
        def scan_folder_files(top_entry, top_path = nil)
          unless top_path.nil?
            # canonical path: start with / and ends with /
            top_path = "/#{top_path.split('/').reject(&:empty?).join('/')}/"
          end
          Log.log.debug{"scan: #{top_entry} : #{top_path}".green}
          # don't use recursive call, use list instead
          entries_to_process = [top_entry]
          until entries_to_process.empty?
            entry = entries_to_process.shift
            # process this entry only if it is within the top_path
            entry_path_with_slash = entry['path']
            Log.log.debug{"processing entry #{entry_path_with_slash}"} if @periodic.trigger?
            entry_path_with_slash = "#{entry_path_with_slash}/" unless entry_path_with_slash.end_with?('/')
            if !top_path.nil? && !top_path.start_with?(entry_path_with_slash) && !entry_path_with_slash.start_with?(top_path)
              Log.log.debug{"#{entry['path']} folder (skip start)".bg_red}
              next
            end
            Log.log.debug{"item:#{entry}"}
            begin
              case entry['type']
              when 'file'
                if @filter_block.call(entry)
                  generate_preview(entry)
                else
                  Log.log.debug('skip by filter')
                end
              when 'link'
                Log.log.debug('Ignoring link.')
              when 'folder'
                if @option_skip_folders.include?(entry['path'])
                  Log.log.debug{"#{entry['path']} folder (skip list)".bg_red}
                else
                  Log.log.debug{"#{entry['path']} folder".green}
                  # get folder content
                  folder_entries = get_folder_entries(entry['id'])
                  # process all items in current folder
                  folder_entries.each do |folder_entry|
                    # add path for older versions of ES
                    folder_entry['path'] = entry_path_with_slash + folder_entry['name'] if !folder_entry.key?('path')
                    folder_entry['parent_file_id'] = entry['id']
                    entries_to_process.push(folder_entry)
                  end
                end
              else
                Log.log.warn{"unknown entry type: #{entry['type']}"}
              end
            rescue StandardError => e
              Log.log.warn{"An error occurred: #{e}, ignoring"}
            end
          end
        end

        ACTIONS = %i[scan events trevents check test show].freeze

        def execute_action
          command = options.get_next_command(ACTIONS)
          unless %i[check test show].include?(command)
            # this will use node api
            @api_node = Api::Node.new(**basic_auth_params)
            @transfer_server_address = URI.parse(@api_node.base_url).host
            # get current access key
            @access_key_self = @api_node.read('access_keys/self')
            # TODO: check events is activated here:
            # note that docroot is good to look at as well
            node_info = @api_node.read('info')
            Log.log.debug{"root: #{node_info['docroot']}"}
            @access_remote = @option_file_access.eql?(:remote)
            Log.log.debug{"remote: #{@access_remote}"}
            Log.log.debug{"access key info: #{@access_key_self}"}
            # TODO: can the previews folder parameter be read from node api ?
            @option_skip_folders.push("/#{@option_previews_folder}")
            if @access_remote
              # NOTE: the filter "name", it's why we take the first one
              @previews_folder_entry = get_folder_entries(@access_key_self['root_file_id'], {name: @option_previews_folder}).first
              raise Cli::Error, "Folder #{@option_previews_folder} does not exist on node. " \
                'Please create it in the storage root, or specify an alternate name.' if @previews_folder_entry.nil?
            else
              Aspera.assert(@access_key_self['storage']['type'].eql?('local')){'only local storage allowed in this mode'}
              @local_storage_root = @access_key_self['storage']['path']
              # TODO: option to override @local_storage_root='xxx'
              @local_storage_root = @local_storage_root[PVCL_LOCAL_STORAGE.length..-1] if @local_storage_root.start_with?(PVCL_LOCAL_STORAGE)
              # TODO: windows could have "C:" ?
              Aspera.assert(@local_storage_root.start_with?('/')){"not local storage: #{@local_storage_root}"}
              Aspera.assert(File.directory?(@local_storage_root), type: Cli::Error){"Local storage root folder #{@local_storage_root} does not exist."}
              @local_preview_folder = File.join(@local_storage_root, @option_previews_folder)
              raise Cli::Error, "Folder #{@local_preview_folder} does not exist locally. " \
                'Please create it, or specify an alternate name.' unless File.directory?(@local_preview_folder)
              # protection to avoid clash of file id for two different access keys
              marker_file = File.join(@local_preview_folder, AK_MARKER_FILE)
              Log.log.debug{"marker file: #{marker_file}"}
              if File.exist?(marker_file)
                ak = File.read(marker_file).chomp
                Aspera.assert(@access_key_self['id'].eql?(ak)){"mismatch access key in #{marker_file}: contains #{ak}, using #{@access_key_self['id']}"}
              else
                File.write(marker_file, @access_key_self['id'])
              end
            end
          end
          Aspera::Preview::FileTypes.instance.use_mimemagic = options.get_option(:mimemagic, mandatory: true)
          # check tools that are anyway required for all cases
          Aspera::Preview::Utils.check_tools(@option_skip_types)
          case command
          when :scan
            scan_path = options.get_option(:scan_path)
            scan_id = options.get_option(:scan_id)
            # by default start at root
            folder_info =
              if scan_id.nil?
                {
                  'id'   => @access_key_self['root_file_id'],
                  'name' => '/',
                  'type' => 'folder',
                  'path' => '/'
                }
              else
                @api_node.read("files/#{scan_id}")
              end
            @filter_block = Api::Node.file_matcher_from_argument(options)
            scan_folder_files(folder_info, scan_path)
            return Main.result_status('scan finished')
          when :events, :trevents
            @filter_block = Api::Node.file_matcher_from_argument(options)
            iteration_persistency = nil
            if options.get_option(:once_only, mandatory: true)
              iteration_persistency = PersistencyActionOnce.new(
                manager: persistency,
                data:    [],
                id:      IdGenerator.from_list(
                  'preview_iteration',
                  command.to_s,
                  options.get_option(:url, mandatory: true),
                  options.get_option(:username, mandatory: true)
                )
              )
            end
            # call processing method specified by command line command
            send(:"process_#{command}", iteration_persistency)
            return Main.result_status("#{command} finished")
          when :check
            return Main.result_status('Tools validated')
          when :test, :show
            source = options.get_next_argument('source file')
            format = options.get_next_argument('format', accept_list: Aspera::Preview::Generator::PREVIEW_FORMATS, default: :png)
            generated_file_path = preview_filename(format, options.get_option(:base))
            g = Aspera::Preview::Generator.new(source, generated_file_path, @gen_options, @tmp_folder, nil)
            g.generate
            if command.eql?(:show)
              terminal_options = (options.get_option(:query) || {}).symbolize_keys
              Log.log.debug{"preview: #{generated_file_path}"}
              formatter.display_status(Aspera::Preview::Terminal.build(File.read(generated_file_path), **terminal_options))
            end
            return Main.result_status("generated: #{generated_file_path}")
          else Aspera.error_unexpected_value(command)
          end
        ensure
          Log.log.debug{"cleaning up temp folder #{@tmp_folder}"}
          FileUtils.rm_rf(@tmp_folder)
        end
      end
    end
  end
end
