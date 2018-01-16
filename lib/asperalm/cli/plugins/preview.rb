require 'asperalm/cli/main'
require 'asperalm/cli/basic_auth_plugin'
require 'asperalm/preview/generator'
require 'asperalm/preview/options'
require 'asperalm/fasp/agent'
require 'date'

# for older rubies
unless Hash.method_defined?(:dig)
  class Hash
    def dig(*path)
      path.inject(self) do |location, key|
        location.respond_to?(:keys) ? location[key] : nil
      end
    end
  end
end

module Asperalm
  module Cli
    module Plugins
      class Preview < BasicAuthPlugin

        attr_accessor :option_overwrite
        attr_accessor :option_previews_folder
        attr_accessor :option_iteration_file_filepath
        attr_accessor :option_folder_cache
        # main temp folder to download remote sources
        def main_temp_folder;"/tmp/aspera.previews";end

        # special tag to identify transfers related to generator
        PREV_GEN_TAG='preview_generator'
        PREVIEW_FOLDER_SUFFIX='.asp-preview'

        # values for option_overwrite
        def self.overwrite_policies; [:always,:never,:mtime];end

        def option_skip_types=(value)
          @skip_types=[]
          value.split(',').each do |v|
            s=v.to_sym
            raise "not supported: #{v}" unless Asperalm::Preview::Generator.conversion_types.include?(s)
            @skip_types.push(s)
          end
        end

        def option_skip_types()
          return @skip_types.map{|i|i.to_s}.join(',')
        end

        def initialize
          @option_iteration_file_filepath=nil
          @skip_types=[]
          @default_transfer_spec=nil
          # link CLI options to gen_info attributes
          Main.tool.options.set_option(:file_access,:local)
          Main.tool.options.set_obj_attr(:skip_types,self,:option_skip_types)
          Main.tool.options.set_obj_attr(:overwrite,self,:option_overwrite,:mtime)
          Main.tool.options.set_obj_attr(:previews_folder,self,:option_previews_folder,'previews')
          Main.tool.options.set_obj_attr(:iteration_file,self,:option_iteration_file_filepath,nil)
          Main.tool.options.set_obj_attr(:folder_cache,self,:option_folder_cache,:yes)
          Main.tool.options.set_obj_attr(:video,Asperalm::Preview::Options.instance,:vid_conv_method,:reencode)
          Main.tool.options.set_obj_attr(:vid_offset_seconds,Asperalm::Preview::Options.instance,:vid_offset_seconds,10)
          Main.tool.options.set_obj_attr(:vid_size,Asperalm::Preview::Options.instance,:vid_size,'320:-2')
          Main.tool.options.set_obj_attr(:vid_framecount,Asperalm::Preview::Options.instance,:vid_framecount,30)
          Main.tool.options.set_obj_attr(:vid_blendframes,Asperalm::Preview::Options.instance,:vid_blendframes,2)
          Main.tool.options.set_obj_attr(:vid_framepause,Asperalm::Preview::Options.instance,:vid_framepause,5)
          Main.tool.options.set_obj_attr(:vid_fps,Asperalm::Preview::Options.instance,:vid_fps,15)
          Main.tool.options.set_obj_attr(:vid_mp4_size_reencode,Asperalm::Preview::Options.instance,:vid_mp4_size_reencode,"-2:'min(ih,360)'")
          Main.tool.options.set_obj_attr(:clips_offset_seconds,Asperalm::Preview::Options.instance,:clips_offset_seconds,10)
          Main.tool.options.set_obj_attr(:clips_size,Asperalm::Preview::Options.instance,:clips_size,'320:-2')
          Main.tool.options.set_obj_attr(:clips_length,Asperalm::Preview::Options.instance,:clips_length,5)
          Main.tool.options.set_obj_attr(:clips_count,Asperalm::Preview::Options.instance,:clips_count,5)
          Main.tool.options.set_obj_attr(:thumb_mp4_size,Asperalm::Preview::Options.instance,:thumb_mp4_size,"-1:'min(ih,600)'")
          Main.tool.options.set_obj_attr(:thumb_img_size,Asperalm::Preview::Options.instance,:thumb_img_size,800)
          Main.tool.options.set_obj_attr(:thumb_offset_fraction,Asperalm::Preview::Options.instance,:thumb_offset_fraction,0.1)
          Main.tool.options.set_obj_attr(:validate_mime,Asperalm::Preview::Options.instance,:validate_mime,:no)
        end

        alias super_declare_options declare_options

        def declare_options
          super_declare_options
          Main.tool.options.add_opt_list(:file_access,[:local,:remote],"how to read and write files in repository")
          Main.tool.options.add_opt_simple(:skip_types,"LIST","skip types in comma separated list")
          Main.tool.options.add_opt_list(:overwrite,Preview.overwrite_policies,"when to generate preview file")
          Main.tool.options.add_opt_simple(:iteration_file,"PATH","path to iteration memory file")
          Main.tool.options.add_opt_list(:video,Asperalm::Preview::Options.vid_conv_methods,"method to generate video")
          Main.tool.options.add_opt_list(:validate_mime,[:no,:yes],"extra mime type validation")
          Main.tool.options.add_opt_list(:folder_cache,[:no,:yes],"use node api folder cache")
          Main.tool.options.add_opt_list(:validate_mime,[:no,:yes],"use magic number validation")
        end

        def action_list; [:scan,:events,:folder];end

        # /files/id/files is normally cached in redis, but we can discard the cache
        # but /files/id is not cached
        def get_folder_entries(file_id,request_args=nil)
          headers={'Accept'=>'application/json'}
          headers.merge!({'X-Aspera-Cache-Control'=>'no-cache'}) if @option_folder_cache.eql?(:no)
          return @api_node.call({:operation=>'GET',:subpath=>"files/#{file_id}/files",:headers=>headers,:url_params=>request_args})[:data]
          #return @api_node.read("files/#{file_id}/files",request_args)[:data]
        end

        # requests recent events on node api and process newly modified folders
        def process_file_events_old
          args={
            'access_key'=>@access_key_self['id'],
            'type'=>'download.ended'
          }
          # and optionally by iteration token
          begin
            events_filter['iteration_token']=File.read(@option_iteration_file_filepath) unless @option_iteration_file_filepath.nil?
          rescue
          end
          events=@api_node.read("events",args)[:data]
          return if events.empty?
          events.each do |event|
            next unless event['data']['direction'].eql?('receive')
            next unless event['data']['status'].eql?('completed')
            next unless event['data']['error_code'].eql?(0)
            next unless event.dig('data','tags','aspera',PREV_GEN_TAG).nil?
            #folder_id=event.dig('data','tags','aspera','node','file_id')
            folder_id=event.dig('data','file_id')
            next if folder_id.nil?
            folder_entry=@api_node.read("files/#{folder_id}")[:data] rescue nil
            next if folder_entry.nil?
            scan_folder_files(folder_entry)
          end
          # write next iteration value if needed/possible
          unless @option_iteration_file_filepath.nil? or events.last['id'].nil?
            File.write(@option_iteration_file_filepath,events.last['id'].to_s)
          end
        end

        def process_file_events
          # get new file creation by access key (TODO: what if file already existed?)
          events_filter={
            'access_key'=>@access_key_self['id'],
            'type'=>'file.created'
          }
          # and optionally by iteration token
          begin
            events_filter['iteration_token']=File.read(@option_iteration_file_filepath) unless @option_iteration_file_filepath.nil?
          rescue
          end
          events=@api_node.read("events",events_filter)[:data]
          return if events.empty?
          events.each do |event|
            # process only files
            next unless event.dig('data','type').eql?('file')
            file_entry=@api_node.read("files/#{event['data']['id']}")[:data] rescue nil
            next if file_entry.nil?
            next if file_entry['path'].start_with?("/#{@option_preview_folder}/")
            file_entry['parent_file_id']=event['data']['parent_file_id']
            generate_preview(file_entry)
          end
          # write new iteration file
          last_processed_iteration=events.last['id']
          Log.log.debug("write #{@option_iteration_file_filepath} - #{last_processed_iteration} (previous: #{events_filter['iteration_token']})")
          File.write(@option_iteration_file_filepath,last_processed_iteration.to_s) unless @option_iteration_file_filepath.nil? or last_processed_iteration.nil?
        end

        def do_transfer(direction,folder_id,source_filename,destination=nil)
          if @default_transfer_spec.nil?
            # make a dummy call to get some default transfer parameters
            res=@api_node.create("files/upload_setup",{"transfer_requests"=>[{"transfer_request"=>{"paths"=>[{}],"destination_root"=>"/"}}]})
            sample_transfer_spec=res[:data]["transfer_specs"].first["transfer_spec"]
            # add remote_user ?
            @default_transfer_spec=['ssh_port','fasp_port'].inject({}){|h,e|h[e]=sample_transfer_spec[e];h}
            @default_transfer_spec.merge!({
              'token'            => "Basic #{Base64.strict_encode64("#{@access_key_self['id']}:#{Main.tool.options.get_option(:password,:mandatory)}")}",
              'authentication'   => 'token', # connect client: do not ask password
              'remote_host'      => @transfer_server_address,
              'remote_user'      => Fasp::ACCESS_KEY_TRANSFER_USER,
              'EX_quiet'         => true,
            })
          end
          tspec=@default_transfer_spec.merge({
            'direction'        => direction,
            'paths'            => [{'source'=>source_filename}],
            'tags'             => { 'aspera' => {
            PREV_GEN_TAG         => true,
            'node'               => { 'access_key' => @access_key_self['id'], 'file_id' => folder_id },
            'xfer_id'            => SecureRandom.uuid,
            'xfer_retry'         => 3600 } }
          })
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
          # defined by node api
          entry_preview_folder_name="#{entry['id']}#{PREVIEW_FOLDER_SUFFIX}"
          # prepare preview file list and collect current state
          gen_infos=Asperalm::Preview::Generator.generators(original_extension,entry['content_type']).inject([]) do |a,g|
            a.push({
              :generator => g,
              :preview_exist => nil,
              :preview_newer_than_original => nil
            })
            a # give back memory for inject
          end
          # lets gather some infos on possibly existing previews, it depends if files access locally or remotely
          if @access_remote
            # folder where this entry is downloaded
            remote_entry_temp_local_folder=main_temp_folder
            # store source directly here
            local_original_filepath=File.join(remote_entry_temp_local_folder,entry['name'])
            original_mtime=DateTime.parse(entry['modified_time'])
            # where previews are generated
            local_entry_preview_dir=File.join(remote_entry_temp_local_folder,entry_preview_folder_name)
            need_create_local_folder=true # this will be temp folder
            #TODO: this does not work because previews is hidden
            #this_preview_folder_entries=get_folder_entries(@previews_folder_entry['id'],{:name=>entry_preview_folder_name})
            gen_infos.each do |gen_info|
              gen_info[:generator].source=local_original_filepath
              gen_info[:generator].destination=File.join(local_entry_preview_dir, 'preview.'+gen_info[:generator].preview_format)
              gen_info[:preview_exist]=false # TODO: use this_preview_folder_entries (but it's hidden)
              gen_info[:preview_newer_than_original] = false # TODO: get change time and compare, useful ?
            end
          else # direct local file system access
            local_original_filepath=File.join(@local_storage_root,entry['path'])
            original_mtime=File.mtime(local_original_filepath)
            local_entry_preview_dir = File.join(@local_preview_folder, entry_preview_folder_name)
            need_create_local_folder=!File.directory?(local_entry_preview_dir)
            gen_infos.each do |gen_info|
              gen_info[:generator].source=local_original_filepath
              gen_info[:generator].destination=File.join(local_entry_preview_dir, 'preview.'+gen_info[:generator].preview_format)
              gen_info[:preview_exist]=File.exist?(gen_info[:generator].destination)
              gen_info[:preview_newer_than_original] = (gen_info[:preview_exist] and (File.mtime(gen_info[:generator].destination)>original_mtime))
            end
          end
          # here we have the status on preview files, let's find if they need generation
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
            # get conversion_type (if known) and check if supported
            next false unless gen_info[:generator].supported?
            # shall we skip it ?
            next false if @skip_types.include?(gen_info[:generator].conversion_type)
            # ok we need to generate
            true
          end
          return if gen_infos.empty?
          FileUtils.mkdir_p(local_entry_preview_dir) if need_create_local_folder
          if @access_remote
            raise "parent not computed" if entry['parent_file_id'].nil?
            #  download original file to temp folder remote_entry_temp_local_folder
            do_transfer('receive',entry['parent_file_id'],entry['name'],remote_entry_temp_local_folder)
          end
          gen_infos.each do |gen_info|
            begin
              gen_info[:generator].generate
            rescue => e
              Log.log.error("exception: #{e.message}:\n#{e.backtrace.join("\n")}".red)
              raise e
            end
          end
          if @access_remote
            # upload
            do_transfer('send',@previews_folder_entry['id'],local_entry_preview_dir)
            # delete remote_entry_temp_local_folder and below
            FileUtils.rm_rf(remote_entry_temp_local_folder)
          end
