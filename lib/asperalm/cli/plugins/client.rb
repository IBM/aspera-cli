require 'asperalm/cli/main'
require 'asperalm/cli/plugins/node'
require 'asperalm/fasp_folders'
require 'asperalm/operating_system'

module Asperalm
  module Cli
    module Plugins
      # list and download connect client versions
      class Client < Plugin
        CONNECT_WEB_URL = 'http://d3gcli72yxqn2z.cloudfront.net/connect'
        CONNECT_VERSIONS = 'connectversions.js'
        def declare_options; end

        def action_list; [ :location, :connect ];end

        def self.textify_list(table_data)
          return table_data.select {|i| ! i['key'].eql?('links') }
        end

        # retrieve structure with all versions available
        def self.connect_versions
          api_connect_cdn=Rest.new(CONNECT_WEB_URL)
          javascript=api_connect_cdn.call({:operation=>'GET',:subpath=>CONNECT_VERSIONS})
          jsondata=javascript[:http].body.gsub(/\r\n\s*/,'').gsub(/^.*AW.connectVersions = /,'').gsub(/;$/,'')
          alldata=JSON.parse(jsondata)
          return alldata['entries']
        end

        def execute_action
          command=Main.tool.options.get_next_arg_from_list('command',action_list)
          case command
          when :location # shows files used
            return {:type=>:hash_array, :data=>Asperalm::FaspFolders.resource.map {|k,v| {'name'=>k,'path'=>v[:path]}}}
          when :connect #
            command=Main.tool.options.get_next_arg_from_list('command',[:list,:id])
            case command
            when :list #
              return {:type=>:hash_array, :data=>self.class.connect_versions, :fields => ['id','title','version']}
            when :id #
              all_resources=self.class.connect_versions
              connect_id=Main.tool.options.get_next_arg_value('id or title')
              one_res = all_resources.select {|i| i['id'].eql?(connect_id) || i['title'].eql?(connect_id)}.first
              command=Main.tool.options.get_next_arg_from_list('command',[:info,:links])
              case command
              when :info # shows files used
                return {:type=>:key_val_list, :data=>one_res, :textify => lambda { |table_data| self.class.textify_list(table_data) }}
              when :links # shows files used
                command=Main.tool.options.get_next_arg_from_list('command',[:list,:id])
                all_links=one_res['links']
                case command
                when :list # shows files used
                  return {:type=>:hash_array, :data=>all_links}
                when :id #
                  link_title=Main.tool.options.get_next_arg_value('title')
                  one_link=all_links.select {|i| i['title'].eql?(link_title)}.first
                  command=Main.tool.options.get_next_arg_from_list('command',[:download,:open])
                  case command
                  when :download #
                    folder_dest=Main.tool.options.get_next_arg_value('destination folder')
                    api_connect_cdn=Rest.new(CONNECT_WEB_URL)
                    fileurl = one_link['href']
                    filename=fileurl.gsub(%r{.*/},'')
                    download_data=api_connect_cdn.call({:operation=>'GET',:subpath=>fileurl,:save_to_file=>File.join(folder_dest,filename)})
                    return {:data=>"downloaded: #{filename}",:type => :status}
                  when :open #
                    OperatingSystem.open_uri(one_link['href'])
                    return {:data=>"opened: #{one_link['href']}",:type => :status}
                  end
                end
              end
            end
          end
        end
      end
    end
  end # Cli
end # Asperalm
