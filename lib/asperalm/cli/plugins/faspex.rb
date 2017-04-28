require 'asperalm/cli/basic_auth_plugin'

module Asperalm
  module Cli
    module Plugins
      class Faspex < BasicAuthPlugin
        attr_accessor :faspmanager
        alias super_set_options set_options
        def set_options
          super_set_options
          @option_parser.set_option(:pkgbox,:inbox)
          @option_parser.add_opt_simple(:recipient,"--recipient=STRING","package recipient")
          @option_parser.add_opt_simple(:title,"--title=STRING","package title")
          @option_parser.add_opt_simple(:note,"--note=STRING","package note")
          @option_parser.add_opt_list(:pkgbox,[:inbox,:sent,:archive],"package box",'--box=TYPE')
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

        def self.get_fasp_uri_from_entry(entry)
          raise CliBadArgument, "package is empty" if !entry.has_key?('link')
          return (entry['link'].select{|e| e["rel"].eql?("package")}).first["href"]
        end

        def get_faspex_authenticated_api
          return Rest.new(@option_parser.get_option_mandatory(:url),{:basic_auth=>{:user=>@option_parser.get_option_mandatory(:username), :password=>@option_parser.get_option_mandatory(:password)}})
        end

        def self.format_list(entries)
          return entries.map { |e|
            e.keys.each {|k| e[k]=e[k].first if e[k].is_a?(Array) and e[k].length == 1}
            if e['to'].has_key?('recipient_delivery_id')
              e['recipient_delivery_id'] = e['to']['recipient_delivery_id'].first
            else
              e['recipient_delivery_id'] = 'unknown'
            end
            e['items'] = e.has_key?('link') ? e['link'].length : 0
            e
          }
        end

        def execute_action
          command=@option_parser.get_next_arg_from_list('command',[ :package, :dropbox, :recv_publink, :list_shares, :me ])
          case command
          when :package
            command_pkg=@option_parser.get_next_arg_from_list('command',[ :send, :recv, :list ])
            api_faspex=get_faspex_authenticated_api
            case command_pkg
            when :send
              filelist = @option_parser.get_remaining_arguments("file list")
              send_result=api_faspex.call({:operation=>'POST',:subpath=>'send',:json_params=>{"delivery"=>{"use_encryption_at_rest"=>false,"note"=>@option_parser.get_option_mandatory(:note),"sources"=>[{"paths"=>filelist}],"title"=>@option_parser.get_option_mandatory(:title),"recipients"=>@option_parser.get_option_mandatory(:recipient).split(','),"send_upload_result"=>true}},:headers=>{'Accept'=>'application/json'}})[:data]
              if send_result.has_key?('error')
                raise CliBadArgument,"#{send_result['error']['user_message']} / #{send_result['error']['internal_message']}"
              end
              raise "expecting one session exactly" if send_result['xfer_sessions'].length != 1
              transfer_spec=send_result['xfer_sessions'].first
              transfer_spec['paths']=filelist.map { |i| {'source'=>i} }
              @faspmanager.transfer_with_spec(transfer_spec)
              return nil
            when :recv
              if true
                pkguuid=@option_parser.get_next_arg_value("Package UUID")
                all_inbox_xml=api_faspex.call({:operation=>'GET',:subpath=>"#{@option_parser.get_option(:pkgbox).to_s}.atom",:headers=>{'Accept'=>'application/xml'}})[:http].body
                allinbox=XmlSimple.xml_in(all_inbox_xml, {"ForceArray" => true})
                package_entries=[]
                if allinbox.has_key?('entry')
                  package_entries=allinbox['entry'].select { |e| pkguuid.eql?(e['id'].first) }
                end
                if package_entries.length != 1
                  raise CliBadArgument,"no such uuid"
                end
                package_entry=package_entries.first
              else
                delivid=@option_parser.get_next_arg_value("Package delivery ID")
                entry_xml=api_faspex.call({:operation=>'GET',:subpath=>"received/#{delivid}",:headers=>{'Accept'=>'application/xml'}})[:http].body
                package_entry=XmlSimple.xml_in(entry_xml, {"ForceArray" => true})
              end
              transfer_uri=self.class.get_fasp_uri_from_entry(package_entry)
              transfer_spec=@faspmanager.fasp_uri_to_transferspec(transfer_uri)
              # NOTE: only external users have token in faspe: link !
              if !transfer_spec.has_key?('token')
                xmlpayload='<?xml version="1.0" encoding="UTF-8"?><url-list xmlns="http://schemas.asperasoft.com/xml/url-list"><url href="'+transfer_uri+'"/></url-list>'
                transfer_spec['token']=api_faspex.call({:operation=>'POST',:subpath=>"issue-token?direction=down",:headers=>{'Accept'=>'text/plain','Content-Type'=>'application/vnd.aspera.url-list+xml'},:text_body_params=>xmlpayload})[:http].body
              end
              transfer_spec['direction']='receive'
              transfer_spec['destination_root']='.'
              @faspmanager.transfer_with_spec(transfer_spec)
              return nil
            when :list
              all_inbox_xml=api_faspex.call({:operation=>'GET',:subpath=>"#{@option_parser.get_option(:pkgbox).to_s}.atom",:headers=>{'Accept'=>'application/xml'}})[:http].body
              all_inbox_data=XmlSimple.xml_in(all_inbox_xml, {"ForceArray" => true})
              if all_inbox_data.has_key?('entry')
                return {:values=>all_inbox_data['entry'],:fields=>['title','items','recipient_delivery_id','id'], :textify => lambda { |items| Faspex.format_list(items)} }
              end
              return nil
            end
            when :list_shares
            api_faspex=get_faspex_authenticated_api
            shares_list=api_faspex.call({:operation=>'GET',:subpath=>"source_shares",:headers=>{'Accept'=>'application/json'}})[:data]
            return {:values=>shares_list['items']}
            when :me
            api_faspex=get_faspex_authenticated_api
            my_info=api_faspex.call({:operation=>'GET',:subpath=>"me",:headers=>{'Accept'=>'application/json'}})[:data]
            return {:values=>[my_info]}
            when :dropbox
            api_faspex=get_faspex_authenticated_api
            command_pkg=@option_parser.get_next_arg_from_list('command',[ :list ])
            case command_pkg
            when :list
            dropbox_list=api_faspex.call({:operation=>'GET',:subpath=>"/aspera/faspex/dropboxes",:headers=>{'Accept'=>'application/json'}})[:data]
            return {:values=>dropbox_list['items'], :fields=>['name','id','description','can_read','can_write']}
            end
          when :recv_publink
            thelink=@option_parser.get_next_arg_value("Faspex public URL for a package")
            link_data=self.class.get_link_data(thelink)
            # Note: unauthenticated API
            api_faspex=Rest.new(link_data[:faspex_base_url],{})
            pkgdatares=api_faspex.call({:operation=>'GET',:subpath=>link_data[:subpath],:url_params=>{:passcode=>link_data[:passcode]},:headers=>{'Accept'=>'application/xml'}})
            raise StandardError, "no such package, please visit: #{thelink}" if !pkgdatares[:http].body.start_with?('<?xml ')
            package_entry=XmlSimple.xml_in(pkgdatares[:http].body, {"ForceArray" => false})
            transfer_uri=self.class.get_fasp_uri_from_entry(package_entry)
            transfer_spec=@faspmanager.fasp_uri_to_transferspec(transfer_uri)
            transfer_spec['direction']='receive'
            transfer_spec['destination_root']='.'
            @faspmanager.transfer_with_spec(transfer_spec)
            return nil
          end # command
        end
      end
    end
  end # Cli
end # Asperalm