#        rescue => e
#          Log.log.error("exception: #{e.message}:\n#{e.backtrace.join("\n")}".red)
        end # generate_preview

        # scan all files in provided folder entry
        def scan_folder_files(top_entry)
          Log.log().debug("scan: #{top_entry}")
          # dont use recursive call, use list instead
          items_to_process=[top_entry]
          while !items_to_process.empty?
            entry=items_to_process.shift
            Log.log.debug("item:#{entry}")
            case entry['type']
            when 'file'
              generate_preview(entry)
            when 'link'
              Log.log.debug("Ignoring link.")
            when 'folder'
              if @skip_folders.include?(entry['path'])
                Log.log.debug("#{entry['path']} folder (skip)".bg_red)
              else
                Log.log.debug("#{entry['path']} folder")
                # get folder content
                folder_entries=get_folder_entries(entry['id'])
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
          @api_node=basic_auth_api
          @transfer_server_address=URI.parse(@api_node.base_url).host
          @access_key_self = @api_node.read('access_keys/self')[:data] # same as with accesskey instead of /self
          @access_remote=Main.tool.options.get_option(:file_access,:mandatory).eql?(:remote)
          Log.log.debug("access key info: #{@access_key_self}")
          #TODO: either allow setting parameter, or get from aspera.conf
          @option_preview_folder='previews'
          @skip_folders=['/'+@option_preview_folder]
          if @access_remote
            # note the filter "name", it's why we take the first one
            @previews_folder_entry=get_folder_entries(@access_key_self['root_file_id'],{:name=>@option_preview_folder}).first
            raise "ERROR: no such folder: #{@option_preview_folder}" if @previews_folder_entry.nil?
          else
            #TODO: option to override @local_storage_root='xxx'
            @local_storage_root=@access_key_self['storage']['path'].gsub(%r{^file:///},'')
            raise "ERROR: no such folder: #{@local_storage_root}" unless File.directory?(@local_storage_root)
            @local_preview_folder=File.join(@local_storage_root,@option_preview_folder)
            raise "ERROR: no such folder: #{@local_preview_folder}" unless File.directory?(@local_preview_folder)
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
