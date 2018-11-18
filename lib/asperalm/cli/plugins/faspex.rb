require 'asperalm/cli/basic_auth_plugin'
require 'asperalm/cli/plugins/node'
require 'asperalm/cli/plugins/config'
require 'asperalm/cli/extended_value'
require 'asperalm/cli/transfer_agent'
require 'asperalm/persistency_file'
require 'asperalm/open_application'
require 'asperalm/fasp/uri'
require 'xmlsimple'
require 'singleton'

module Asperalm
  module Cli
    module Plugins
      class Faspex < BasicAuthPlugin
        include Singleton
        @@KEY_NODE='node'
        @@KEY_PATH='path'
        @@VAL_ALL='ALL'
        alias super_declare_options declare_options
        def declare_options
          super_declare_options
          Main.instance.options.add_opt_simple(:delivery_info,"package delivery information (extended value)")
          Main.instance.options.add_opt_simple(:source_name,"create package from remote source (by name)")
          Main.instance.options.add_opt_simple(:storage,"Faspex local storage definition")
          Main.instance.options.add_opt_list(:box,[:inbox,:sent,:archive],"package box")
          Main.instance.options.add_opt_boolean(:once_only,"keep track of already downloaded packages")
          Main.instance.options.set_option(:box,:inbox)
          Main.instance.options.set_option(:once_only,:false)
        end

        # extract elements from anonymous faspex link
        def self.get_link_data(email)
          package_match = email.match(/((http[^"]+)\/(external_deliveries\/([^?]+)))\?passcode=([^"]+)/)
          if package_match.nil? then
            raise CliBadArgument, "string does not match Faspex url"
          end
          return {
            :uri => package_match[0],
            :url => package_match[1],
            :faspex_base_url =>  package_match[2],
            :subpath => package_match[3],
            :delivery_id => package_match[4],
            :passcode => package_match[5]
          }
        end

        # get faspe: URI from entry in xml, and fix problems..
        def self.get_fasp_uri_from_entry(entry)
          raise CliBadArgument, "package is empty" if !entry.has_key?('link')
          result=entry['link'].select{|e| e["rel"].eql?("package")}.first["href"]
          # tags in the end of URL is not well % encoded... there are "=" that should be %3D
          # TODO: enter ticket to Faspex ?
          if m=result.match(/(=+)$/);result.gsub!(/=+$/,"#{"%3D"*m[1].length}");end
          return result
        end

        def self.textify_package_list(table_data)
          return table_data.map { |e|
            e.keys.each {|k| e[k]=e[k].first if e[k].is_a?(Array) and e[k].length == 1}
            e['items'] = e.has_key?('link') ? e['link'].length : 0
            e
          }
        end

        # field_sym : :id or :name
        def self.get_source_id(source_list,source_name)
          source_ids=source_list.select { |i| i['name'].eql?(source_name) }
          if source_ids.empty?
            raise CliError,"No such Faspex source #{field_sym.to_s}: #{field_value} in [#{source_list.map{|i| i[field_sym.to_s]}.join(', ')}]"
          end
          return source_ids.first['id']
        end

        def api_v3
          if @api_v3.nil?
            @api_v3=basic_auth_api
          end
          return @api_v3
        end

        def api_v4
          if @api_v4.nil?
            faspex_api_base=Main.instance.options.get_option(:url,:mandatory)
            @api_v4=Rest.new({
              :base_url             => faspex_api_base+'/api',
              :auth_type            => :oauth2,
              :oauth_base_url       => faspex_api_base+'/auth/oauth2',
              :oauth_type           => :header_userpass,
              :oauth_user_name      => Main.instance.options.get_option(:username,:mandatory),
              :oauth_user_pass      => Main.instance.options.get_option(:password,:mandatory),
              :oauth_scope          => 'admin'
            })
          end
          return @api_v4
        end

        def action_list; [ :package, :source, :me, :dropbox, :recv_publink, :v4, :address_book ];end

        # we match recv command on atom feed on this field
        PACKAGE_MATCH_FIELD='package_id'

        def mailbox_all_entries
          mailbox=Main.instance.options.get_option(:box,:mandatory).to_s
          all_inbox_xml=api_v3.call({:operation=>'GET',:subpath=>"#{mailbox}.atom",:headers=>{'Accept'=>'application/xml'}})[:http].body
          all_inbox_data=XmlSimple.xml_in(all_inbox_xml, {"ForceArray" => true})
          Log.dump(:all_inbox_data,all_inbox_data)
          result=all_inbox_data.has_key?('entry') ? all_inbox_data['entry'] : []
          result.each do |e|
            e[PACKAGE_MATCH_FIELD]=e['to'].first['recipient_delivery_id'].first
          end
          return result
        end

        def execute_action
          command=Main.instance.options.get_next_command(action_list)
          case command
          when :package
            command_pkg=Main.instance.options.get_next_command([ :send, :recv, :list ])
            case command_pkg
            when :list
              return {:type=>:object_list,:data=>self.mailbox_all_entries,:fields=>[PACKAGE_MATCH_FIELD,'title','items'], :textify => lambda { |table_data| Faspex.textify_package_list(table_data)} }
            when :recv
              # get command line parameters
              delivid=Main.instance.options.get_option(:id,:mandatory)
              mailbox=Main.instance.options.get_option(:box,:mandatory).to_s
              once_only=Main.instance.options.get_option(:once_only,:mandatory)
              # list of faspex URI to download
              uris_to_download=nil
              skip_ids=[]
              ids_to_download=[]
              case delivid
              when @@VAL_ALL
                if once_only
                  persistency_file=PersistencyFile.new('faspex_recv',Cli::Plugins::Config.instance.config_folder)
                  persistency_file.set_unique(
                  nil,
                  [Main.instance.options.get_option(:username,:mandatory),Main.instance.options.get_option(:box,:mandatory).to_s],
                  Main.instance.options.get_option(:url,:mandatory))
                  data=persistency_file.read_from_file
                  unless data.nil?
                    skip_ids=JSON.parse(data)
                  end
                end
                # todo
                uris_to_download=self.mailbox_all_entries.select{|e| !skip_ids.include?(e[PACKAGE_MATCH_FIELD])}.map{|e|ids_to_download.push(e[PACKAGE_MATCH_FIELD]);self.class.get_fasp_uri_from_entry(e)}
              else
                # I dont know which delivery id is the right one if package was receive by group
                entry_xml=api_v3.call({:operation=>'GET',:subpath=>"#{mailbox}/#{delivid}",:headers=>{'Accept'=>'application/xml'}})[:http].body
                package_entry=XmlSimple.xml_in(entry_xml, {"ForceArray" => true})
                transfer_uri=self.class.get_fasp_uri_from_entry(package_entry)
                uris_to_download=[transfer_uri]
              end
              Log.dump(:uris_to_download,uris_to_download)
              return Main.result_status('no package') if uris_to_download.empty?
              result_transfer=[]
              uris_to_download.each do |transfer_uri|
                this_id=ids_to_download.shift
                transfer_spec=Fasp::Uri.new(transfer_uri).transfer_spec
                # NOTE: only external users have token in faspe: link !
                if !transfer_spec.has_key?('token')
                  sanitized=transfer_uri.gsub('&','&amp;')
                  xmlpayload='<?xml version="1.0" encoding="UTF-8"?><url-list xmlns="http://schemas.asperasoft.com/xml/url-list"><url href="'+sanitized+'"/></url-list>'
                  transfer_spec['token']=api_v3.call({:operation=>'POST',:subpath=>"issue-token?direction=down",:headers=>{'Accept'=>'text/plain','Content-Type'=>'application/vnd.aspera.url-list+xml'},:text_body_params=>xmlpayload})[:http].body
                end
                transfer_spec['direction']='receive'
                statuses=TransferAgent.instance.start(transfer_spec,{:src=>:node_gen3})
                result_transfer.push({'package'=>this_id,'status'=>statuses.map{|i|i.to_s}.join(',')})
                # skip only if all sessions completed
                skip_ids.push(this_id) if TransferAgent.all_session_success(statuses)
              end
              if once_only and !skip_ids.empty?
                persistency_file.write_to_file(JSON.generate(skip_ids))
              end
              return {:type=>:object_list,:data=>result_transfer}
            when :send
              delivery_info=Main.instance.options.get_option(:delivery_info,:mandatory)
              raise CliBadArgument,"delivery_info must be hash, refer to doc" unless delivery_info.is_a?(Hash)
              delivery_info['sources']||=[{'paths'=>[]}]
              first_source=delivery_info['sources'].first
              first_source['paths'].push(*Main.instance.ts_source_paths.map{|i|i['source']})
              source_name=Main.instance.options.get_option(:source_name,:optional)
              if !source_name.nil?
                source_list=api_v3.call({:operation=>'GET',:subpath=>"source_shares",:headers=>{'Accept'=>'application/json'}})[:data]['items']
                source_id=self.class.get_source_id(source_list,source_name)
                first_source['id']=source_id
              end
              package_create_params={'delivery'=>delivery_info}
              send_result=api_v3.call({:operation=>'POST',:subpath=>'send',:json_params=>package_create_params,:headers=>{'Accept'=>'application/json'}})[:data]
              if send_result.has_key?('error')
                raise CliBadArgument,"#{send_result['error']['user_message']}: #{send_result['error']['internal_message']}"
              end
              if !source_name.nil?
                # no transfer spec if remote source
                return {:data=>[send_result['links']['status']],:type=>:value_list,:name=>'link'}
              end
              raise CliBadArgument,"expecting one session exactly" if send_result['xfer_sessions'].length != 1
              transfer_spec=send_result['xfer_sessions'].first
              # use source from cmd line, this one nly contains destination (already in dest root)
              transfer_spec.delete('paths')
              return Main.result_transfer(transfer_spec,{:src=>:node_gen3})
            end
          when :source
            command_source=Main.instance.options.get_next_command([ :list, :id, :name ])
            source_list=api_v3.call({:operation=>'GET',:subpath=>"source_shares",:headers=>{'Accept'=>'application/json'}})[:data]['items']
            case command_source
            when :list
              return {:type=>:object_list,:data=>source_list}
            else # :id or :name
              source_match_val=Main.instance.options.get_next_argument('source id or name')
              source_ids=source_list.select { |i| i[command_source.to_s].to_s.eql?(source_match_val) }
              if source_ids.empty?
                raise CliError,"No such Faspex source #{command_source.to_s}: #{source_match_val} in [#{source_list.map{|i| i[command_source.to_s]}.join(', ')}]"
              end
              # get id and name
              source_name=source_ids.first['name']
              source_id=source_ids.first['id']
              source_hash=Main.instance.options.get_option(:storage,:mandatory)
              # check value of option
              raise CliError,"storage option must be a Hash" unless source_hash.is_a?(Hash)
              source_hash.each do |name,storage|
                raise CliError,"storage '#{name}' must be a Hash" unless storage.is_a?(Hash)
                [@@KEY_NODE,@@KEY_PATH].each do |key|
                  raise CliError,"storage '#{name}' must have a '#{key}'" unless storage.has_key?(key)
                end
              end
              if !source_hash.has_key?(source_name)
                raise CliError,"No such storage in config file: \"#{source_name}\" in [#{source_hash.keys.join(', ')}]"
              end
              source_info=source_hash[source_name]
              Log.log.debug("source_info: #{source_info}")
              command_node=Main.instance.options.get_next_command([ :info, :node ])
              case command_node
              when :info
                return {:data=>source_info,:type=>:single_object}
              when :node
                node_config=ExtendedValue.parse(:node,source_info[@@KEY_NODE])
                raise CliError,"bad type for: \"#{source_info[@@KEY_NODE]}\"" unless node_config.is_a?(Hash)
                Log.log.debug("node=#{node_config}")
                api_node=Rest.new({
                  :base_url      => node_config['url'],
                  :auth_type     =>:basic,
                  :basic_username=>node_config['username'],
                  :basic_password=>node_config['password']})
                command=Main.instance.options.get_next_command(Node.common_actions)
                return Node.execute_common(command,api_node,source_info[@@KEY_PATH])
              end
            end
          when :me
            my_info=api_v3.call({:operation=>'GET',:subpath=>"me",:headers=>{'Accept'=>'application/json'}})[:data]
            return {:data=>my_info, :type=>:single_object}
          when :dropbox
            command_pkg=Main.instance.options.get_next_command([ :list, :create ])
            case command_pkg
            when :list
              dropbox_list=api_v3.call({:operation=>'GET',:subpath=>"/aspera/faspex/dropboxes",:headers=>{'Accept'=>'application/json'}})[:data]
              return {:type=>:object_list, :data=>dropbox_list['items'], :fields=>['name','id','description','can_read','can_write']}
              #              when :create
              #
            end
          when :recv_publink
            thelink=Main.instance.options.get_next_argument("Faspex public URL for a package")
            link_data=self.class.get_link_data(thelink)
            # Note: unauthenticated API
            api_public_link=Rest.new({:base_url=>link_data[:faspex_base_url]})
            pkgdatares=api_public_link.call({:operation=>'GET',:subpath=>link_data[:subpath],:url_params=>{:passcode=>link_data[:passcode]},:headers=>{'Accept'=>'application/xml'}})
            if !pkgdatares[:http].body.start_with?('<?xml ')
              OpenApplication.instance.uri(thelink)
              raise CliError, "no such package"
            end
            package_entry=XmlSimple.xml_in(pkgdatares[:http].body, {"ForceArray" => false})
            transfer_uri=self.class.get_fasp_uri_from_entry(package_entry)
            transfer_spec=Fasp::Uri.new(transfer_uri).transfer_spec
            transfer_spec['direction']='receive'
            return Main.result_transfer(transfer_spec,{:src=>:node_gen3})
          when :v4
            command=Main.instance.options.get_next_command([:dropbox, :dmembership, :workgroup,:wmembership,:user,:metadata_profile])
            case command
            when :dropbox
              return Plugin.entity_action(api_v4,'admin/dropboxes',['id','e_wg_name','e_wg_desc','created_at'],:id)
            when :dmembership
              return Plugin.entity_action(api_v4,'dropbox_memberships',nil,:id)
            when :workgroup
              return Plugin.entity_action(api_v4,'admin/workgroups',['id','e_wg_name','e_wg_desc','created_at'],:id)
            when :wmembership
              return Plugin.entity_action(api_v4,'workgroup_memberships',nil,:id)
            when :user
              return Plugin.entity_action(api_v4,'users',['id','name','first_name','last_name'],:id)
            when :metadata_profile
              return Plugin.entity_action(api_v4,'metadata_profiles',nil,:id)
            end
          when :address_book
            result=api_v3.call({:operation=>'GET',:subpath=>"address-book",:headers=>{'Accept'=>'application/json'},:url_params=>{'format'=>'json','count'=>100000}})[:data]
            Main.instance.display_status("users: #{result['itemsPerPage']}/#{result['totalResults']}, start:#{result['startIndex']}")
            users=result['entry']
            # add missing entries
            users.each do |u|
              unless u['emails'].nil?
                email=u['emails'].find{|e|e['primary'].eql?('true')}
                u['email'] = email['value'] unless email.nil?
              end
              if u['email'].nil?
                Log.log.warn("Skip user without email: #{u}")
                next
              end
              u['first_name'],u['last_name'] = u['displayName'].split(' ',2)
              u['x']=true
            end
            return {:type=>:object_list,:data=>users}
          end # command
        end
      end
    end
  end # Cli
end # Asperalm
