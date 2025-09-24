# frozen_string_literal: true

# cspell:ignore passcode xrds workgroups dmembership wmembership
require 'aspera/cli/basic_auth_plugin'
require 'aspera/cli/plugins/node'
require 'aspera/cli/plugins/config'
require 'aspera/cli/extended_value'
require 'aspera/cli/special_values'
require 'aspera/cli/transfer_agent'
require 'aspera/transfer/uri'
require 'aspera/transfer/spec'
require 'aspera/persistency_action_once'
require 'aspera/environment'
require 'aspera/nagios'
require 'aspera/id_generator'
require 'aspera/log'
require 'aspera/assert'
require 'xmlsimple'
require 'json'
require 'cgi'

module Aspera
  module Cli
    module Plugins
      class Faspex < Cli::BasicAuthPlugin
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
        STANDARD_PATH = '/aspera/faspex'
        HEADER_FASPEX_VERSION = 'X-IBM-Aspera'
        private_constant :KEY_NODE, :KEY_PATH, :PACKAGE_MATCH_FIELD, :ATOM_MAILBOXES, :ATOM_PARAMS, :ATOM_EXT_PARAMS, :PUB_LINK_EXTERNAL_MATCH, :HEADER_FASPEX_VERSION

        class << self
          def detect(address_or_url)
            address_or_url = "https://#{address_or_url}" unless address_or_url.match?(%r{^[a-z]{1,6}://})
            urls = [address_or_url]
            urls.push("#{address_or_url}#{STANDARD_PATH}") unless address_or_url.end_with?(STANDARD_PATH)
            error = nil
            urls.each do |base_url|
              next unless base_url.start_with?('https://')
              api = Rest.new(base_url: base_url, redirect_max: 1)
              result = api.call(
                operation:        'POST',
                headers:          {
                  'Content-type' => Rest::MIME_TEXT,
                  'Accept'       => 'application/xrds+xml'
                }
              )
              # 4.x
              next unless result[:http].body.start_with?('<?xml')
              res_s = XmlSimple.xml_in(result[:http].body, {'ForceArray' => false})
              Log.log.debug{"version: #{result[:http][HEADER_FASPEX_VERSION]}"}
              version = res_s['XRD']['application']['version']
              # take redirect if any
              return {
                version: version,
                url:     result[:http].uri.to_s
              }
            rescue StandardError => e
              error = e
              Log.log.debug{"detect error: #{e}"}
            end
            raise error if error
            return
          end

          # @param object [Plugin] An instance of this class
          # @return [Hash] :preset_value, :test_args
          def wizard(object:)
            options = object.options
            return {
              preset_value: {
                url:      options.get_option(:url, mandatory: true),
                username: options.get_option(:username, mandatory: true),
                password: options.get_option(:password, mandatory: true)
              },
              test_args:    'me'
            }
          end

          # extract elements from faspex public link
          def get_link_data(public_url)
            public_uri = URI.parse(public_url)
            Aspera.assert(m = public_uri.path.match(%r{^(.*)/(external.*)$}), type: Cli::BadArgument){'Public link does not match Faspex format'}
            base = m[1]
            subpath = m[2]
            port_add = public_uri.port.eql?(public_uri.default_port) ? '' : ":#{public_uri.port}"
            result = {
              base_url: "#{public_uri.scheme}://#{public_uri.host}#{port_add}#{base}",
              subpath:  subpath,
              query:    Rest.query_to_h(public_uri.query)
            }
            Log.dump(:link_data, result)
            return result
          end

          # get Transfer::Uri::SCHEME URI from entry in xml, and fix problems.
          def get_fasp_uri_from_entry(entry, raise_no_link: true)
            unless entry.key?('link')
              raise Cli::BadArgument, 'package has no link (deleted?)' if raise_no_link
              return
            end
            result = entry['link'].find{ |e| e['rel'].eql?('package')}['href']
            return result
          end

          # @return [Integer] identifier of source
          def get_source_id_by_name(source_name, source_list)
            match_source = source_list.find{ |i| i['name'].eql?(source_name)}
            return match_source['id'] unless match_source.nil?
            raise Cli::Error, %Q(No such Faspex source: "#{source_name}" in [#{source_list.map{ |i| %Q("#{i['name']}")}.join(', ')}])
          end
        end

        def initialize(**env)
          super
          @api_v3 = nil
          @api_v4 = nil
          options.declare(:link, 'Public link for specific operation')
          options.declare(:delivery_info, 'Package delivery information', types: Hash)
          options.declare(:remote_source, 'Remote source for package send (id or %name:)')
          options.declare(:storage, 'Faspex local storage definition (for browsing source)')
          options.declare(:recipient, 'Use if recipient is a dropbox (with *)')
          options.declare(:box, 'Package box', values: ATOM_MAILBOXES, default: :inbox)
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
            faspex_api_base = options.get_option(:url, mandatory: true)
            @api_v4 = Rest.new(
              base_url: "#{faspex_api_base}/api",
              auth:     {
                type:         :oauth2,
                grant_method: :generic,
                base_url:     "#{faspex_api_base}/auth/oauth2",
                auth:         {type: :basic, username: options.get_option(:username, mandatory: true), password: options.get_option(:password, mandatory: true)},
                scope:        'admin',
                grant_type:   'password'
              }
            )
          end
          return @api_v4
        end

        # query supports : {"startIndex":10,"count":1,"page":109,"max":2,"pmax":1}
        def mailbox_filtered_entries(stop_at_id: nil)
          recipient_names = [options.get_option(:recipient) || options.get_option(:username, mandatory: true)]
          # some workgroup messages have no star in recipient name
          recipient_names.push(recipient_names.first[1..-1]) if recipient_names.first.start_with?('*')
          # mailbox is in ATOM_MAILBOXES
          mailbox = options.get_option(:box, mandatory: true)
          # parameters
          mailbox_query = options.get_option(:query)
          max_items = nil
          max_pages = nil
          result = []
          if !mailbox_query.nil?
            Aspera.assert_type(mailbox_query, Hash){'query'}
            Aspera.assert((mailbox_query.keys - ATOM_EXT_PARAMS).empty?){"query: supported params: #{ATOM_EXT_PARAMS}"}
            Aspera.assert(!(mailbox_query.key?('startIndex') && mailbox_query.key?('page'))){'query: startIndex and page are exclusive'}
            max_items = mailbox_query[MAX_ITEMS]
            mailbox_query.delete(MAX_ITEMS)
            max_pages = mailbox_query[MAX_PAGES]
            mailbox_query.delete(MAX_PAGES)
          end
          loop do
            # get a batch of package information
            # order: first batch is latest packages, and then in a batch ids are increasing
            atom_xml = api_v3.call(
              operation: 'GET',
              subpath:   "#{mailbox}.atom",
              headers:   {'Accept' => 'application/xml'},
              query:     mailbox_query
            )[:http].body
            box_data = XmlSimple.xml_in(atom_xml, {'ForceArray' => %w[entry field link to]})
            Log.dump(:box_data, box_data)
            items = box_data.key?('entry') ? box_data['entry'] : []
            Log.log.debug{"new items: #{items.count}"}
            # it is the end if page is empty
            break if items.empty?
            stop_condition = false
            # results will be sorted in reverse id
            items.reverse_each do |package|
              # create the package id, based on recipient's box
              package[PACKAGE_MATCH_FIELD] =
                case mailbox
                when :inbox, :archive
                  recipient = package['to'].find{ |i| recipient_names.include?(i['name'])}
                  recipient.nil? ? nil : recipient['recipient_delivery_id']
                else # :sent
                  package['delivery_id']
                end
              # add special key
              package['items'] = package['link'].is_a?(Array) ? package['link'].length : 0
              package['metadata'] = package['metadata']['field'].each_with_object({}){ |i, m| m[i['name']] = i['content']}
              # if we look for a specific package
              stop_condition = true if !stop_at_id.nil? && stop_at_id.eql?(package[PACKAGE_MATCH_FIELD])
              # keep only those for the specified recipient
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
            link = box_data['link'].find{ |i| i['rel'].eql?('next')}
            Log.log.debug{"link: #{link}"}
            # no next link
            break if link.nil?
            # replace parameters with the ones from next link
            params = CGI.parse(URI.parse(link['href']).query)
            mailbox_query = params.keys.each_with_object({}){ |i, m| m[i] = params[i].first}
            Log.log.debug{"query: #{mailbox_query}"}
            break if !max_pages.nil? && (mailbox_query['page'].to_i > max_pages)
          end
          return result
        end

        # retrieve transfer spec from pub link for send package
        def send_public_link_to_ts(public_link_url, package_create_params)
          delivery_info = package_create_params['delivery']
          # pub link user
          link_data = self.class.get_link_data(public_link_url)
          if !['external/submissions/new', 'external/dropbox_submissions/new'].include?(link_data[:subpath])
            raise Cli::BadArgument, "pub link is #{link_data[:subpath]}, expecting external/submissions/new"
          end
          create_path = link_data[:subpath].split('/')[0..-2].join('/')
          package_create_params[:passcode] = link_data[:query]['passcode']
          delivery_info[:transfer_type] = 'connect'
          delivery_info[:source_paths_list] = transfer.source_list.join("\r\n")
          api_public_link = Rest.new(base_url: link_data[:base_url])
          # Hum, as this does not always work (only user, but not dropbox), we get the javascript and need hack
          # pkg_created=api_public_link.create(create_path,package_create_params)
          # so extract data from javascript
          package_creation_data = api_public_link.call(
            operation:    'POST',
            subpath:      create_path,
            content_type: Rest::MIME_JSON,
            body:         package_create_params,
            headers:      {'Accept' => 'text/javascript'}
          )[:http].body
          # get arguments of function call
          package_creation_data.delete!("\n") # one line
          package_creation_data.gsub!(/^[^"]+\("\{/, '{') # delete header
          package_creation_data.gsub!(/"\);[^"]+$/, '"') # delete trailer
          package_creation_data.gsub!(/\}", *"/, '},"') # between two arguments
          package_creation_data.gsub!('\\"', '"') # remove protecting quote
          begin
            package_creation_data = JSON.parse("[#{package_creation_data}]")
          rescue JSON::ParserError # => e
            raise Aspera::Error, 'Unexpected response: missing metadata ?'
          end
          return package_creation_data.first
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
            command_pkg = options.get_next_command(%i[send receive list show], aliases: {recv: :receive})
            case command_pkg
            when :show
              delivery_id = instance_identifier
              return Main.result_single_object(mailbox_filtered_entries(stop_at_id: delivery_id).find{ |p| p[PACKAGE_MATCH_FIELD].eql?(delivery_id)})
            when :list
              return Main.result_object_list(mailbox_filtered_entries, fields: [PACKAGE_MATCH_FIELD, 'title', 'items'])
            when :send
              delivery_info = options.get_option(:delivery_info, mandatory: true)
              Aspera.assert_type(delivery_info, Hash, type: Cli::BadArgument){'delivery_info'}
              # actual parameter to faspex API
              package_create_params = {'delivery' => delivery_info}
              public_link_url = options.get_option(:link)
              if public_link_url.nil?
                # authenticated user
                delivery_info['sources'] ||= [{'paths' => []}]
                first_source = delivery_info['sources'].first
                first_source['paths'].concat(transfer.source_list)
                source_id = instance_identifier(as_option: :remote_source) do |field, value|
                  Aspera.assert(field.eql?('name'), type: Cli::BadArgument){'only name as selector, or give id'}
                  source_list = api_v3.read('source_shares')['items']
                  self.class.get_source_id_by_name(value, source_list)
                end
                first_source['id'] = source_id.to_i unless source_id.nil?
                pkg_created = api_v3.create('send', package_create_params)
                if first_source.key?('id')
                  # no transfer spec if remote source: handled by faspex
                  return {data: [pkg_created['links']['status']], type: :value_list, name: 'link'}
                end
                raise Cli::BadArgument, 'expecting one session exactly' if pkg_created['xfer_sessions'].length != 1
                transfer_spec = pkg_created['xfer_sessions'].first
                # use source from cmd line, this one only contains destination (already in dest root)
                transfer_spec.delete('paths')
              else # public link
                transfer_spec = send_public_link_to_ts(public_link_url, package_create_params)
              end
              # Log.dump(:transfer_spec,transfer_spec)
              return Main.result_transfer(transfer.start(transfer_spec))
            when :receive
              link_url = options.get_option(:link)
              # list of faspex ID/URI to download
              pkg_id_uri = nil
              skip_ids_data = []
              skip_ids_persistency = nil
              case link_url
              when nil # usual case: no link
                if options.get_option(:once_only, mandatory: true)
                  skip_ids_persistency = PersistencyActionOnce.new(
                    manager: persistency,
                    data:    skip_ids_data,
                    id:      IdGenerator.from_list([
                      'faspex_recv',
                      options.get_option(:url, mandatory: true),
                      options.get_option(:username, mandatory: true),
                      options.get_option(:box, mandatory: true).to_s
                    ])
                  )
                end
                # get command line parameters
                delivery_id = instance_identifier
                Aspera.assert(!delivery_id.empty?){'empty id'}
                recipient = options.get_option(:recipient)
                if delivery_id.eql?(SpecialValues::ALL)
                  pkg_id_uri = mailbox_filtered_entries.map{ |i| {id: i[PACKAGE_MATCH_FIELD], uri: self.class.get_fasp_uri_from_entry(i, raise_no_link: false)}}
                elsif delivery_id.eql?(SpecialValues::INIT)
                  Aspera.assert(skip_ids_persistency){'Only with option once_only'}
                  skip_ids_persistency.data.clear.concat(mailbox_filtered_entries.map{ |i| {id: i[PACKAGE_MATCH_FIELD]}})
                  skip_ids_persistency.save
                  return Main.result_status("Initialized skip for #{skip_ids_persistency.data.count} package(s)")
                elsif !recipient.nil? && recipient.start_with?('*')
                  found_package_link = mailbox_filtered_entries(stop_at_id: delivery_id).find{ |p| p[PACKAGE_MATCH_FIELD].eql?(delivery_id)}['link'].first['href']
                  raise "Not Found. Dropbox and Workgroup packages can use the link option with #{Transfer::Uri::SCHEME}" if found_package_link.nil?
                  pkg_id_uri = [{id: delivery_id, uri: found_package_link}]
                else
                  # TODO: delivery id is the right one if package was receive by workgroup
                  endpoint =
                    case options.get_option(:box, mandatory: true)
                    when :inbox, :archive then'received'
                    when :sent then 'sent'
                    end
                  entry_xml = api_v3.call(operation: 'GET', subpath: "#{endpoint}/#{delivery_id}", headers: {'Accept' => 'application/xml'})[:http].body
                  package_entry = XmlSimple.xml_in(entry_xml, {'ForceArray' => true})
                  pkg_id_uri = [{id: delivery_id, uri: self.class.get_fasp_uri_from_entry(package_entry)}]
                end
              when /^#{Transfer::Uri::SCHEME}:/o
                pkg_id_uri = [{id: 'package', uri: link_url}]
              else
                link_data = self.class.get_link_data(link_url)
                if !link_data[:subpath].start_with?(PUB_LINK_EXTERNAL_MATCH)
                  raise Cli::BadArgument, "Pub link is #{link_data[:subpath]}. Expecting #{PUB_LINK_EXTERNAL_MATCH}"
                end
                # NOTE: unauthenticated API (authorization is in url params)
                api_public_link = Rest.new(base_url: link_data[:base_url])
                package_creation_data = api_public_link.call(
                  operation: 'GET',
                  subpath:   link_data[:subpath],
                  headers:   {'Accept' => 'application/xml'},
                  query:     {passcode: link_data[:query]['passcode']}
                )
                if !package_creation_data[:http].body.start_with?('<?xml ')
                  Environment.instance.open_uri(link_url)
                  raise Cli::Error, 'Unexpected response: package not found ?'
                end
                package_entry = XmlSimple.xml_in(package_creation_data[:http].body, {'ForceArray' => false})
                Log.dump(:package_entry, package_entry)
                transfer_uri = self.class.get_fasp_uri_from_entry(package_entry)
                pkg_id_uri = [{id: package_entry['id'], uri: transfer_uri}]
              end
              # prune packages already downloaded
              # TODO : remove ids from skip not present in inbox to avoid growing too big
              # skip_ids_data.select!{|id|pkg_id_uri.select{|p|p[:id].eql?(id)}}
              pkg_id_uri.reject!{ |i| skip_ids_data.include?(i[:id])}
              Log.dump(:pkg_id_uri, pkg_id_uri)
              return Main.result_status('no new package') if pkg_id_uri.empty?
              result_transfer = []
              pkg_id_uri.each do |id_uri|
                if id_uri[:uri].nil?
                  # skip package with no link: empty or content deleted
                  statuses = [:success]
                else
                  transfer_spec = Transfer::Uri.new(id_uri[:uri]).transfer_spec
                  # NOTE: only external users have token in Transfer::Uri::SCHEME link !
                  if !transfer_spec.key?('token')
                    sanitized = id_uri[:uri].gsub('&', '&amp;')
                    xml_payload =
                      %Q(<?xml version="1.0" encoding="UTF-8"?><url-list xmlns="http://schemas.asperasoft.com/xml/url-list"><url href="#{sanitized}"/></url-list>)
                    transfer_spec['token'] = api_v3.call(
                      operation:    'POST',
                      subpath:      'issue-token',
                      query:        {'direction' => 'down'},
                      content_type: Rest::MIME_TEXT,
                      body:         xml_payload,
                      headers:      {'Accept' => Rest::MIME_TEXT, 'Content-Type' => 'application/vnd.aspera.url-list+xml'}
                    )[:http].body
                  end
                  transfer_spec['direction'] = Transfer::Spec::DIRECTION_RECEIVE
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
            command_source = options.get_next_command(%i[list info node])
            source_list = api_v3.read('source_shares')['items']
            case command_source
            when :list
              return Main.result_object_list(source_list)
            else # :info :node
              source_id = instance_identifier do |field, value|
                Aspera.assert(field.eql?('name'), type: Cli::BadArgument){'only name as selector, or give id'}
                self.class.get_source_id_by_name(value, source_list)
              end.to_i
              selected_source = source_list.find{ |i| i['id'].eql?(source_id)}
              raise BadArgument, 'No such source' if selected_source.nil?
              source_name = selected_source['name']
              source_hash = options.get_option(:storage, mandatory: true)
              # check value of option
              Aspera.assert_type(source_hash, Hash, type: Cli::Error){'storage option'}
              source_hash.each do |name, storage|
                Aspera.assert_type(storage, Hash, type: Cli::Error){"storage '#{name}'"}
                [KEY_NODE, KEY_PATH].each do |key|
                  Aspera.assert(storage.key?(key), type: Cli::Error){"storage '#{name}' must have a '#{key}'"}
                end
              end
              if !source_hash.key?(source_name)
                raise Cli::Error, "No such storage in config file: \"#{source_name}\" in [#{source_hash.keys.join(', ')}]"
              end
              source_info = source_hash[source_name]
              Log.dump(:source_info, source_info)
              case command_source
              when :info
                return Main.result_single_object(source_info)
              when :node
                node_config = ExtendedValue.instance.evaluate(source_info[KEY_NODE])
                Log.log.debug{"node=#{node_config}"}
                Aspera.assert_type(node_config, Hash, type: Cli::Error){source_info[KEY_NODE]}
                api_node = Rest.new(
                  base_url: node_config['url'],
                  auth:     {
                    type:     :basic,
                    username: node_config['username'],
                    password: node_config['password']
                  }
                )
                command = options.get_next_command(Node::COMMANDS_FASPEX)
                return Node.new(**init_params, api: api_node, prefix_path: source_info[KEY_PATH]).execute_action(command)
              end
            end
          when :me
            my_info = api_v3.read('me')
            return Main.result_single_object(my_info)
          when :dropbox
            command_pkg = options.get_next_command([:list])
            case command_pkg
            when :list
              dropbox_list = api_v3.read('dropboxes')
              return Main.result_object_list(dropbox_list['items'], fields: %w[name id description can_read can_write])
            end
          when :v4
            command = options.get_next_command(%i[package dropbox dmembership workgroup wmembership user metadata_profile])
            case command
            when :dropbox
              return entity_execute(api: api_v4, entity: 'admin/dropboxes', display_fields: %w[id e_wg_name e_wg_desc created_at])
            when :dmembership
              return entity_execute(api: api_v4, entity: 'dropbox_memberships')
            when :workgroup
              return entity_execute(api: api_v4, entity: 'admin/workgroups', display_fields: %w[id e_wg_name e_wg_desc created_at])
            when :wmembership
              return entity_execute(api: api_v4, entity: 'workgroup_memberships')
            when :user
              return entity_execute(api: api_v4, entity: 'users', display_fields: %w[id name first_name last_name])
            when :metadata_profile
              return entity_execute(api: api_v4, entity: 'metadata_profiles')
            when :package
              pkg_box_type = options.get_next_command([:users])
              pkg_box_id = instance_identifier
              return entity_execute(api: api_v4, entity: "#{pkg_box_type}/#{pkg_box_id}/packages")
            end
          when :address_book
            result = api_v3.read('address-book', {'format' => 'json', 'count' => 100_000})
            formatter.display_status("users: #{result['itemsPerPage']}/#{result['totalResults']}, start:#{result['startIndex']}")
            users = result['entry']
            # add missing entries
            users.each do |u|
              unless u['emails'].nil?
                email = u['emails'].find{ |i| i['primary'].eql?('true')}
                u['email'] = email['value'] unless email.nil?
              end
              if u['email'].nil?
                Log.log.warn{"Skip user without email: #{u}"}
                next
              end
              u['first_name'], u['last_name'] = u['displayName'].split(' ', 2)
              u['x'] = true
            end
            return Main.result_object_list(users)
          when :login_methods
            login_meths = api_v3.call(operation: 'GET', subpath: 'login/new', headers: {'Accept' => 'application/xrds+xml'})[:http].body
            login_methods = XmlSimple.xml_in(login_meths, {'ForceArray' => false})
            return Main.result_object_list(login_methods['XRD']['Service'])
          end
        end
      end
    end
  end
end
