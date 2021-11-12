require 'aspera/cli/basic_auth_plugin'
require 'aspera/preview/generator'
require 'aspera/preview/options'
require 'aspera/preview/utils'
require 'aspera/preview/file_types'
require 'aspera/persistency_action_once'
require 'aspera/node'
require 'aspera/hash_ext'
require 'aspera/timer_limiter'
require 'aspera/id_generator'
require 'date'
require 'securerandom'

module Aspera
  module Cli
    module Plugins
      class Preview < BasicAuthPlugin
        # special tag to identify transfers related to generator
        PREV_GEN_TAG='preview_generator'
        # defined by node API: suffix for folder containing previews
        PREVIEW_FOLDER_SUFFIX='.asp-preview'
        # basename of preview files
        PREVIEW_BASENAME='preview'
        # subfolder in system tmp folder
        TMP_DIR_PREFIX='prev_tmp'
        DEFAULT_PREVIEWS_FOLDER='previews'
        AK_MARKER_FILE='.aspera_access_key'
        LOCAL_STORAGE_PCVL='file:///'
        LOG_LIMITER_SEC=30.0
        private_constant :PREV_GEN_TAG, :PREVIEW_FOLDER_SUFFIX, :PREVIEW_BASENAME, :TMP_DIR_PREFIX, :DEFAULT_PREVIEWS_FOLDER, :LOCAL_STORAGE_PCVL, :AK_MARKER_FILE, :LOG_LIMITER_SEC

        # option_skip_format has special accessors
        attr_accessor :option_previews_folder
        attr_accessor :option_folder_reset_cache
        attr_accessor :option_skip_folders
        attr_accessor :option_overwrite
        attr_accessor :option_file_access
        def initialize(env)
          super(env)
          @skip_types=[]
          @default_transfer_spec=nil
          # by default generate all supported formats (clone, as altered by options)
          @preview_formats_to_generate=Aspera::Preview::Generator::PREVIEW_FORMATS.clone
          # options for generation
          @gen_options=Aspera::Preview::Options.new
          # used to trigger periodic processing
          @periodic=TimerLimiter.new(LOG_LIMITER_SEC)
          # link CLI options to gen_info attributes
          self.options.set_obj_attr(:skip_format,self,:option_skip_format,[]) # no skip
          self.options.set_obj_attr(:folder_reset_cache,self,:option_folder_reset_cache,:no)
          self.options.set_obj_attr(:skip_types,self,:option_skip_types)
          self.options.set_obj_attr(:previews_folder,self,:option_previews_folder,DEFAULT_PREVIEWS_FOLDER)
          self.options.set_obj_attr(:skip_folders,self,:option_skip_folders,[]) # no skip
          self.options.set_obj_attr(:overwrite,self,:option_overwrite,:mtime)
          self.options.set_obj_attr(:file_access,self,:option_file_access,:local)
          self.options.add_opt_list(:skip_format,Aspera::Preview::Generator::PREVIEW_FORMATS,'skip this preview format (multiple possible)')
          self.options.add_opt_list(:folder_reset_cache,[:no,:header,:read],'force detection of generated preview by refresh cache')
          self.options.add_opt_simple(:skip_types,'skip types in comma separated list')
          self.options.add_opt_simple(:previews_folder,'preview folder in storage root')
          self.options.add_opt_simple(:temp_folder,'path to temp folder')
          self.options.add_opt_simple(:skip_folders,'list of folder to skip')
          self.options.add_opt_simple(:case,'basename of output for for test')
          self.options.add_opt_simple(:scan_path,'subpath in folder id to start scan in (default=/)')
          self.options.add_opt_simple(:scan_id,'forder id in storage to start scan in, default is access key main folder id')
          self.options.add_opt_boolean(:mimemagic,'use Mime type detection of gem mimemagic')
          self.options.add_opt_list(:overwrite,[:always,:never,:mtime],'when to overwrite result file')
          self.options.add_opt_list(:file_access,[:local,:remote],'how to read and write files in repository')
          self.options.set_option(:temp_folder,Dir.tmpdir)
          self.options.set_option(:mimemagic,:false)

          # add other options for generator (and set default values)
          Aspera::Preview::Options::DESCRIPTIONS.each do |opt|
            self.options.set_obj_attr(opt[:name],@gen_options,opt[:name],opt[:default])
            if opt.has_key?(:values)
              self.options.add_opt_list(opt[:name],opt[:values],opt[:description])
            elsif [:yes,:no].include?(opt[:default])
              self.options.add_opt_boolean(opt[:name],opt[:description])
            else
              self.options.add_opt_simple(opt[:name],opt[:description])
            end
          end

          self.options.parse_options!
          raise 'skip_folder shall be an Array, use @json:[...]' unless @option_skip_folders.is_a?(Array)
          @tmp_folder=File.join(self.options.get_option(:temp_folder,:mandatory),"#{TMP_DIR_PREFIX}.#{SecureRandom.uuid}")
          FileUtils.mkdir_p(@tmp_folder)
          Log.log.debug("tmpdir: #{@tmp_folder}")
        end

        def option_skip_types=(value)
          @skip_types=[]
          value.split(',').each do |v|
            s=v.to_sym
            raise "not supported: #{v}" unless Aspera::Preview::FileTypes::CONVERSION_TYPES.include?(s)
            @skip_types.push(s)
          end
        end

        def option_skip_types
          return @skip_types.map{|i|i.to_s}.join(',')
        end

        def option_skip_format=(value)
          @preview_formats_to_generate.delete(value)
        end

        def option_skip_format
          return @preview_formats_to_generate.map{|i|i.to_s}.join(',')
        end

        # /files/id/files is normally cached in redis, but we can discard the cache
        # but /files/id is not cached
        def get_folder_entries(file_id,request_args=nil)
          headers={'Accept'=>'application/json'}
          headers.merge!({'X-Aspera-Cache-Control'=>'no-cache'}) if @option_folder_reset_cache.eql?(:header)
          return @api_node.call({:operation=>'GET',:subpath=>"files/#{file_id}/files",:headers=>headers,:url_params=>request_args})[:data]
          #return @api_node.read("files/#{file_id}/files",request_args)[:data]
        end

        # old version based on folders
        # @param iteration_persistency can be nil
        def process_trevents(iteration_persistency)
          events_filter={
            'access_key'=>@access_key_self['id'],
            'type'=>'download.ended'
          }
          # optionally add iteration token from persistency
          events_filter['iteration_token']=iteration_persistency.data.first unless iteration_persistency.nil?
          begin
            events=@api_node.read('events',events_filter)[:data]
          rescue RestCallError => e
            if e.message.include?('Invalid iteration_token')
              Log.log.warn("Retrying without iteration token: #{e}")
              events_filter.delete('iteration_token')
              retry
            end
            raise e
          end
          return if events.empty?
          events.each do |event|
            if event['data']['direction'].eql?('receive') and
            event['data']['status'].eql?('completed') and
            event['data']['error_code'].eql?(0) and
            event['data'].dig('tags','aspera',PREV_GEN_TAG).nil?
              folder_id=event.dig('data','tags','aspera','node','file_id')
              folder_id||=event.dig('data','file_id')
              if !folder_id.nil?
                folder_entry=@api_node.read("files/#{folder_id}")[:data] rescue nil
                scan_folder_files(folder_entry) unless folder_entry.nil?
              end
            end
            if @periodic.trigger? or event.equal?(events.last)
              Log.log.info("Processed event #{event['id']}")
              # save checkpoint to avoid losing processing in case of error
              if !iteration_persistency.nil?
                iteration_persistency.data[0]=event['id'].to_s
                iteration_persistency.save
              end
            end
          end
        end

        # requests recent events on node api and process newly modified folders
        def process_events(iteration_persistency)
          # get new file creation by access key (TODO: what if file already existed?)
          events_filter={
            'access_key'=>@access_key_self['id'],
            'type'=>'file.*'
          }
          # optionally add iteration token from persistency
          events_filter['iteration_token']=iteration_persistency.data.first unless iteration_persistency.nil?
          events=@api_node.read('events',events_filter)[:data]
          return if events.empty?
          events.each do |event|
            # process only files
            if event.dig('data','type').eql?('file')
              file_entry=@api_node.read("files/#{event['data']['id']}")[:data] rescue nil
              if !file_entry.nil? and
              @option_skip_folders.select{|d|file_entry['path'].start_with?(d)}.empty?
                file_entry['parent_file_id']=event['data']['parent_file_id']
                if event['types'].include?('file.deleted')
                  Log.log.error('TODO'.red)
                end
                if event['types'].include?('file.deleted')
                  generate_preview(file_entry)
                end
              end
            end
            if @periodic.trigger? or event.equal?(events.last)
              Log.log.info("Processing event #{event['id']}")
              # save checkpoint to avoid losing processing in case of error
              if !iteration_persistency.nil?
                iteration_persistency.data[0]=event['id'].to_s
                iteration_persistency.save
              end
            end
          end
        end

        def do_transfer(direction,folder_id,source_filename,destination='/')
          raise "error" if destination.nil? and direction.eql?('receive')
          if @default_transfer_spec.nil?
            # make a dummy call to get some default transfer parameters
            res=@api_node.create('files/upload_setup',{'transfer_requests'=>[{'transfer_request'=>{'paths'=>[{}],'destination_root'=>'/'}}]})
            template_ts=res[:data]['transfer_specs'].first['transfer_spec']
            # get ports, anyway that should be 33001 for both. add remote_user ?
            @default_transfer_spec=['ssh_port','fasp_port'].inject({}){|h,e|h[e]=template_ts[e];h}
            if ! @default_transfer_spec['remote_user'].eql?(Aspera::Node::ACCESS_KEY_TRANSFER_USER)
              Log.log.warn("remote_user shall be xfer")
              @default_transfer_spec['remote_user']=Aspera::Node::ACCESS_KEY_TRANSFER_USER
            end
            Aspera::Node::set_ak_basic_token(@default_transfer_spec,@access_key_self['id'],self.options.get_option(:password,:mandatory))
            # note: we use the same address for ascp than for node api instead of the one from upload_setup
            # TODO: configurable ? useful ?
            @default_transfer_spec['remote_host']=@transfer_server_address
          end
          tspec=@default_transfer_spec.merge({
            'direction'  => direction,
            'paths'      => [{'source'=>source_filename}],
            'tags'       => { 'aspera' => {
            PREV_GEN_TAG   => true,
            'node'         => {
            'access_key'     => @access_key_self['id'],
            'file_id'        => folder_id }}}
          })
          # force destination
          # tspec['destination_root']=destination
          self.transfer.option_transfer_spec_deep_merge({'destination_root'=>destination})
          Main.result_transfer(self.transfer.start(tspec,{:src=>:node_gen4}))
        end

        def get_infos_local(gen_infos,entry,local_entry_preview_dir)
          local_original_filepath=File.join(@local_storage_root,entry['path'])
          original_mtime=File.mtime(local_original_filepath)
          # out
          local_entry_preview_dir.replace(File.join(@local_preview_folder, entry_preview_folder_name(entry)))
          gen_infos.each do |gen_info|
            gen_info[:src]=local_original_filepath
            gen_info[:dst]=File.join(local_entry_preview_dir, gen_info[:base_dest])
            gen_info[:preview_exist]=File.exist?(gen_info[:dst])
            gen_info[:preview_newer_than_original] = (gen_info[:preview_exist] and (File.mtime(gen_info[:dst])>original_mtime))
          end
        end

        def get_infos_remote(gen_infos,entry,local_entry_preview_dir)
          #Log.log.debug(">>>> get_infos_remote #{entry}".red)
          # store source directly here
          local_original_filepath=File.join(@tmp_folder,entry['name'])
          #original_mtime=DateTime.parse(entry['modified_time'])
          # out: where previews are generated
          local_entry_preview_dir.replace(File.join(@tmp_folder,entry_preview_folder_name(entry)))
          file_info=@api_node.read("files/#{entry['id']}")[:data]
          #TODO: this does not work because previews is hidden in api (gen4)
          #this_preview_folder_entries=get_folder_entries(@previews_folder_entry['id'],{:name=>@entry_preview_folder_name})
          # TODO: use gen3 api to list files and get date
          gen_infos.each do |gen_info|
            gen_info[:src]=local_original_filepath
            gen_info[:dst]=File.join(local_entry_preview_dir, gen_info[:base_dest])
            # TODO: use this_preview_folder_entries (but it's hidden)
            gen_info[:preview_exist]=file_info.has_key?('preview')
            # TODO: get change time and compare, useful ?
            gen_info[:preview_newer_than_original] = gen_info[:preview_exist]
          end
        end

        # defined by node api
        def entry_preview_folder_name(entry)
          "#{entry['id']}#{PREVIEW_FOLDER_SUFFIX}"
        end

        def preview_filename(preview_format,filename=nil)
          filename||=PREVIEW_BASENAME
          return "#{filename}.#{preview_format.to_s}"
        end

        # generate preview files for one folder entry (file) if necessary
        # entry must contain "parent_file_id" if remote.
        def generate_preview(entry)
          #Log.log.debug(">>>> #{entry}".red)
          # folder where previews will be generated for this particular entry
          local_entry_preview_dir=String.new
          # prepare generic information
          gen_infos=@preview_formats_to_generate.map do |preview_format|
            {
              :preview_format => preview_format,
              :base_dest      => preview_filename(preview_format)
            }
          end
          # lets gather some infos on possibly existing previews
          # it depends if files access locally or remotely
          if @access_remote
            get_infos_remote(gen_infos,entry,local_entry_preview_dir)
          else # direct local file system access
            get_infos_local(gen_infos,entry,local_entry_preview_dir)
          end
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
            # need generator for further checks
            gen_info[:generator]=Aspera::Preview::Generator.new(@gen_options,gen_info[:src],gen_info[:dst],@tmp_folder,entry['content_type'])
            # get conversion_type (if known) and check if supported
            next false unless gen_info[:generator].supported?
            # shall we skip it ?
            next false if @skip_types.include?(gen_info[:generator].conversion_type)
            # ok we need to generate
            true
          end
          return if gen_infos.empty?
          # create folder if needed
          FileUtils.mkdir_p(local_entry_preview_dir)
          if @access_remote
            raise 'missing parent_file_id in entry' if entry['parent_file_id'].nil?
            #  download original file to temp folder
            do_transfer('receive',entry['parent_file_id'],entry['name'],@tmp_folder)
          end
          Log.log.info("source: #{entry['id']}: #{entry['path']})")
          gen_infos.each do |gen_info|
            gen_info[:generator].generate rescue nil
          end
          if @access_remote
            # upload
            do_transfer('send',@previews_folder_entry['id'],local_entry_preview_dir)
            # cleanup after upload
            FileUtils.rm_rf(local_entry_preview_dir)
            File.delete(File.join(@tmp_folder,entry['name']))
          end
          # force read file updated previews
          if @option_folder_reset_cache.eql?(:read)
            @api_node.read("files/#{entry['id']}")
          end
        rescue => e
          Log.log.error("#{e.message}")
          Log.log.debug(e.backtrace.join("\n").red)
        end # generate_preview

        # scan all files in provided folder entry
        # @param scan_start subpath to start folder scan inside
        def scan_folder_files(top_entry,scan_start=nil)
          if !scan_start.nil?
            # canonical path: start with / and ends with /
            scan_start='/'+scan_start.split('/').select{|i|!i.empty?}.join('/')
            scan_start="#{scan_start}/" #unless scan_start.end_with?('/')
          end
          filter_block=Aspera::Node.file_matcher(options.get_option(:value,:optional))
          Log.log.debug("scan: #{top_entry} : #{scan_start}".green)
          # don't use recursive call, use list instead
          entries_to_process=[top_entry]
          while !entries_to_process.empty?
            entry=entries_to_process.shift
            # process this entry only if it is within the scan_start
            entry_path_with_slash=entry['path']
            Log.log.info("processing entry #{entry_path_with_slash}") if @periodic.trigger?
            entry_path_with_slash="#{entry_path_with_slash}/" unless entry_path_with_slash.end_with?('/')
            if !scan_start.nil? and !scan_start.start_with?(entry_path_with_slash) and !entry_path_with_slash.start_with?(scan_start)
              Log.log.debug("#{entry['path']} folder (skip start)".bg_red)
              next
            end
            Log.log.debug("item:#{entry}")
            begin
              case entry['type']
              when 'file'
                if filter_block.call(entry)
                  generate_preview(entry)
                else
                  Log.log.debug('skip by filter')
                end
              when 'link'
                Log.log.debug('Ignoring link.')
              when 'folder'
                if @option_skip_folders.include?(entry['path'])
                  Log.log.debug("#{entry['path']} folder (skip list)".bg_red)
                else
                  Log.log.debug("#{entry['path']} folder".green)
                  # get folder content
                  folder_entries=get_folder_entries(entry['id'])
                  # process all items in current folder
                  folder_entries.each do |folder_entry|
                    # add path for older versions of ES
                    if !folder_entry.has_key?('path')
                      folder_entry['path']=entry_path_with_slash+folder_entry['name']
                    end
                    folder_entry['parent_file_id']=entry['id']
                    entries_to_process.push(folder_entry)
                  end
                end
              else
                Log.log.warn("unknown entry type: #{entry['type']}")
              end
            rescue => e
              Log.log.warn("An error occured: #{e}, ignoring")
            end
          end
        end

        ACTIONS=[:scan,:events,:trevents,:check,:test]

        def execute_action
          command=self.options.get_next_command(ACTIONS)
          unless [:check,:test].include?(command)
            # this will use node api
            @api_node=basic_auth_api
            @transfer_server_address=URI.parse(@api_node.params[:base_url]).host
            # get current access key
            @access_key_self=@api_node.read('access_keys/self')[:data]
            # TODO: check events is activated here:
            # note that docroot is good to look at as well
            node_info=@api_node.read('info')[:data]
            Log.log.debug("root: #{node_info['docroot']}")
            @access_remote=@option_file_access.eql?(:remote)
            Log.log.debug("remote: #{@access_remote}")
            Log.log.debug("access key info: #{@access_key_self}")
            #TODO: can the previews folder parameter be read from node api ?
            @option_skip_folders.push('/'+@option_previews_folder)
            if @access_remote
              # note the filter "name", it's why we take the first one
              @previews_folder_entry=get_folder_entries(@access_key_self['root_file_id'],{:name=>@option_previews_folder}).first
              raise CliError,"Folder #{@option_previews_folder} does not exist on node. Please create it in the storage root, or specify an alternate name." if @previews_folder_entry.nil?
            else
              raise "only local storage allowed in this mode" unless @access_key_self['storage']['type'].eql?('local')
              @local_storage_root=@access_key_self['storage']['path']
              #TODO: option to override @local_storage_root='xxx'
              @local_storage_root=@local_storage_root[LOCAL_STORAGE_PCVL.length..-1] if @local_storage_root.start_with?(LOCAL_STORAGE_PCVL)
              #TODO: windows could have "C:" ?
              raise "not local storage: #{@local_storage_root}" unless @local_storage_root.start_with?('/')
              raise CliError,"Local storage root folder #{@local_storage_root} does not exist." unless File.directory?(@local_storage_root)
              @local_preview_folder=File.join(@local_storage_root,@option_previews_folder)
              raise CliError,"Folder #{@local_preview_folder} does not exist locally. Please create it, or specify an alternate name." unless File.directory?(@local_preview_folder)
              # protection to avoid clash of file id for two different access keys
              marker_file=File.join(@local_preview_folder,AK_MARKER_FILE)
              Log.log.debug("marker file: #{marker_file}")
              if File.exist?(marker_file)
                ak=File.read(marker_file)
                raise "mismatch access key in #{marker_file}: contains #{ak}, using #{@access_key_self['id']}" unless @access_key_self['id'].eql?(ak)
              else
                File.write(marker_file,@access_key_self['id'])
              end
            end
          end
          Aspera::Preview::FileTypes.instance.use_mimemagic = self.options.get_option(:mimemagic,:mandatory)
          case command
          when :scan
            scan_path=self.options.get_option(:scan_path,:optional)
            scan_id=self.options.get_option(:scan_id,:optional)
            # by default start at root
            folder_info=if scan_id.nil?
              { 'id'   => @access_key_self['root_file_id'],
                'name' => '/',
                'type' => 'folder',
                'path' => '/' }
            else
              @api_node.read("files/#{scan_id}")[:data]
            end
            scan_folder_files(folder_info,scan_path)
            return Main.result_status('scan finished')
          when :events,:trevents
            iteration_persistency=nil
            if self.options.get_option(:once_only,:mandatory)
              iteration_persistency=PersistencyActionOnce.new(
              manager: @agents[:persistency],
              data:    [],
              id:      IdGenerator.from_list(['preview_iteration',command.to_s,self.options.get_option(:url,:mandatory),self.options.get_option(:username,:mandatory)]))
            end
            # call processing method specified by command line command
            send("process_#{command}",iteration_persistency)
            return Main.result_status("#{command} finished")
          when :check
            Aspera::Preview::Utils.check_tools(@skip_types)
            return Main.result_status('tools validated')
          when :test
            format = self.options.get_next_argument('format',Aspera::Preview::Generator::PREVIEW_FORMATS)
            source = self.options.get_next_argument('source file')
            dest=preview_filename(format,self.options.get_option(:case,:optional))
            g=Aspera::Preview::Generator.new(@gen_options,source,dest,@tmp_folder,nil)
            raise "cannot find file type for #{source}" if g.conversion_type.nil?
            raise "out format #{format} not supported" unless g.supported?
            g.generate
            return Main.result_status("generated: #{dest}")
          else
            raise "error"
          end
        ensure
          FileUtils.rm_rf(@tmp_folder)
        end # execute_action
      end # Preview
    end # Plugins
  end # Cli
end # Aspera
