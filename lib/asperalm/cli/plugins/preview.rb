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
          Main.tool.options.set_obj_attr(:overwrite,self,:option_overwrite,:mtime)
          Main.tool.options.set_obj_attr(:skip_types,self,:option_skip_types)
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
          Main.tool.options.set_option(:file_access,:file_system)
          Main.tool.options.add_opt_list(:file_access,[:file_system,:fasp],"how to read and write files in repository")
          Main.tool.options.add_opt_list(:overwrite,Preview.overwrite_policies,"when to generate preview file")
          Main.tool.options.add_opt_list(:video,PreviewGenerator.video_styles,"method to generate video")
          Main.tool.options.add_opt_simple(:skip_types,"LIST","skip types in comma separated list")
        end

        def action_list; [:scan,:events,:id];end

        #requests recent events on node api and process newly created files
        def process_file_events
          iteration=nil
          args={'access_key'=>@access_key_self['id']}
          args['iteration_token']=iteration unless iteration.nil?
          #args['count']=10
          events=@api_node.read("events",args)[:data]
          new_iteration_token=nil
          temp_file_ids=[]
          process_file_ids=[]
          # this will be new iteration token
          latest_upload_id=nil
          events.each do |event|
            event['types'].each do |type|
              case type
              when 'file.created'
                # was created, but maybe upload not finished
                file_id=event.dig('data','id')
                temp_file_ids.push(file_id) unless file_id.nil? or temp_file_ids.include?(file_id)
              when 'download.ended'
                if event['data']['status'].eql?('completed') and
                event['data']['error_code'].eql?(0) and
                event.dig('data','tags','aspera','  ').nil?
                  #upload_folder=event.dig('data','tags','aspera','node','file_id')
                  #upload_folder=event.dig('data','file_id')
                  # validate created files
                  process_file_ids.concat(temp_file_ids)
                  temp_file_ids=[]
                  latest_upload_id=event['id']
                end
              end
            end
          end
          process_file_ids.each do |file_id|
            file_info=@api_node.read("files/#{file_id}")[:data] rescue nil
            generate_preview(file_info) unless file_info.nil?
          end
        end

        def scan_root_folder_files
          scan_folder_files({ 'id' => @access_key_self['root_file_id'], 'name' => '/', 'type' => 'folder', 'path' => '/' })
        end

        # direction: send / receive
        def do_transfer(direction,file_id,source_path_name,destination=nil)
          #send_result=api_node.call({:operation=>'POST',:subpath=>'files/download_setup',:json_params=>{ :transfer_requests => [ { :transfer_request => { :paths => filelist.map {|i| {:source=>i}; } } } ] }})
          # todo: create token based on acces key ?
          #raise CliError,"not implemented"
          tspec={
            'direction'        => direction,
            'paths'            => [{'source'=>source_path_name}],
            'remote_user'      => 'xfer',
            'remote_host'      => @transfer_address,
            'EX_ssh_key_paths' => [ Fasp::ResourceFinder.path(:ssh_bypass_key_dsa)],
            "fasp_port"        => 33001, # TODO: always the case ?
            "ssh_port"         => 22,#33001, # TODO: always the case ?
            'token'            => @basic_token,
            'tags'             => { "aspera" => {
            "preview_generator"=>'ok',
            #"files"            => {},
            "node"             => { "access_key" => @access_key_self['id'], "file_id" => file_id },
            "xfer_id"          => SecureRandom.uuid,
            "xfer_retry"       => 3600 } } }
          tspec['destination_root']='/' if direction.eql?("send")
          tspec['destination_root']=destination unless destination.nil?
          Fasp::Agent.add_aspera_keys(tspec)
          Fasp::Manager.instance.start_transfer(tspec)
        end

        # generate preview files for one folder entry (file) if necessary
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
              #TODO: transfer original file to folder main_temp_folder
              do_transfer('receive',entry['id'],entry['name'],main_temp_folder)
            end
            to_generate.each do |info|
              begin
                PreviewGenerator.instance.generate(info[:method],local_original_filepath,info[:dest])
              rescue => e
                Log.log.error("exception: #{e.message}:\n#{e.backtrace.join("\n")}".red)
              end
            end
            if !@is_local
              # TODO: upload
              do_transfer('send',"main_preview_folder_id",local_entry_preview_dir)
              #TODO: delete main_temp_folder and below
              FileUtils.rm_rf(main_temp_folder)
            end
          end
        end

        # scan all files in provided folder
        def scan_folder_files(root_entry)
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
            raise "ERROR: #{@local_storage_root}" unless File.directory?(@local_storage_root)
            @local_preview_folder=File.join(@local_storage_root,@option_preview_folder)
            raise "ERROR: #{@local_preview_folder}" unless File.directory?(@local_preview_folder)
          else
            @previews_entry=@api_node.read("files/#{@access_key_self['root_file_id']}/files",{:name=>@option_preview_folder})[:data].first
            @basic_token="Basic #{Base64.strict_encode64("#{@access_key_self['id']}:#{Main.tool.options.get_option(:password,:mandatory)}")}"
          end
          command=Main.tool.options.get_next_argument('command',action_list)
          case command
          when :scan
            scan_root_folder_files
            return Main.status_result('scan finished')
          when :events
            process_file_events
            return Main.status_result('events finished')
          when :id
            file_id=Main.tool.options.get_next_argument('file id')
            file_info=@api_node.read("files/#{file_id}")[:data]
            generate_preview(file_info)
            return Main.status_result('file finished')
          end
        end # execute_action
      end # Preview
    end # Plugins
  end # Cli
end # Asperalm
