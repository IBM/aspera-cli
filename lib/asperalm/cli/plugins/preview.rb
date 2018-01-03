require 'asperalm/cli/main'
require 'asperalm/cli/basic_auth_plugin'
require 'asperalm/preview_generator'
require 'asperalm/fasp/agent'
require 'date'

class Hash
  def dig(*path)
    path.inject(self) do |location, key|
      location.respond_to?(:keys) ? location[key] : nil
    end
  end
end

module Asperalm
  module Cli
    module Plugins
      class Preview < BasicAuthPlugin

        attr_accessor :option_overwrite
        attr_accessor :option_iteration_file_filepath

        # special tag to identify transfers related to generator
        PREV_GEN_TAG='preview_generator'
        # values for option_overwrite
        def self.overwrite_policies; [:always,:never,:mtime];end

        def option_skip_types=(value)
          @skip_types=[]
          value.split(',').each do |v|
            s=v.to_sym
            raise "not supported: #{v}" unless PreviewGenerator.supported_types.include?(s)
            @skip_types.push(s)
          end
        end

        def option_skip_types()
          return @skip_types.map{|i|i.to_s}.join(',')
        end

        def initialize
          @skip_types=[]
          # link CLI options to generator attributes
          Main.tool.options.set_option(:file_access,:file_system)
          Main.tool.options.set_obj_attr(:skip_types,self,:option_skip_types)
          Main.tool.options.set_obj_attr(:overwrite,self,:option_overwrite,:mtime)
          Main.tool.options.set_obj_attr(:iteration_file,self,:option_iteration_file_filepath,nil)
          Main.tool.options.set_obj_attr(:video,PreviewGenerator.instance,:option_video_style,:reencode)
          Main.tool.options.set_obj_attr(:vid_offset_seconds,PreviewGenerator.instance,:option_vid_offset_seconds,10)
          Main.tool.options.set_obj_attr(:vid_size,PreviewGenerator.instance,:option_vid_size,'320:-2')
          Main.tool.options.set_obj_attr(:vid_framecount,PreviewGenerator.instance,:option_vid_framecount,30)
          Main.tool.options.set_obj_attr(:vid_blendframes,PreviewGenerator.instance,:option_vid_blendframes,2)
          Main.tool.options.set_obj_attr(:vid_framepause,PreviewGenerator.instance,:option_vid_framepause,5)
          Main.tool.options.set_obj_attr(:vid_fps,PreviewGenerator.instance,:option_vid_fps,15)
          Main.tool.options.set_obj_attr(:vid_mp4_size_reencode,PreviewGenerator.instance,:option_vid_mp4_size_reencode,"-2:'min(ih,360)'")
          Main.tool.options.set_obj_attr(:clips_offset_seconds,PreviewGenerator.instance,:option_clips_offset_seconds,10)
          Main.tool.options.set_obj_attr(:clips_size,PreviewGenerator.instance,:option_clips_size,'320:-2')
          Main.tool.options.set_obj_attr(:clips_length,PreviewGenerator.instance,:option_clips_length,5)
          Main.tool.options.set_obj_attr(:clips_count,PreviewGenerator.instance,:option_clips_count,5)
          Main.tool.options.set_obj_attr(:thumb_mp4_size,PreviewGenerator.instance,:option_thumb_mp4_size,"-1:'min(ih,600)'")
          Main.tool.options.set_obj_attr(:thumb_img_size,PreviewGenerator.instance,:option_thumb_img_size,800)
          Main.tool.options.set_obj_attr(:thumb_offset_fraction,PreviewGenerator.instance,:option_thumb_offset_fraction,0.1)
        end

        alias super_declare_options declare_options

        def declare_options
          super_declare_options
          Main.tool.options.add_opt_list(:file_access,[:file_system,:fasp],"how to read and write files in repository")
          Main.tool.options.add_opt_simple(:skip_types,"LIST","skip types in comma separated list")
          Main.tool.options.add_opt_list(:overwrite,Preview.overwrite_policies,"when to generate preview file")
          Main.tool.options.add_opt_simple(:iteration_file,"PATH","path to iteration memory file")
          Main.tool.options.add_opt_list(:video,PreviewGenerator.video_styles,"method to generate video")
        end

        def action_list; [:scan,:events,:folder];end

        # requests recent events on node api and process newly modified folders
        def process_file_events1
          args={'access_key'=>@access_key_self['id']}
          args['iteration_token']=File.read(@option_iteration_file_filepath) unless @option_iteration_file_filepath.nil?
          events=@api_node.read("events",args)[:data]
          event_folder_ids=[]
          # this will be new iteration token
          last_processed_iteration=events.last['id'] unless events.empty?
          events.each do |event|
            if event['types'].include?('download.ended') and
            event['data']['direction'].eql?('receive') and
            event['data']['status'].eql?('completed') and
            event['data']['error_code'].eql?(0) and
            #!event.dig('data','tags','aspera').nil? and
            event.dig('data','tags','aspera',PREV_GEN_TAG).nil?
              #upload_folder=event.dig('data','tags','aspera','node','file_id')
              #upload_folder=event.dig('data','file_id')
              folder_id=event.dig('data','file_id')
              event_folder_ids.push(folder_id) unless folder_id.nil?
              Log.log.debug(">>#{event['id']}: #{folder_id}".red)
            end
          end

          # write new iteration file
          event_folder_ids.each do |file_id|
            folder_entry=@api_node.read("files/#{file_id}")[:data] rescue nil
            scan_folder_files(folder_entry) unless folder_entry.nil?
          end
          File.write(@option_iteration_file_filepath,last_processed_iteration.to_s) unless @option_iteration_file_filepath.nil? or last_processed_iteration.nil?
        end

        def process_file_events
          events_filter={'access_key'=>@access_key_self['id']}
          begin
            events_filter['iteration_token']=File.read(@option_iteration_file_filepath) unless @option_iteration_file_filepath.nil?
          rescue
          end
          events=@api_node.read("events",events_filter)[:data]
          return if events.empty?
          item_to_process=[]
          last_processed_iteration=events.last['id']
          Log.log.debug("old/new iteration: #{events_filter['iteration_token']} - #{last_processed_iteration}")
          events.each do |event|
            if event['types'].include?('file.created') and
            event.dig('data','type').eql?('file')
              item_to_process.push(event)
            end
          end

          item_to_process.each do |item|
            folder_entry=@api_node.read("files/#{item['data']['id']}")[:data] rescue nil
            next if folder_entry.nil?
            next if folder_entry['path'].start_with?("/#{@option_preview_folder}/")
            unless folder_entry.nil?
              folder_entry['parent_file_id']=item['data']['parent_file_id']
              generate_preview(folder_entry)
            end
          end
          # write new iteration file
          Log.log.debug("write #{@option_iteration_file_filepath} - #{last_processed_iteration}")
          File.write(@option_iteration_file_filepath,last_processed_iteration.to_s) unless @option_iteration_file_filepath.nil? or last_processed_iteration.nil?
        end

        # direction: send / receive
        def do_transfer(direction,folder_id,source_filename,destination=nil)
          tspec={
            'direction'        => direction,
            'paths'            => [{'source'=>source_filename}],
            'remote_user'      => 'xfer',
            'remote_host'      => @transfer_address,
            "fasp_port"        => 33001, # TODO: always the case ?
            "ssh_port"         => 33001, # TODO: always the case ?
            'token'            => @basic_token,
            'authentication'   => "token", # bypass ssh # TODO: doc
            'EX_quiet'         => true,
            'tags'             => { "aspera" => {
            PREV_GEN_TAG  => true,
            "node"        => { "access_key" => @access_key_self['id'], "file_id" => folder_id },
            "xfer_id"     => SecureRandom.uuid,
            "xfer_retry"  => 3600 } }
          }
          tspec['destination_root']='/' if direction.eql?("send")
          tspec['destination_root']=destination unless destination.nil?
          Fasp::Manager.instance.start_transfer(tspec)
        end

        # generate preview files for one folder entry (file) if necessary
        # entry must contain "parent_file_id" if remote.
        def generate_preview(entry)
          original_extension=File.extname(entry['name']).downcase
          # file on local file system containing original file for transcoding
          local_original_filepath=nil
          # modification time of original file (actual, not local copy)
          original_mtime=nil
          # where previews will be generated for this particular entry
          local_entry_preview_dir=nil
          # does it need to be created?
          need_create_local_folder=nil
          # infos on current state on previews (actual)
          preview_infos=nil
          entry_preview_folder_name="#{entry['id']}.asp-preview"
          # optimisation, work direct with files on filesystem
          if @is_local
            local_original_filepath=File.join(@local_storage_root,entry['path'])
            original_mtime=File.mtime(local_original_filepath)
            local_entry_preview_dir = File.join(@local_preview_folder, entry_preview_folder_name)
            need_create_local_folder=!File.directory?(local_entry_preview_dir) # Hmmm
            preview_infos=PreviewGenerator.preview_formats.map do |out_format|
              local_preview_filepath=File.join(local_entry_preview_dir, 'preview.'+out_format)
              local_preview_exists=File.exists?(local_preview_filepath)
              {
                :extension => original_extension,
                :mime => entry['content_type'],
                :out_format => out_format,
                :dest => local_preview_filepath,
                :exist => local_preview_exists,
                :preview_newer? => (local_preview_exists and (File.mtime(local_preview_filepath)>original_mtime))
              }
            end
          else
            main_temp_folder="/tmp/toto" # TODO: mkdir
            local_original_filepath=File.join(main_temp_folder,entry['name'])
            original_mtime=DateTime.parse(entry['modified_time'])
            local_entry_preview_dir=File.join(main_temp_folder,entry_preview_folder_name)
            need_create_local_folder=true
            #TODO: by api, read content of entry preview folder on storage
            preview_folder_entry=@api_node.read("files/#{@previews_entry['id']}/files",{:name=>entry_preview_folder_name})[:data]

            # and build preview_infos
            preview_infos=PreviewGenerator.preview_formats.map do |out_format|
              local_preview_filepath=File.join(local_entry_preview_dir, 'preview.'+out_format)
              local_preview_exists=false
              {
                :extension => original_extension,
                :mime => entry['content_type'],
                :out_format => out_format,
                :dest => local_preview_filepath,
                :exist => local_preview_exists,
                :preview_newer? => false,
                :method => nil
              }
            end
          end
          # here we have the status on preview files, let's find if they need generation
          to_generate=[]
          preview_infos.each do |preview_info|
            # if it exists, what about overwrite policy ?
            if preview_info[:exist]
              case @option_overwrite
              when :always
                # continue: generate
              when :never
                # never overwrite
                next
              when :mtime
                # skip if preview is newer than original
                next if preview_info[:preview_newer?]
              end
            end
            # get type and method
            PreviewGenerator.instance.set_type_method(preview_info)
            # is this a known file extension ?
            next if preview_info[:source_type].nil?
            # shall we skip it ?
            next if @skip_types.include?(preview_info[:source_type].to_sym)
            # can we manage it ?
            next if preview_info[:method].nil?
            # ok, it's passed ! need generation
            to_generate.push({:method=>preview_info[:method],:dest=>preview_info[:dest]})
          end
          unless to_generate.empty?
            FileUtils.mkdir_p(local_entry_preview_dir) if need_create_local_folder
            if !@is_local
              #transfer original file to folder main_temp_folder
              raise "parent not computed" if entry['parent_file_id'].nil?
              do_transfer('receive',entry['parent_file_id'],entry['name'],main_temp_folder)
            end
            to_generate.each do |info|
              begin
                puts(info[:dest])
                PreviewGenerator.instance.generate(info[:method],local_original_filepath,info[:dest])
              rescue => e
                Log.log.error("exception: #{e.message}:\n#{e.backtrace.join("\n")}".red)
              end
            end
            if !@is_local
              # TODO: upload
              do_transfer('send',@previews_entry['id'],local_entry_preview_dir)
              #TODO: delete main_temp_folder and below
              FileUtils.rm_rf(main_temp_folder)
            end
          end
        rescue => e
          Log.log.error("An error occured: #{e}")
        end

        # scan all files in provided folder
        def scan_folder_files(root_entry)
          Log.log().debug("scan: #{root_entry}")
          # dont use recursive call, use list instead
          items_to_process=[root_entry]
          while !items_to_process.empty?
            entry=items_to_process.shift
            Log.log.debug("item:#{entry}")
            case entry['type']
            when 'file'
              generate_preview(entry)
            when 'link'
              Log.log.info("Ignoring link.")
            when 'folder'
              if @skip_folders.include?(entry['path'])
                Log.log.info("#{entry['path']} folder (skip)".bg_red)
              else
                Log.log.info("#{entry['path']} folder")
                # get folder content
                folder_entries=@api_node.read("files/#{entry['id']}/files")[:data]
                # process all items in current folder
                folder_entries.each do |folder_entry|
                  # add path for older versions of ES
                  if !folder_entry.has_key?('path')
                    folder_entry['path']=(entry['path'].eql?('/')?'':entry['path'])+'/'+folder_entry['name']
                  end
                  folder_entry['parent_file_id']=entry['id']
                  items_to_process.push(folder_entry)
                end
              end
            else
              Log.log.warn("unknown entry type: #{entry['type']}")
            end
          end
        end

        def execute_action
          # TODO: lock based on TCP to avoid running multiple instances
          @api_node=basic_auth_api
          @transfer_address=URI.parse(@api_node.base_url).host
          @access_key_self = @api_node.read('access_keys/self')[:data] # same as with accesskey instead of /self
          @is_local=Main.tool.options.get_option(:file_access,:mandatory).eql?(:file_system)
          Log.log.debug("access key info: #{@access_key_self}")
          #@api_node.read('files/1')[:data]
          # either allow setting parameter, or get from aspera.conf
          @option_preview_folder='previews'
          @skip_folders=['/'+@option_preview_folder]
          if @is_local
            #TODO: option to override @local_storage_root='xxx'
            @local_storage_root=@access_key_self['storage']['path'].gsub(%r{^file:///},'')
            raise "ERROR: no such folder: #{@local_storage_root}" unless File.directory?(@local_storage_root)
            @local_preview_folder=File.join(@local_storage_root,@option_preview_folder)
            raise "ERROR: no such folder: #{@local_preview_folder}" unless File.directory?(@local_preview_folder)
          else
            # note the filter "name", it's why we take the first one
            @previews_entry=@api_node.read("files/#{@access_key_self['root_file_id']}/files",{:name=>@option_preview_folder})[:data].first
            @basic_token="Basic #{Base64.strict_encode64("#{@access_key_self['id']}:#{Main.tool.options.get_option(:password,:mandatory)}")}"
          end
          command=Main.tool.options.get_next_argument('command',action_list)
          case command
          when :scan
            scan_folder_files({ 'id' => @access_key_self['root_file_id'], 'name' => '/', 'type' => 'folder', 'path' => '/' })
            return Main.status_result('scan finished')
          when :events
            process_file_events
            return Main.status_result('events finished')
          when :folder
            file_id=Main.tool.options.get_next_argument('file id')
            file_info=@api_node.read("files/#{file_id}")[:data]
            scan_folder_files(file_info)
            return Main.status_result('file finished')
          end
        end # execute_action
      end # Preview
    end # Plugins
  end # Cli
end # Asperalm
