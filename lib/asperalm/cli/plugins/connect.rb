require 'asperalm/cli/main'
require 'asperalm/cli/plugins/node'
require 'asperalm/Connect'

module Asperalm
  module Cli
    module Plugins
      class Connect < Plugin
        CONNECT_WEB_URL = 'http://d3gcli72yxqn2z.cloudfront.net/connect'
        CONNECT_VERSIONS = 'connectversions.js'
        def declare_options
        end

        def action_list; [ :status, :list, :id ];end

        def self.textify_list(table_data)
          return table_data.select {|i| ! i['key'].eql?('links') }
        end

        def self.get_data
          api_connect_cdn=Rest.new(CONNECT_WEB_URL)
          data=api_connect_cdn.call({:operation=>'GET',:subpath=>CONNECT_VERSIONS})
          data=data[:http].body
          data.gsub!(/[\r\n]\s*/,'')
          data.gsub!(/^.*AW.connectVersions = /,'')
          data.gsub!(/;$/,'')
          data=JSON.parse(data)
          data=data['entries']
          data
        end

        def execute_action
          command=Main.tool.options.get_next_arg_from_list('command',action_list)
          case command
          when :status # shows files used
            return {:type=>:hash_array, :data=>Asperalm::Connect.resource.map {|k,v| {'name'=>k,'path'=>v[:path]}}}
          when :list #
            return {:type=>:hash_array, :data=>self.class.get_data, :fields => ['id','title','version']}
          when :id #
            all_resources=self.class.get_data
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
                command=Main.tool.options.get_next_arg_from_list('command',[:download])
                folder_dest=Main.tool.options.get_next_arg_value('destination folder')
                one_link=all_links.select {|i| i['title'].eql?(link_title)}.first
                api_connect_cdn=Rest.new(CONNECT_WEB_URL)
                fileurl = one_link['href']
                filename=fileurl.dup
                filename.gsub!(%r{.*/},'')
                download_data=api_connect_cdn.call({:operation=>'GET',:subpath=>fileurl})
                open(File.join(folder_dest,filename), "wb") do |file|
                  file.write(download_data[:http].body)
                end
                return {:data=>"downloaded: #{filename}",:type => :status}
              end
            end
          else
            raise "ERROR, unknown command: [#{command}]"
          end
        end
      end
    end
  end # Cli
end # Asperalm
