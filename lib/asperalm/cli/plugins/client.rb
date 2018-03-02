require 'asperalm/cli/main'
require 'asperalm/cli/plugins/node'
require 'asperalm/fasp/installation'
require 'asperalm/open_application'

module Asperalm
  module Cli
    module Plugins
      # list and download connect client versions
      class Client < Plugin
        CONNECT_WEB_URL = 'http://d3gcli72yxqn2z.cloudfront.net/connect'
        CONNECT_VERSIONS = 'connectversions.js'
        def declare_options; end

        def action_list; [ :installation, :monitor, :location, :connect ];end

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
          command=Main.tool.options.get_next_argument('command',action_list)
          case command
          when :location # shows files used
            return {:type=>:hash_array, :data=>Fasp::Installation.instance.paths.map {|k,v| {'name'=>k,'path'=>v[:path]}}}
          when :installation
            subcmd=Main.tool.options.get_next_argument('command',[:list])
            all=Fasp::Installation.instance.installed_products
            case subcmd
            when :list # shows files used
              return {:type=>:hash_array, :data=>all, :fields=>[:name,:app_root]}
            end
          when :monitor # todo
            raise "xx"
            return {:type=>:hash_array, :data=>Fasp::Installation.instance.installed_products}
          when :connect #
            command=Main.tool.options.get_next_argument('command',[:list,:id])
            case command
            when :list #
              return {:type=>:hash_array, :data=>self.class.connect_versions, :fields => ['id','title','version']}
            when :id #
              all_resources=self.class.connect_versions
              connect_id=Main.tool.options.get_next_argument('id or title')
              one_res = all_resources.select {|i| i['id'].eql?(connect_id) || i['title'].eql?(connect_id)}.first
              command=Main.tool.options.get_next_argument('command',[:info,:links])
              case command
              when :info # shows files used
                return {:type=>:key_val_list, :data=>one_res, :textify => lambda { |table_data| self.class.textify_list(table_data) }}
              when :links # shows files used
                command=Main.tool.options.get_next_argument('command',[:list,:id])
                all_links=one_res['links']
                case command
                when :list # shows files used
                  return {:type=>:hash_array, :data=>all_links}
                when :id #
                  link_title=Main.tool.options.get_next_argument('title')
                  one_link=all_links.select {|i| i['title'].eql?(link_title)}.first
                  command=Main.tool.options.get_next_argument('command',[:download,:open])
                  case command
                  when :download #
                    folder_dest=Main.tool.destination_folder('receive')
                    #folder_dest=Main.tool.options.get_next_argument('destination folder')
                    api_connect_cdn=Rest.new(CONNECT_WEB_URL)
                    fileurl = one_link['href']
                    filename=fileurl.gsub(%r{.*/},'')
                    api_connect_cdn.call({:operation=>'GET',:subpath=>fileurl,:save_to_file=>File.join(folder_dest,filename)})
                    return {:data=>"downloaded: #{filename}",:type => :status}
                  when :open #
                    OpenApplication.instance.uri(one_link['href'])
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
