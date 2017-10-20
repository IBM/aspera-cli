require 'asperalm/cli/main'
require 'asperalm/cli/basic_auth_plugin'
require 'asperalm/cli/plugins/node'
require 'asperalm/operating_system'
require 'asperalm/fasp/uri'
require 'xmlsimple'

module Asperalm
  module Cli
    module Plugins
      class Faspex < BasicAuthPlugin
        @@KEY_NODE='node'
        @@KEY_PATH='path'
        alias super_declare_options declare_options
        def declare_options
          super_declare_options
          Main.tool.options.set_option(:box,:inbox)
          Main.tool.options.add_opt_simple(:recipient,"STRING","package recipient")
          Main.tool.options.add_opt_simple(:title,"STRING","package title")
          Main.tool.options.add_opt_simple(:note,"STRING","package note")
          Main.tool.options.add_opt_simple(:metadata,"@json:JSON_STRING","package metadata (hash, use @json:)")
          Main.tool.options.add_opt_simple(:source_name,"STRING","create package from remote source (by name)")
          Main.tool.options.add_opt_list(:box,'TYPE',[:inbox,:sent,:archive],"package box")
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

        def get_faspex_authenticated_api
          return Rest.new(Main.tool.options.get_option_mandatory(:url),{:auth=>{:type=>:basic,:username=>Main.tool.options.get_option_mandatory(:username), :password=>Main.tool.options.get_option_mandatory(:password)}})
        end

        def self.textify_package_list(table_data)
          return table_data.map { |e|
            e.keys.each {|k| e[k]=e[k].first if e[k].is_a?(Array) and e[k].length == 1}
            #if e['to'].has_key?('recipient_delivery_id')
            #  e['recipient_delivery_id'] = e['to']['recipient_delivery_id'].first
            #else
            #  e['recipient_delivery_id'] = 'unknown'
            #end
            #if e['to'].has_key?('name')
            #  e['to'] = e['to']['name'].first
            #else
            #  e['to'] = 'unknown'
            #end
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

        def action_list; [ :package, :dropbox, :recv_publink, :source, :me ];end

        # we match recv command on atom feed on this field
        PACKAGE_MATCH_FIELD='delivery_id'

        def execute_action
          command=Main.tool.options.get_next_arg_from_list('command',action_list)
          case command
          when :package
            command_pkg=Main.tool.options.get_next_arg_from_list('command',[ :send, :recv, :list ])
            api_faspex=get_faspex_authenticated_api
            case command_pkg
            when :list
              all_inbox_xml=api_faspex.call({:operation=>'GET',:subpath=>"#{Main.tool.options.get_option(:box).to_s}.atom",:headers=>{'Accept'=>'application/xml'}})[:http].body
              all_inbox_data=XmlSimple.xml_in(all_inbox_xml, {"ForceArray" => true})
              if all_inbox_data.has_key?('entry')
                return {:data=>all_inbox_data['entry'],:type=>:hash_array,:fields=>['title','items',PACKAGE_MATCH_FIELD], :textify => lambda { |table_data| Faspex.textify_package_list(table_data)} }
              end
              return Main.no_result
            when :send
              filelist = Main.tool.options.get_remaining_arguments("file list")
              package_create_params={
                "delivery"=>{
                "title"=>Main.tool.options.get_option_mandatory(:title),
                "note"=>Main.tool.options.get_option_mandatory(:note),
                "recipients"=>Main.tool.options.get_option_mandatory(:recipient).split(','),
                "send_upload_result"=>true,
                "notify_on_upload"=> false,
                "notifiable_on_upload"=> "",
                "notify_on_download"=> false,
                "notifiable_on_download"=> "",
                "use_encryption_at_rest"=>false,
                "sources"=>[{"paths"=>filelist}]
                }
              }
              source_name=Main.tool.options.get_option(:source_name)
              if !source_name.nil?
                source_list=api_faspex.call({:operation=>'GET',:subpath=>"source_shares",:headers=>{'Accept'=>'application/json'}})[:data]['items']
                source_id=self.class.get_source_id(source_list,source_name)
                package_create_params['delivery']['sources'].first['id']=source_id
              end
              metadata=Main.tool.options.get_option(:metadata)
              if !metadata.nil?
                package_create_params['delivery']['metadata']=metadata
              end
              send_result=api_faspex.call({:operation=>'POST',:subpath=>'send',:json_params=>package_create_params,:headers=>{'Accept'=>'application/json'}})[:data]
              if send_result.has_key?('error')
                raise CliBadArgument,"#{send_result['error']['user_message']}: #{send_result['error']['internal_message']}"
              end
              if !source_name.nil?
                # no transfer spec if remote source
                return {:data=>[send_result['links']['status']],:type=>:value_list,:name=>'link'}
              end
              raise CliBadArgument,"expecting one session exactly" if send_result['xfer_sessions'].length != 1
              transfer_spec=send_result['xfer_sessions'].first
              transfer_spec['paths']=filelist.map { |i| {'source'=>i} }
              return Main.tool.start_transfer(transfer_spec)
            when :recv
              # UUID is not reliable, it changes at every call
              if false
                pkguuid=Main.tool.options.get_next_arg_value("Package ID")
                all_inbox_xml=api_faspex.call({:operation=>'GET',:subpath=>"#{Main.tool.options.get_option(:box).to_s}.atom",:headers=>{'Accept'=>'application/xml'}})[:http].body
                allinbox=XmlSimple.xml_in(all_inbox_xml, {"ForceArray" => true})
                package_entries=[]
                if allinbox.has_key?('entry')
                  package_entries=allinbox['entry'].select { |e| pkguuid.eql?(e[PACKAGE_MATCH_FIELD].first) }
                end
                if package_entries.length == 0
                  raise CliBadArgument,"no such package: #{pkguuid}"
                end
                package_entry=package_entries.first
              else
                # I dont know which delivery id is the right one if package was receive by group
                delivid=Main.tool.options.get_next_arg_value("Package delivery ID")
                entry_xml=api_faspex.call({:operation=>'GET',:subpath=>"#{Main.tool.options.get_option(:box).to_s}/#{delivid}",:headers=>{'Accept'=>'application/xml'}})[:http].body
                package_entry=XmlSimple.xml_in(entry_xml, {"ForceArray" => true})
              end
              destination_folder=Main.tool.options.get_next_arg_value('destination folder')
              transfer_uri=self.class.get_fasp_uri_from_entry(package_entry)
              transfer_spec=Fasp::Uri.new(transfer_uri).transfer_spec
              # NOTE: only external users have token in faspe: link !
              if !transfer_spec.has_key?('token')
                sanitized=transfer_uri.gsub('&','&amp;')
                xmlpayload='<?xml version="1.0" encoding="UTF-8"?><url-list xmlns="http://schemas.asperasoft.com/xml/url-list"><url href="'+sanitized+'"/></url-list>'
                transfer_spec['token']=api_faspex.call({:operation=>'POST',:subpath=>"issue-token?direction=down",:headers=>{'Accept'=>'text/plain','Content-Type'=>'application/vnd.aspera.url-list+xml'},:text_body_params=>xmlpayload})[:http].body
              end
              transfer_spec['direction']='receive'
              transfer_spec['destination_root']=destination_folder
              return Main.tool.start_transfer(transfer_spec)
            end
          when :source
            command_source=Main.tool.options.get_next_arg_from_list('command',[ :list, :id, :name ])
            api_faspex=get_faspex_authenticated_api
            source_list=api_faspex.call({:operation=>'GET',:subpath=>"source_shares",:headers=>{'Accept'=>'application/json'}})[:data]['items']
            case command_source
            when :list
              return {:data=>source_list,:type=>:hash_array}
            else # :id or :name
              source_match_val=Main.tool.options.get_next_arg_value('source id or name')
              #source_match_val=source_match_val.to_i if command_source.eql?(:id)
              source_ids=source_list.select { |i| i[command_source.to_s].to_s.eql?(source_match_val) }
              if source_ids.empty?
                raise CliError,"No such Faspex source #{command_source.to_s}: #{source_match_val} in [#{source_list.map{|i| i[command_source.to_s]}.join(', ')}]"
              end
              # get id and name
              source_name=source_ids.first['name']
              source_id=source_ids.first['id']
              source_hash=Main.tool.options.get_option(:storage)
              raise CliError,"No storage defined in aslmcli config" if source_hash.nil?
              if !source_hash.has_key?(source_name)
                raise CliError,"No such storage in aslmcli config: \"#{source_name}\" in [#{source_hash.keys.join(', ')}]"
              end
              source_info=source_hash[source_name]
              Log.log.debug("source_info: #{source_info}")
              command_node=Main.tool.options.get_next_arg_from_list('command',[ :info, :node ])
              case command_node
              when :info
                return {:data=>source_info,:type=>:key_val_list}
              when :node
                node_config=Main.tool.get_plugin_default_config(:node,source_info[@@KEY_NODE])
                raise CliError,"No such node aslmcli config: \"#{source_info[@@KEY_NODE]}\"" if node_config.nil?
                api_node=Rest.new(node_config[:url],{:auth=>{:type=>:basic,:username=>node_config[:username], :password=>node_config[:password]}})
                command=Main.tool.options.get_next_arg_from_list('command',Node.common_actions)
                return Node.execute_common(command,api_node,source_info[@@KEY_PATH])
              end
            end
          when :me
            api_faspex=get_faspex_authenticated_api
            my_info=api_faspex.call({:operation=>'GET',:subpath=>"me",:headers=>{'Accept'=>'application/json'}})[:data]
            return {:data=>my_info, :type=>:key_val_list}
          when :dropbox
            api_faspex=get_faspex_authenticated_api
            command_pkg=Main.tool.options.get_next_arg_from_list('command',[ :list ])
            case command_pkg
            when :list
              dropbox_list=api_faspex.call({:operation=>'GET',:subpath=>"/aspera/faspex/dropboxes",:headers=>{'Accept'=>'application/json'}})[:data]
              return {:data=>dropbox_list['items'], :type=>:hash_array, :fields=>['name','id','description','can_read','can_write']}
            end
          when :recv_publink
            thelink=Main.tool.options.get_next_arg_value("Faspex public URL for a package")
            destination_folder=Main.tool.options.get_next_arg_value('destination folder')
            link_data=self.class.get_link_data(thelink)
            # Note: unauthenticated API
            api_faspex=Rest.new(link_data[:faspex_base_url],{})
            pkgdatares=api_faspex.call({:operation=>'GET',:subpath=>link_data[:subpath],:url_params=>{:passcode=>link_data[:passcode]},:headers=>{'Accept'=>'application/xml'}})
            if !pkgdatares[:http].body.start_with?('<?xml ')
              OperatingSystem.open_uri(thelink)
              raise CliError, "no such package"
            end
            package_entry=XmlSimple.xml_in(pkgdatares[:http].body, {"ForceArray" => false})
            transfer_uri=self.class.get_fasp_uri_from_entry(package_entry)
            transfer_spec=Fasp::Uri.new(transfer_uri).transfer_spec
            transfer_spec['direction']='receive'
            transfer_spec['destination_root']=destination_folder
            return Main.tool.start_transfer(transfer_spec)
          end # command
        end
      end
    end
  end # Cli
end # Asperalm
