# frozen_string_literal: true

require 'aspera/cli/basic_auth_plugin'
require 'aspera/cli/plugins/node'
require 'aspera/cli/plugins/config'
require 'aspera/cli/extended_value'
require 'aspera/cli/transfer_agent'
require 'aspera/persistency_action_once'
require 'aspera/open_application'
require 'aspera/fasp/uri'
require 'aspera/fasp/transfer_spec'
require 'aspera/nagios'
require 'aspera/id_generator'
require 'xmlsimple'
require 'json'
require 'cgi'

module Aspera
  module Cli
    module Plugins
      class Faspex < Aspera::Cli::BasicAuthPlugin
        # required hash key for source in config
        KEY_NODE = 'node' # value must be hash with url, username, password
        KEY_PATH = 'path' # value must be same sub-path as in Faspex's node
        # added field in result that identifies the package
        PACKAGE_MATCH_FIELD = 'package_id'
        # list of supported atoms
        ATOM_MAILBOXES = %i[inbox archive sent].freeze
        # allowed parameters for inbox.atom
        ATOM_PARAMS = %w[page count startIndex].freeze
        # with special parameters (from Plugin class) : max and pmax (from Plugin)
        ATOM_EXT_PARAMS = [MAX_ITEMS, MAX_PAGES].concat(ATOM_PARAMS).freeze
        # sub path in url for public link delivery
        PUB_LINK_EXTERNAL_MATCH = 'external_deliveries/'
        private_constant(*%i[KEY_NODE KEY_PATH PACKAGE_MATCH_FIELD ATOM_MAILBOXES ATOM_PARAMS ATOM_EXT_PARAMS PUB_LINK_EXTERNAL_MATCH])

        class << self
          def detect(base_url)
            api = Rest.new(base_url: base_url)
            result = api.call(
              operation:        'POST',
              subpath:          'aspera/faspex',
              headers:          {'Accept' => 'application/xrds+xml', 'Content-type' => 'text/plain'},
              text_body_params: '')
            # 4.x
            if result[:http].body.start_with?('<?xml')
              res_s = XmlSimple.xml_in(result[:http].body, {'ForceArray' => false})
              version = res_s['XRD']['application']['version']
              return {version: version}
            end
            return nil
          end

          # extract elements from anonymous faspex link
          def get_link_data(publink)
            publink_uri = URI.parse(publink)
            raise CliBadArgument, 'Public link does not match Faspex format' unless (m = publink_uri.path.match(%r{^(.*)/(external.*)$}))
            base = m[1]
            subpath = m[2]
            port_add = publink_uri.port.eql?(publink_uri.default_port) ? '' : ":#{publink_uri.port}"
            result = {
              base_url: "#{publink_uri.scheme}://#{publink_uri.host}#{port_add}#{base}",
              subpath:  subpath,
              query:    URI.decode_www_form(publink_uri.query).each_with_object({}){|v, h|h[v.first] = v.last; }
            }
            Log.dump('publink', result)
            return result
          end

          # get faspe: URI from entry in xml, and fix problems..
          def get_fasp_uri_from_entry(entry, raise_no_link: true)
            unless entry.key?('link')
              raise CliBadArgument, 'package has no link (deleted?)' if raise_no_link
              return nil
            end
            result = entry['link'].find{|e| e['rel'].eql?('package')}['href']
            # tags in the end of URL is not well % encoded... there are "=" that should be %3D
            # TODO: enter ticket to Faspex ?
            # ##XXif m=result.match(/(=+)$/);result.gsub!(/=+$/,"#{"%3D"*m[1].length}");end
            return result
          end

          def textify_package_list(table_data)
            return table_data.map do |e|
              e.each_key {|k| e[k] = e[k].first if e[k].is_a?(Array) && (e[k].length == 1)}
              e['items'] = e.key?('link') ? e['link'].length : 0
              e
            end
          end

          # field_sym : :id or :name
          def get_source_id(source_list, source_name)
            source_ids = source_list.select { |i| i['name'].eql?(source_name) }
            if source_ids.empty?
              raise CliError, %Q(No such Faspex source "#{source_name}" in [#{source_list.map{|i| %Q("#{i['name']}")}.join(', ')}])
            end
            return source_ids.first['id']
          end
        end

        def initialize(env)
          @api_v3 = nil
          @api_v4 = nil
          super(env)
          options.add_opt_simple(:link, 'public link for specific operation')
          options.add_opt_simple(:delivery_info, 'package delivery information (extended value)')
          options.add_opt_simple(:source_name, 'create package from remote source (by name)')
          options.add_opt_simple(:storage, 'Faspex local storage definition')
          options.add_opt_simple(:recipient, 'use if recipient is a dropbox (with *)')
          options.add_opt_list(:box, ATOM_MAILBOXES, 'package box')
          options.set_option(:box, :inbox)
          options.parse_options!
        end

        def api_v3
          if @api_v3.nil?
            @api_v3 = basic_auth_api
          end
          return @api_v3
        end

        def api_v4
          if @api_v4.nil?
            faspex_api_base = options.get_option(:url, is_type: :mandatory)
            @api_v4 = Rest.new({
              base_url: faspex_api_base + '/api',
              auth:     {
                type:     :oauth2,
                base_url: faspex_api_base + '/auth/oauth2',
                auth:     {type: :basic, username: options.get_option(:username, is_type: :mandatory), password: options.get_option(:password, is_type: :mandatory)},
                crtype:   :generic,
                generic:  {grant_type: 'password'},
                scope:    'admin'
              }})
          end
          return @api_v4
        end

        # query supports : {"startIndex":10,"count":1,"page":109,"max":2,"pmax":1}
        def mailbox_filtered_entries(stop_at_id: nil)
          recipient_names = [options.get_option(:recipient) || options.get_option(:username, is_type: :mandatory)]
          # some workgroup messages have no star in recipient name
          recipient_names.push(recipient_names.first[1..-1]) if recipient_names.first.start_with?('*')
          # mailbox is in ATOM_MAILBOXES
          mailbox = options.get_option(:box, is_type: :mandatory)
          # parameters
          mailbox_query = options.get_option(:query)
          max_items = nil
          max_pages = nil
          result = []
          if !mailbox_query.nil?
            raise 'query: must be Hash or nil' unless mailbox_query.is_a?(Hash)
            raise "query: supported params: #{ATOM_EXT_PARAMS}" unless (mailbox_query.keys - ATOM_EXT_PARAMS).empty?
            raise 'query: startIndex and page are exclusive' if mailbox_query.key?('startIndex') && mailbox_query.key?('page')
            max_items = mailbox_query[MAX_ITEMS]
            mailbox_query.delete(MAX_ITEMS)
            max_pages = mailbox_query[MAX_PAGES]
            mailbox_query.delete(MAX_PAGES)
          end
          loop do
            # get a batch of package information
            # order: first batch is latest packages, and then in a batch ids are increasing
            atom_xml = api_v3.call({operation: 'GET', subpath: "#{mailbox}.atom", headers: {'Accept' => 'application/xml'}, url_params: mailbox_query})[:http].body
            box_data = XmlSimple.xml_in(atom_xml, {'ForceArray' => true})
            Log.dump(:box_data, box_data)
            items = box_data.key?('entry') ? box_data['entry'] : []
            Log.log.debug{"new items: #{items.count}"}
            # it is the end if page is empty
            break if items.empty?
            stop_condition = false
            # results will be sorted in reverse id
            items.reverse_each do |package|
              package[PACKAGE_MATCH_FIELD] =
                case mailbox
                when :inbox, :archive
                  recipient = package['to'].find{|i|recipient_names.include?(i['name'].first)}
                  recipient.nil? ? nil : recipient['recipient_delivery_id'].first
                else # :sent
                  package['delivery_id'].first
                end
              # if we look for a specific package
              stop_condition = true if !stop_at_id.nil? && stop_at_id.eql?(package[PACKAGE_MATCH_FIELD])
              # keep only those for the specified recipient,
              result.push(package) unless package[PACKAGE_MATCH_FIELD].nil?
            end
            break if stop_condition
            # result.push({PACKAGE_MATCH_FIELD=>'======'})
            Log.log.debug{"total items: #{result.count}"}
            # reach the limit ?
            if !max_items.nil? && (result.count >= max_items)
              result = result.slice(0, max_items) if result.count > max_items
              break
            end
            link = box_data['link'].find{|i|i['rel'].eql?('next')}
            Log.log.debug{"link: #{link}"}
            # no next link
            break if link.nil?
            # replace parameters with the ones from next link
            params = CGI.parse(URI.parse(link['href']).query)
            mailbox_query = params.keys.each_with_object({}){|i, m|; m[i] = params[i].first; }
            Log.log.debug{"query: #{mailbox_query}"}
            break if !max_pages.nil? && (mailbox_query['page'].to_i > max_pages)
          end
          return result
        end

        # retrieve transfer spec from pub link for send package
        def send_publink_to_ts(public_link_url, package_create_params)
          delivery_info = package_create_params['delivery']
          # pub link user
          link_data = self.class.get_link_data(public_link_url)
          if !['external/submissions/new', 'external/dropbox_submissions/new'].include?(link_data[:subpath])
            raise CliBadArgument, "pub link is #{link_data[:subpath]}, expecting external/submissions/new"
          end
          create_path = link_data[:subpath].split('/')[0..-2].join('/')
          package_create_params[:passcode] = link_data[:query]['passcode']
          delivery_info[:transfer_type] = 'connect'
          delivery_info[:source_paths_list] = transfer.ts_source_paths.map{|i|i['source']}.join("\r\n")
          api_public_link = Rest.new({base_url: link_data[:base_url]})
          # Hum, as this does not always work (only user, but not dropbox), we get the javascript and need hack
          # pkg_created=api_public_link.create(create_path,package_create_params)[:data]
          # so extract data from javascript
          pkgdatares = api_public_link.call({
            operation:   'POST',
            subpath:     create_path,
            json_params: package_create_params,
            headers:     {'Accept' => 'text/javascript'}})[:http].body
          # get args of function call
          pkgdatares.delete!("\n") # one line
          pkgdatares.gsub!(/^[^"]+\("\{/, '{') # delete header
          pkgdatares.gsub!(/"\);[^"]+$/, '"') # delete trailer
          pkgdatares.gsub!(/\}", *"/, '},"') # between two args
          pkgdatares.gsub!('\\"', '"') # remove protecting quote
          begin
            pkgdatares = JSON.parse("[#{pkgdatares}]")
          rescue JSON::ParserError # => e
            raise 'Unexpected response: missing metadata ?'
          end
          return pkgdatares.first
        end

        ACTIONS = %i[health package source me dropbox v4 address_book login_methods].freeze

        def execute_action
          command = options.get_next_command(ACTIONS)
          case command
          when :health
            nagios = Nagios.new
            begin
              api_v3.read('me')
              nagios.add_ok('faspex api', 'accessible')
            rescue StandardError => e
              nagios.add_critical('faspex api', e.to_s)
            end
            return nagios.result
          when :package
            command_pkg = options.get_next_command(%i[send recv list])
            case command_pkg
            when :list
              return {
                type:    :object_list,
                data:    mailbox_filtered_entries,
                fields:  [PACKAGE_MATCH_FIELD, 'title', 'items'],
                textify: lambda {|table_data|Faspex.textify_package_list(table_data)}
              }
            when :send
              delivery_info = options.get_option(:delivery_info, is_type: :mandatory)
              raise CliBadArgument, 'delivery_info must be hash, refer to doc' unless delivery_info.is_a?(Hash)
              # actual parameter to faspex API
              package_create_params = {'delivery' => delivery_info}
              public_link_url = options.get_option(:link)
              if public_link_url.nil?
                # authenticated user
                delivery_info['sources'] ||= [{'paths' => []}]
                first_source = delivery_info['sources'].first
                first_source['paths'].push(*transfer.ts_source_paths.map{|i|i['source']})
                source_name = options.get_option(:source_name)
                if !source_name.nil?
                  source_list = api_v3.call({operation: 'GET', subpath: 'source_shares', headers: {'Accept' => 'application/json'}})[:data]['items']
                  source_id = self.class.get_source_id(source_list, source_name)
                  first_source['id'] = source_id
                end
                pkg_created = api_v3.call({
                  operation:   'POST',
                  subpath:     'send',
                  json_params: package_create_params,
                  headers:     {'Accept' => 'application/json'}
                })[:data]
                if !source_name.nil?
                  # no transfer spec if remote source
                  return {data: [pkg_created['links']['status']], type: :value_list, name: 'link'}
                end
                raise CliBadArgument, 'expecting one session exactly' if pkg_created['xfer_sessions'].length != 1
                transfer_spec = pkg_created['xfer_sessions'].first
                # use source from cmd line, this one only contains destination (already in dest root)
                transfer_spec.delete('paths')
              else # publink
                transfer_spec = send_publink_to_ts(public_link_url, package_create_params)
              end
              # Log.dump('transfer_spec',transfer_spec)
              return Main.result_transfer(transfer.start(transfer_spec))
            when :recv
              link_url = options.get_option(:link)
              # list of faspex ID/URI to download
              pkg_id_uri = nil
              skip_ids_data = []
              skip_ids_persistency = nil
              case link_url
              when nil # usual case: no link
                if options.get_option(:once_only, is_type: :mandatory)
                  skip_ids_persistency = PersistencyActionOnce.new(
                    manager: @agents[:persistency],
                    data:    skip_ids_data,
                    id:      IdGenerator.from_list([
                      'faspex_recv',
                      options.get_option(:url, is_type: :mandatory),
                      options.get_option(:username, is_type: :mandatory),
                      options.get_option(:box, is_type: :mandatory).to_s
                    ]))
                end
                # get command line parameters
                delivid = instance_identifier
                raise 'empty id' if delivid.empty?
                recipient = options.get_option(:recipient)
                if VAL_ALL.eql?(delivid)
                  pkg_id_uri = mailbox_filtered_entries.map{|i|{id: i[PACKAGE_MATCH_FIELD], uri: self.class.get_fasp_uri_from_entry(i, raise_no_link: false)}}
                elsif !recipient.nil? && recipient.start_with?('*')
                  found_package_link = mailbox_filtered_entries(stop_at_id: delivid).find{|p|p[PACKAGE_MATCH_FIELD].eql?(delivid)}['link'].first['href']
                  raise 'Not Found. Dropbox and Workgroup packages can use the link option with faspe:' if found_package_link.nil?
                  pkg_id_uri = [{id: delivid, uri: found_package_link}]
                else
                  # TODO: delivery id is the right one if package was receive by workgroup
                  endpoint =
                    case options.get_option(:box, is_type: :mandatory)
                    when :inbox, :archive then'received'
                    when :sent then 'sent'
                    end
                  entry_xml = api_v3.call({operation: 'GET', subpath: "#{endpoint}/#{delivid}", headers: {'Accept' => 'application/xml'}})[:http].body
                  package_entry = XmlSimple.xml_in(entry_xml, {'ForceArray' => true})
                  pkg_id_uri = [{id: delivid, uri: self.class.get_fasp_uri_from_entry(package_entry)}]
                end
              when /^faspe:/
                pkg_id_uri = [{id: 'package', uri: link_url}]
              else
                link_data = self.class.get_link_data(link_url)
                if !link_data[:subpath].start_with?(PUB_LINK_EXTERNAL_MATCH)
                  raise CliBadArgument, "Pub link is #{link_data[:subpath]}. Expecting #{PUB_LINK_EXTERNAL_MATCH}"
                end
                # NOTE: unauthenticated API (authorization is in url params)
                api_public_link = Rest.new({base_url: link_data[:base_url]})
                pkgdatares = api_public_link.call(
                  operation: 'GET',
                  subpath: link_data[:subpath],
                  url_params: {passcode: link_data[:query]['passcode']},
                  headers: {'Accept' => 'application/xml'})
                if !pkgdatares[:http].body.start_with?('<?xml ')
                  OpenApplication.instance.uri(link_url)
                  raise CliError, 'Unexpected response: package not found ?'
                end
                package_entry = XmlSimple.xml_in(pkgdatares[:http].body, {'ForceArray' => false})
                Log.dump(:package_entry, package_entry)
                transfer_uri = self.class.get_fasp_uri_from_entry(package_entry)
                pkg_id_uri = [{id: package_entry['id'], uri: transfer_uri}]
              end # public link
              # prune packages already downloaded
              # TODO : remove ids from skip not present in inbox to avoid growing too big
              # skip_ids_data.select!{|id|pkg_id_uri.select{|p|p[:id].eql?(id)}}
              pkg_id_uri.reject!{|i|skip_ids_data.include?(i[:id])}
              Log.dump(:pkg_id_uri, pkg_id_uri)
              return Main.result_status('no new package') if pkg_id_uri.empty?
              result_transfer = []
              pkg_id_uri.each do |id_uri|
                if id_uri[:uri].nil?
                  # skip package with no link: empty or content deleted
                  statuses = [:success]
                else
                  transfer_spec = Fasp::Uri.new(id_uri[:uri]).transfer_spec
                  # NOTE: only external users have token in faspe: link !
                  if !transfer_spec.key?('token')
                    sanitized = id_uri[:uri].gsub('&', '&amp;')
                    xmlpayload =
                      %Q(<?xml version="1.0" encoding="UTF-8"?><url-list xmlns="http://schemas.asperasoft.com/xml/url-list"><url href="#{sanitized}"/></url-list>)
                    transfer_spec['token'] = api_v3.call({
                      operation:        'POST',
                      subpath:          'issue-token?direction=down',
                      headers:          {'Accept' => 'text/plain', 'Content-Type' => 'application/vnd.aspera.url-list+xml'},
                      text_body_params: xmlpayload})[:http].body
                  end
                  transfer_spec['direction'] = Fasp::TransferSpec::DIRECTION_RECEIVE
                  statuses = transfer.start(transfer_spec)
                end
                result_transfer.push({'package' => id_uri[:id], Main::STATUS_FIELD => statuses})
                # skip only if all sessions completed
                skip_ids_data.push(id_uri[:id]) if TransferAgent.session_status(statuses).eql?(:success)
              end
              skip_ids_persistency&.save
              return Main.result_transfer_multiple(result_transfer)
            end
          when :source
            command_source = options.get_next_command(%i[list id name])
            source_list = api_v3.call({operation: 'GET', subpath: 'source_shares', headers: {'Accept' => 'application/json'}})[:data]['items']
            case command_source
            when :list
              return {type: :object_list, data: source_list}
            else # :id or :name
              source_match_val = options.get_next_argument('source id or name')
              source_ids = source_list.select { |i| i[command_source.to_s].to_s.eql?(source_match_val) }
              if source_ids.empty?
                raise CliError, "No such Faspex source #{command_source}: #{source_match_val} in [#{source_list.map{|i| i[command_source.to_s]}.join(', ')}]"
              end
              # get id and name
              source_name = source_ids.first['name']
              # source_id=source_ids.first['id']
              source_hash = options.get_option(:storage, is_type: :mandatory)
              # check value of option
              raise CliError, 'storage option must be a Hash' unless source_hash.is_a?(Hash)
              source_hash.each do |name, storage|
                raise CliError, "storage '#{name}' must be a Hash" unless storage.is_a?(Hash)
                [KEY_NODE, KEY_PATH].each do |key|
                  raise CliError, "storage '#{name}' must have a '#{key}'" unless storage.key?(key)
                end
              end
              if !source_hash.key?(source_name)
                raise CliError, "No such storage in config file: \"#{source_name}\" in [#{source_hash.keys.join(', ')}]"
              end
              source_info = source_hash[source_name]
              Log.log.debug{"source_info: #{source_info}"}
              command_node = options.get_next_command(%i[info node])
              case command_node
              when :info
                return {data: source_info, type: :single_object}
              when :node
                node_config = ExtendedValue.instance.evaluate(source_info[KEY_NODE])
                raise CliError, "bad type for: \"#{source_info[KEY_NODE]}\"" unless node_config.is_a?(Hash)
                Log.log.debug{"node=#{node_config}"}
                api_node = Rest.new({
                  base_url: node_config['url'],
                  auth:     {
                    type:     :basic,
                    username: node_config['username'],
                    password: node_config['password']}})
                command = options.get_next_command(Node::COMMANDS_FASPEX)
                return Node.new(@agents.merge(skip_basic_auth_options: true, node_api: api_node)).execute_action(command, source_info[KEY_PATH])
              end
            end
          when :me
            my_info = api_v3.call({operation: 'GET', subpath: 'me', headers: {'Accept' => 'application/json'}})[:data]
            return {data: my_info, type: :single_object}
          when :dropbox
            command_pkg = options.get_next_command([:list])
            case command_pkg
            when :list
              dropbox_list = api_v3.call({operation: 'GET', subpath: 'dropboxes', headers: {'Accept' => 'application/json'}})[:data]
              return {type: :object_list, data: dropbox_list['items'], fields: %w[name id description can_read can_write]}
            end
          when :v4
            command = options.get_next_command(%i[package dropbox dmembership workgroup wmembership user metadata_profile])
            case command
            when :dropbox
              return entity_action(api_v4, 'admin/dropboxes', display_fields: %w[id e_wg_name e_wg_desc created_at])
            when :dmembership
              return entity_action(api_v4, 'dropbox_memberships')
            when :workgroup
              return entity_action(api_v4, 'admin/workgroups', display_fields: %w[id e_wg_name e_wg_desc created_at])
            when :wmembership
              return entity_action(api_v4, 'workgroup_memberships')
            when :user
              return entity_action(api_v4, 'users', display_fields: %w[id name first_name last_name])
            when :metadata_profile
              return entity_action(api_v4, 'metadata_profiles')
            when :package
              pkg_box_type = options.get_next_command([:users])
              pkg_box_id = instance_identifier
              return entity_action(api_v4, "#{pkg_box_type}/#{pkg_box_id}/packages")
            end
          when :address_book
            result = api_v3.call(
              operation: 'GET',
              subpath: 'address-book',
              headers: {'Accept' => 'application/json'},
              url_params: {'format' => 'json', 'count' => 100_000}
            )[:data]
            self.format.display_status("users: #{result['itemsPerPage']}/#{result['totalResults']}, start:#{result['startIndex']}")
            users = result['entry']
            # add missing entries
            users.each do |u|
              unless u['emails'].nil?
                email = u['emails'].find{|i|i['primary'].eql?('true')}
                u['email'] = email['value'] unless email.nil?
              end
              if u['email'].nil?
                Log.log.warn{"Skip user without email: #{u}"}
                next
              end
              u['first_name'], u['last_name'] = u['displayName'].split(' ', 2)
              u['x'] = true
            end
            return {type: :object_list, data: users}
          when :login_methods
            login_meths = api_v3.call({operation: 'GET', subpath: 'login/new', headers: {'Accept' => 'application/xrds+xml'}})[:http].body
            login_methods = XmlSimple.xml_in(login_meths, {'ForceArray' => false})
            return {type: :object_list, data: login_methods['XRD']['Service']}
          end # command
        end
      end
    end
  end # Cli
end # Aspera
