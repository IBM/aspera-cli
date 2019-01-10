require 'asperalm/cli/plugins/node'
require 'asperalm/fasp/installation'
require 'asperalm/open_application'

module Asperalm
  module Cli
    module Plugins
      # list and download connect client versions, select FASP implementation
      class Client < Plugin
        CONNECT_WEB_URL = 'http://d3gcli72yxqn2z.cloudfront.net/connect'
        CONNECT_VERSIONS = 'connectversions.js'
        def self.textify_list(table_data)
          return table_data.select {|i| ! i['key'].eql?('links') }
        end

        def initialize(env)
          super(env)
          #self.options.parse_options!
        end

        # retrieve structure from cloud (CDN) with all versions available
        def connect_versions
          if @connect_versions.nil?
            api_connect_cdn=Rest.new({:base_url=>CONNECT_WEB_URL})
            javascript=api_connect_cdn.call({:operation=>'GET',:subpath=>CONNECT_VERSIONS})
            # get result on one line
            connect_versions_javascript=javascript[:http].body.gsub(/\r?\n\s*/,'')
            Log.log.debug("javascript=[\n#{connect_versions_javascript}\n]")
            # get javascript object only
            found=connect_versions_javascript.match(/AW.connectVersions = (.*);/)
            raise CliError,'Problen when getting connect versions from internet' if found.nil?
            alldata=JSON.parse(found[1])
            @connect_versions=alldata['entries']
          end
          return @connect_versions
        end

        def action_list; [ :current, :available, :connect ];end

        def execute_action
          command=self.options.get_next_command(action_list)
          case command
          when :current # shows files used
            return {:type=>:object_list, :data=>Fasp::Installation.instance.paths.map{|k,v|{'name'=>k,'path'=>v}}}
          when :available
            return {:type=>:object_list, :data=>Fasp::Installation.instance.installed_products, :fields=>['name','app_root']}
          when :connect
            command=self.options.get_next_command([:list,:id])
            case command
            when :list
              return {:type=>:object_list, :data=>connect_versions, :fields => ['id','title','version']}
            when :id
              connect_id=self.options.get_next_argument('id or title')
              one_res=connect_versions.select{|i|i['id'].eql?(connect_id) || i['title'].eql?(connect_id)}.first
              raise CliNoSuchId.new(:connect,connect_id) if one_res.nil?
              command=self.options.get_next_command([:info,:links])
              case command
              when :info # shows files used
                return {:type=>:single_object, :data=>one_res, :textify => lambda { |table_data| self.class.textify_list(table_data) }}
              when :links # shows files used
                command=self.options.get_next_command([:list,:id])
                all_links=one_res['links']
                case command
                when :list # shows files used
                  return {:type=>:object_list, :data=>all_links}
                when :id
                  link_title=self.options.get_next_argument('title')
                  one_link=all_links.select {|i| i['title'].eql?(link_title)}.first
                  command=self.options.get_next_command([:download,:open])
                  case command
                  when :download #
                    folder_dest=self.transfer.destination_folder('receive')
                    #folder_dest=self.options.get_next_argument('destination folder')
                    api_connect_cdn=Rest.new({:base_url=>CONNECT_WEB_URL})
                    fileurl = one_link['href']
                    filename=fileurl.gsub(%r{.*/},'')
                    api_connect_cdn.call({:operation=>'GET',:subpath=>fileurl,:save_to_file=>File.join(folder_dest,filename)})
                    return Main.result_status("downloaded: #{filename}")
                  when :open #
                    OpenApplication.instance.uri(one_link['href'])
                    return Main.result_status("opened: #{one_link['href']}")
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
