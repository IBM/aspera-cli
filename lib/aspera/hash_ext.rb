# frozen_string_literal: true

class ::Hash
  def deep_merge(second)
    merge(second){|_key,v1,v2|Hash === v1 && Hash === v2 ? v1.deep_merge(v2) : v2}
  end

  def deep_merge!(second)
    merge!(second){|_key,v1,v2|Hash === v1 && Hash === v2 ? v1.deep_merge!(v2) : v2}
  end
end

# in 2.5
unless Hash.method_defined?(:transform_keys)
  class Hash
    def transform_keys
      return each_with_object({}){|(k,v),memo|memo[yield(k)]=v} if block_given?
      raise 'missing block'
    end
  end
end

# rails
unless Hash.method_defined?(:symbolize_keys)
  class Hash
    def symbolize_keys
      return transform_keys(&:to_sym)
    end
  end
end

# rails
unless Hash.method_defined?(:stringify_keys)
  class Hash
    def stringify_keys
      return transform_keys(&:to_s)
    end
  end
end
