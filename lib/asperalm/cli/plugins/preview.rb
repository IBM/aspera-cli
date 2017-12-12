require 'asperalm/cli/main'
require 'asperalm/cli/basic_auth_plugin'
require 'asperalm/preview_generator'

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
        def initialize
          Main.tool.options.set_obj_attr(:overwrite,PreviewGenerator.instance,:option_overwrite)
          Main.tool.options.set_obj_attr(:video,PreviewGenerator.instance,:option_video_style)
        end

        alias super_declare_options declare_options

        def declare_options
          super_declare_options
          Main.tool.options.set_option(:file_access,:file_system)
          Main.tool.options.set_option(:overwrite,:always)
          Main.tool.options.add_opt_list(:file_access,'VALUE',[:file_system,:fasp],"how to read and write files in repository")
          Main.tool.options.add_opt_list(:overwrite,'VALUE',PreviewGenerator.overwrite_policies,"when to generate preview file")
          Main.tool.options.add_opt_list(:video,'VALUE',PreviewGenerator.video_styles,"method to generate video")
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
                event.dig('data','tags','aspera','preview_generator').nil?
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

        # generate preview for one folder entry (file)
        def generate_preview(entry)
          case Main.tool.options.get_option(:file_access,:mandatory)
          when :file_system
            # first time, compute values
            if @preview_folder_real.nil?
              #TODO: option to override @storage_root_real='xxx'
              @storage_root_real=@access_key_self['storage']['path']
              @storage_root_real.gsub!(%r{^file:///},'')
              @preview_folder_real=File.join(@storage_root_real,@option_preview_folder)
              raise "ERROR: #{@storage_root_real}" unless File.directory?(@storage_root_real)
              raise "ERROR: #{@preview_folder_real}" unless File.directory?(@preview_folder_real)
            end
            #puts "#{entry}".green
            #return
            # optimisation, work direct with files on filesystem
            PreviewGenerator.instance.preview_from_file(File.join(@storage_root_real,entry['path']), entry['id'], @preview_folder_real)
            #rescue => e
            #  Log.log.error("exception: #{e.message} -> #{e.backtrace}")
          else
            raise CliError,"only file_system access it currently supported"
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
          @access_key_self = @api_node.read('access_keys/self')[:data] # same as with accesskey instead of /self
          Log.log.debug("access key info: #{@access_key_self}")
          #@api_node.read('files/1')[:data]
          # either allow setting parameter, or get from aspera.conf
          @option_preview_folder='previews'
          @skip_folders=['/'+@option_preview_folder]
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
