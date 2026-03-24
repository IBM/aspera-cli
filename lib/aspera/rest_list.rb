# frozen_string_literal: true

module Aspera
  # List and lookup methods for Rest
  # To be included in classes inheriting Rest that require those methods.
  module RestList
    # `max`: special query parameter: max number of items for list command
    MAX_ITEMS = 'max'
    # `pmax`: special query parameter: max number of pages for list command
    MAX_PAGES = 'pmax'

    # Query entity by general search (read with parameter `q`)
    #
    # @param subpath     [String] Path of entity in API
    # @param search_name [String] Name of searched entity
    # @param query       [Hash]   Optional additional search query parameters
    # @returns [Hash] A single entity matching the search, or an exception if not found or multiple found
    def lookup_by_name(subpath, search_name, query: nil)
      query = {} if query.nil?
      # returns entities matching the query (it matches against several fields in case insensitive way)
      matching_items = read(subpath, query.merge({'q' => search_name}))
      # API style: {totalcount:, ...} cspell: disable-line
      matching_items = matching_items[subpath] if matching_items.is_a?(Hash)
      Aspera.assert_type(matching_items, Array)
      case matching_items.length
      when 1 then return matching_items.first
      when 0 then raise EntityNotFound, %Q{No such #{subpath}: "#{search_name}"}
      else
        # multiple case insensitive partial matches, try case insensitive full match
        # (anyway AoC does not allow creation of 2 entities with same case insensitive name)
        name_matches = matching_items.select{ |i| i['name'].casecmp?(search_name)}
        case name_matches.length
        when 1 then return name_matches.first
        when 0 then raise %Q(#{subpath}: Multiple case insensitive partial match for: "#{search_name}": #{matching_items.map{ |i| i['name']}} but no case insensitive full match. Please be more specific or give exact name.)
        else raise "Two entities cannot have the same case insensitive name: #{name_matches.map{ |i| i['name']}}"
        end
      end
    end

    # Get a (full or partial) list of all entities of a given type with query: offset/limit
    # @param entity    [String,Symbol] API endpoint of entity to list
    # @param items_key [String]        Key in the result to get the list of items (Default: same as `entity`)
    # @param query     [Hash,nil]      Additional query parameters
    # @return [Array<(Array<Hash>, Integer)>] items, total_count
    def list_entities_limit_offset_total_count(
      entity:,
      items_key: nil,
      query: nil
    )
      entity = entity.to_s if entity.is_a?(Symbol)
      items_key = entity.split('/').last if items_key.nil?
      query = {} if query.nil?
      Aspera.assert_type(entity, String)
      Aspera.assert_type(items_key, String)
      Aspera.assert_type(query, Hash)
      Log.log.debug{"list_entities t=#{entity} k=#{items_key} q=#{query}"}
      result = []
      offset = 0
      max_items = query.delete(MAX_ITEMS)
      remain_pages = query.delete(MAX_PAGES)
      # Merge default parameters, by default 100 per page
      query = {'limit'=> PER_PAGE_DEFAULT}.merge(query)
      total_count = nil
      loop do
        query['offset'] = offset
        page_result = read(entity, query)
        Aspera.assert_type(page_result[items_key], Array)
        result.concat(page_result[items_key])
        # Reach the limit set by user ?
        if !max_items.nil? && (result.length >= max_items)
          result = result.slice(0, max_items)
          break
        end
        total_count ||= page_result['total_count']
        break if result.length >= total_count
        remain_pages -= 1 unless remain_pages.nil?
        break if remain_pages == 0
        offset += page_result[items_key].length
        RestParameters.instance.spinner_cb.call("#{result.length} / #{total_count || '?'}")
      end
      RestParameters.instance.spinner_cb.call(action: :success)
      return result, total_count
    end

    # Lookup an entity id from its name.
    # Uses query `q` if `query` is `:default` and `field` is `name`.
    # @param entity    [String] Type of entity to lookup, by default it is the path, and it is also the field name in result
    # @param value     [String] Value to lookup
    # @param field     [String] Field to match, by default it is `'name'`
    # @param items_key [String] Key in the result to get the list of items (override entity)
    # @param query     [Hash]   Additional query parameters (Default: `:default`)
    def lookup_entity_by_field(entity:, value:, field: 'name', items_key: nil, query: :default)
      if query.eql?(:default)
        Aspera.assert(field.eql?('name')){'Default query is on name only'}
        query = {'q'=> value}
      end
      lookup_entity_generic(entity: entity, field: field, value: value){list_entities_limit_offset_total_count(entity: entity, items_key: items_key, query: query).first}
    end

    # Lookup entity by field and value.
    # Extracts a single result from the list returned by the block.
    #
    # @param entity [String] Type of entity to lookup (path, and by default it is also the field name in result)
    # @param value  [String] Value to match against the field.
    # @param field  [String] Field to match in the hashes (defaults to 'name').
    # @yield []              A mandatory block that returns an Array of Hashes.
    # @return [Hash] The unique matching object.
    # @raise  [Cli::BadIdentifier] If 0 or >1 matches are found.
    def lookup_entity_generic(entity:, value:, field: 'name')
      Aspera.assert(block_given?)
      found = yield
      Aspera.assert_array_all(found, Hash)
      found = found.select{ |i| i[field].eql?(value)}
      return found.first if found.length.eql?(1)
      raise Cli::BadIdentifier.new(entity, value, field: field, count: found.length)
    end
    PER_PAGE_DEFAULT = 1000
    private_constant :PER_PAGE_DEFAULT
    module_function :lookup_entity_generic
  end
end
