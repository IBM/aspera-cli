require 'aspera/cli/basic_auth_plugin'
require 'aspera/cli/plugins/node'
require 'aspera/cli/plugins/config'
require 'aspera/cli/extended_value'
require 'aspera/cli/transfer_agent'
require 'aspera/persistency_file'
require 'aspera/open_application'
require 'aspera/fasp/uri'
require 'aspera/nagios'
require 'xmlsimple'
require 'json'

module Aspera
  module Cli
    module Plugins
      class Faspex < BasicAuthPlugin
        KEY_NODE='node'
        KEY_PATH='path'
        VAL_ALL='ALL'
        private_constant :KEY_NODE,:KEY_PATH,:VAL_ALL
        def initialize(env)
          @api_v3=nil
          @api_v4=nil
          super(env)
          self.options.add_opt_simple(:link,'public link for specific operation')
          self.options.add_opt_simple(:delivery_info,'package delivery information (extended value)')
          self.options.add_opt_simple(:source_name,'create package from remote source (by name)')
          self.options.add_opt_simple(:storage,'Faspex local storage definition')
          self.options.add_opt_list(:box,[:inbox,:sent,:archive],'package box')
          self.options.set_option(:box,:inbox)
          self.options.parse_options!
        end

        # extract elements from anonymous faspex link
        def self.get_link_data(publink)
          publink_uri=URI.parse(publink)
          if m=publink_uri.path.match(/^(.*)\/(external.*)$/)
            base=m[1]
            subpath=m[2]
          else
            raise CliBadArgument, 'public link does not match Faspex format'
          end
          port_add=publink_uri.port.eql?(publink_uri.default_port)?'':":#{publink_uri.port}"
          result={
            :base_url => "#{publink_uri.scheme}://#{publink_uri.host}#{port_add}#{base}",
            :subpath  => subpath,
            :query    => URI::decode_www_form(publink_uri.query).inject({}){|m,v|m[v.first]=v.last;m}
          }
          Log.dump('publink',result)
          return result
        end

        # get faspe: URI from entry in xml, and fix problems..
        def self.get_fasp_uri_from_entry(entry)
          raise CliBadArgument, 'package is empty' unless entry.has_key?('link')
          result=entry['link'].select{|e| e['rel'].eql?('package')}.first['href']
          # tags in the end of URL is not well % encoded... there are "=" that should be %3D
          # TODO: enter ticket to Faspex ?
          ###XXif m=result.match(/(=+)$/);result.gsub!(/=+$/,"#{"%3D"*m[1].length}");end
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
            faspex_api_base=self.options.get_option(:url,:mandatory)
            @api_v4=Rest.new({
              :base_url  => faspex_api_base+'/api',
              :auth      => {
              :type      => :oauth2,
              :base_url  => faspex_api_base+'/auth/oauth2',
              :grant     => :header_userpass,
              :user_name => self.options.get_option(:username,:mandatory),
              :user_pass => self.options.get_option(:password,:mandatory),
              :scope     => 'admin'
              }})
          end
          return @api_v4
        end

        ACTIONS=[ :nagios_check,:package, :source, :me, :dropbox, :v4, :address_book, :login_methods ]

        # we match recv command on atom feed on this field
        PACKAGE_MATCH_FIELD='package_id'

        def mailbox_all_entries
          mailbox=self.options.get_option(:box,:mandatory).to_s
          all_inbox_xml=api_v3.call({:operation=>'GET',:subpath=>"#{mailbox}.atom",:headers=>{'Accept'=>'application/xml'}})[:http].body
          all_inbox_data=XmlSimple.xml_in(all_inbox_xml, {'ForceArray' => true})
          Log.dump(:all_inbox_data,all_inbox_data)
          result=all_inbox_data.has_key?('entry') ? all_inbox_data['entry'] : []
          result.each do |e|
            e[PACKAGE_MATCH_FIELD]=e['to'].first['recipient_delivery_id'].first
          end
          # remove dropbox packages
          result.select!{|p|p['metadata'].first['field'].select{|j|j['name'].eql?('_dropbox_name')}.empty? rescue false}
          return result
        end

        # retrieve transfer spec from pub link for send package
        def send_publink_to_ts(public_link_url,package_create_params)
          delivery_info=package_create_params['delivery']
          # pub link user
          link_data=self.class.get_link_data(public_link_url)
          if !['external/submissions/new','external/dropbox_submissions/new'].include?(link_data[:subpath])
            raise CliBadArgument,"pub link is #{link_data[:subpath]}, expecting external/submissions/new"
          end
          create_path=link_data[:subpath].split('/')[0..-2].join('/')
          package_create_params.merge!({:passcode=>link_data[:query]['passcode']})
          delivery_info.merge!({
            :transfer_type     => 'connect',
            :source_paths_list => self.transfer.ts_source_paths.map{|i|i['source']}.join("\r\n")})
          api_public_link=Rest.new({:base_url=>link_data[:base_url]})
          # Hum, as this does not always work (only user, but not dropbox), we get the javascript and need hack
          #pkg_created=api_public_link.create(create_path,package_create_params)[:data]
          # so extract data from javascript
          pkgdatares=api_public_link.call({:operation=>'POST',:subpath=>create_path,:json_params=>package_create_params,:headers=>{'Accept'=>'text/javascript'}})[:http].body
          # get args of function call
          pkgdatares.gsub!("\n",'') # one line
          pkgdatares.gsub!(/^[^"]+\("\{/,'{') # delete header
          pkgdatares.gsub!(/"\);[^"]+$/,'"') # delete trailer
          pkgdatares.gsub!(/\}", *"/,'},"') # between two args
          pkgdatares.gsub!('\\"','"') # remove protecting quote
          begin
            pkgdatares=JSON.parse("[#{pkgdatares}]")
          rescue JSON::ParserError # => e
            raise "Link not valid"
          end
          return pkgdatares.first
        end

        def execute_action
          command=self.options.get_next_command(ACTIONS)
          case command
          when :nagios_check
            nagios=Nagios.new
            begin
              api_v3.read('me')
              nagios.add_ok('faspex api','accessible')
            rescue => e
              nagios.add_critical('faspex api',e.to_s)
            end
            return nagios.result
          when :package
            command_pkg=self.options.get_next_command([ :send, :recv, :list ])
            case command_pkg
            when :list
              return {:type=>:object_list,:data=>self.mailbox_all_entries,:fields=>[PACKAGE_MATCH_FIELD,'title','items'], :textify => lambda { |table_data| Faspex.textify_package_list(table_data)} }
            when :send
              delivery_info=self.options.get_option(:delivery_info,:mandatory)
              raise CliBadArgument,'delivery_info must be hash, refer to doc' unless delivery_info.is_a?(Hash)
              # actual parameter to faspex API
              package_create_params={'delivery'=>delivery_info}
              public_link_url=self.options.get_option(:link,:optional)
              if public_link_url.nil?
                # authenticated user
                delivery_info['sources']||=[{'paths'=>[]}]
                first_source=delivery_info['sources'].first
                first_source['paths'].push(*self.transfer.ts_source_paths.map{|i|i['source']})
                source_name=self.options.get_option(:source_name,:optional)
                if !source_name.nil?
                  source_list=api_v3.call({:operation=>'GET',:subpath=>'source_shares',:headers=>{'Accept'=>'application/json'}})[:data]['items']
                  source_id=self.class.get_source_id(source_list,source_name)
                  first_source['id']=source_id
                end
                pkg_created=api_v3.call({:operation=>'POST',:subpath=>'send',:json_params=>package_create_params,:headers=>{'Accept'=>'application/json'}})[:data]
                if !source_name.nil?
                  # no transfer spec if remote source
                  return {:data=>[pkg_created['links']['status']],:type=>:value_list,:name=>'link'}
                end
                raise CliBadArgument,'expecting one session exactly' if pkg_created['xfer_sessions'].length != 1
                transfer_spec=pkg_created['xfer_sessions'].first
                # use source from cmd line, this one only contains destination (already in dest root)
                transfer_spec.delete('paths')
              else # publink
                transfer_spec=send_publink_to_ts(public_link_url,package_create_params)
              end
              #Log.dump('transfer_spec',transfer_spec)
              return Main.result_transfer(self.transfer.start(transfer_spec,{:src=>:node_gen3}))
            when :recv
              public_link_url=self.options.get_option(:link,:optional)
              if !public_link_url.nil?
                link_data=self.class.get_link_data(public_link_url)
                if !link_data[:subpath].match(%r{external_deliveries/})
                  raise CliBadArgument,"pub link is #{link_data[:subpath]}, expecting external_deliveries/"
                end
                # Note: unauthenticated API
                api_public_link=Rest.new({:base_url=>link_data[:base_url]})
                pkgdatares=api_public_link.call({:operation=>'GET',:subpath=>link_data[:subpath],:url_params=>{:passcode=>link_data[:query]['passcode']},:headers=>{'Accept'=>'application/xml'}})
                if !pkgdatares[:http].body.start_with?('<?xml ')
                  OpenApplication.instance.uri(public_link_url)
                  raise CliError, 'no such package'
                end
                package_entry=XmlSimple.xml_in(pkgdatares[:http].body, {'ForceArray' => false})
                transfer_uri=self.class.get_fasp_uri_from_entry(package_entry)
                transfer_spec=Fasp::Uri.new(transfer_uri).transfer_spec
                transfer_spec['direction']='receive'
                return Main.result_transfer(self.transfer.start(transfer_spec,{:src=>:node_gen3}))
              end # public link
              # get command line parameters
              delivid=self.options.get_option(:id,:mandatory)
              # list of faspex ID/URI to download
              pkg_id_uri=nil
              skip_ids_data=[]
              skip_ids_persistency=nil
              if self.options.get_option(:once_only,:mandatory)
                skip_ids_persistency=PersistencyFile.new(
                data: skip_ids_data,
                ids:  ['faspex_recv',self.options.get_option(:url,:mandatory),self.options.get_option(:username,:mandatory),self.options.get_option(:box,:mandatory).to_s])
              end
              if delivid.eql?(VAL_ALL)
                pkg_id_uri=mailbox_all_entries.map{|i|{:id=>i[PACKAGE_MATCH_FIELD],:uri=>self.class.get_fasp_uri_from_entry(i)}}
                # TODO : remove ids from skip not present in inbox
                # skip_ids_data.select!{|id|pkg_id_uri.select{|p|p[:id].eql?(id)}}
                pkg_id_uri.select!{|i|!skip_ids_data.include?(i[:id])}
              else
                # TODO: delivery id is the right one if package was receive by group
                endpoint=case self.options.get_option(:box,:mandatory)
                when :inbox,:archive;'received'
                when :sent;'sent'
                end
                entry_xml=api_v3.call({:operation=>'GET',:subpath=>"#{endpoint}/#{delivid}",:headers=>{'Accept'=>'application/xml'}})[:http].body
                package_entry=XmlSimple.xml_in(entry_xml, {'ForceArray' => true})
                pkg_id_uri=[{:id=>delivid,:uri=>self.class.get_fasp_uri_from_entry(package_entry)}]
              end
              Log.dump(:pkg_id_uri,pkg_id_uri)
              return Main.result_status('no package') if pkg_id_uri.empty?
              result_transfer=[]
              pkg_id_uri.each do |id_uri|
                transfer_spec=Fasp::Uri.new(id_uri[:uri]).transfer_spec
                # NOTE: only external users have token in faspe: link !
                if !transfer_spec.has_key?('token')
                  sanitized=id_uri[:uri].gsub('&','&amp;')
                  # TODO: file jira
                  #XXsanitized.gsub!(/%3D%3D$/,'==')
                  #XXsanitized.gsub!(/%3D$/,'=')
                  xmlpayload='<?xml version="1.0" encoding="UTF-8"?><url-list xmlns="http://schemas.asperasoft.com/xml/url-list"><url href="'+sanitized+'"/></url-list>'
                  transfer_spec['token']=api_v3.call({:operation=>'POST',:subpath=>'issue-token?direction=down',:headers=>{'Accept'=>'text/plain','Content-Type'=>'application/vnd.aspera.url-list+xml'},:text_body_params=>xmlpayload})[:http].body
                end
                transfer_spec['direction']='receive'
                statuses=self.transfer.start(transfer_spec,{:src=>:node_gen3})
                result_transfer.push({'package'=>id_uri[:id],'status'=>statuses.map{|i|i.to_s}.join(',')})
                # skip only if all sessions completed
                skip_ids_data.push(id_uri[:id]) if TransferAgent.session_status(statuses).eql?(:success)
              end
              skip_ids_persistency.save unless skip_ids_persistency.nil?
              return {:type=>:object_list,:data=>result_transfer}
            end
          when :source
            command_source=self.options.get_next_command([ :list, :id, :name ])
            source_list=api_v3.call({:operation=>'GET',:subpath=>'source_shares',:headers=>{'Accept'=>'application/json'}})[:data]['items']
            case command_source
            when :list
              return {:type=>:object_list,:data=>source_list}
            else # :id or :name
              source_match_val=self.options.get_next_argument('source id or name')
              source_ids=source_list.select { |i| i[command_source.to_s].to_s.eql?(source_match_val) }
              if source_ids.empty?
                raise CliError,"No such Faspex source #{command_source.to_s}: #{source_match_val} in [#{source_list.map{|i| i[command_source.to_s]}.join(', ')}]"
              end
              # get id and name
              source_name=source_ids.first['name']
              source_id=source_ids.first['id']
              source_hash=self.options.get_option(:storage,:mandatory)
              # check value of option
              raise CliError,'storage option must be a Hash' unless source_hash.is_a?(Hash)
              source_hash.each do |name,storage|
                raise CliError,"storage '#{name}' must be a Hash" unless storage.is_a?(Hash)
                [KEY_NODE,KEY_PATH].each do |key|
                  raise CliError,"storage '#{name}' must have a '#{key}'" unless storage.has_key?(key)
                end
              end
              if !source_hash.has_key?(source_name)
                raise CliError,"No such storage in config file: \"#{source_name}\" in [#{source_hash.keys.join(', ')}]"
              end
              source_info=source_hash[source_name]
              Log.log.debug("source_info: #{source_info}")
              command_node=self.options.get_next_command([ :info, :node ])
              case command_node
              when :info
                return {:data=>source_info,:type=>:single_object}
              when :node
                node_config=ExtendedValue.instance.evaluate(source_info[KEY_NODE])
                raise CliError,"bad type for: \"#{source_info[KEY_NODE]}\"" unless node_config.is_a?(Hash)
                Log.log.debug("node=#{node_config}")
                api_node=Rest.new({
                  :base_url => node_config['url'],
                  :auth     => {
                  :type     =>:basic,
                  :username => node_config['username'],
                  :password => node_config['password']}})
                command=self.options.get_next_command(Node::COMMON_ACTIONS)
                return Node.new(@agents.merge(skip_basic_auth_options: true, node_api: api_node)).execute_action(command,source_info[KEY_PATH])
              end
            end
          when :me
            my_info=api_v3.call({:operation=>'GET',:subpath=>'me',:headers=>{'Accept'=>'application/json'}})[:data]
            return {:data=>my_info, :type=>:single_object}
          when :dropbox
            command_pkg=self.options.get_next_command([ :list ])
            case command_pkg
            when :list
              dropbox_list=api_v3.call({:operation=>'GET',:subpath=>'dropboxes',:headers=>{'Accept'=>'application/json'}})[:data]
              return {:type=>:object_list, :data=>dropbox_list['items'], :fields=>['name','id','description','can_read','can_write']}
            end
          when :v4
            command=self.options.get_next_command([:package,:dropbox, :dmembership, :workgroup,:wmembership,:user,:metadata_profile])
            case command
            when :dropbox
              return self.entity_action(api_v4,'admin/dropboxes',['id','e_wg_name','e_wg_desc','created_at'],:id)
            when :dmembership
              return self.entity_action(api_v4,'dropbox_memberships',nil,:id)
            when :workgroup
              return self.entity_action(api_v4,'admin/workgroups',['id','e_wg_name','e_wg_desc','created_at'],:id)
            when :wmembership
              return self.entity_action(api_v4,'workgroup_memberships',nil,:id)
            when :user
              return self.entity_action(api_v4,'users',['id','name','first_name','last_name'],:id)
            when :metadata_profile
              return self.entity_action(api_v4,'metadata_profiles',nil,:id)
            when :package
              pkg_box_type=self.options.get_next_command([:users])
              pkg_box_id=self.options.get_option(:id,:mandatory)
              return self.entity_action(api_v4,"#{pkg_box_type}/#{pkg_box_id}/packages",nil,:id)
            end
          when :address_book
            result=api_v3.call({:operation=>'GET',:subpath=>'address-book',:headers=>{'Accept'=>'application/json'},:url_params=>{'format'=>'json','count'=>100000}})[:data]
            self.format.display_status("users: #{result['itemsPerPage']}/#{result['totalResults']}, start:#{result['startIndex']}")
            users=result['entry']
            # add missing entries
            users.each do |u|
              unless u['emails'].nil?
                email=u['emails'].find{|i|i['primary'].eql?('true')}
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
          when :login_methods
            login_meths=api_v3.call({:operation=>'GET',:subpath=>'login/new',:headers=>{'Accept'=>'application/xrds+xml'}})[:http].body
            login_methods=XmlSimple.xml_in(login_meths, {'ForceArray' => false})
            return {:type=>:object_list, :data=>login_methods['XRD']['Service']}
          end # command
        end
      end
    end
  end # Cli
end # Aspera
