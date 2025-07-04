# frozen_string_literal: true

class ::Hash
  def deep_merge(second)
    merge(second){ |_key, v1, v2| v1.is_a?(Hash) && v2.is_a?(Hash) ? v1.deep_merge(v2) : v2}
  end

  def deep_merge!(second)
    merge!(second){ |_key, v1, v2| v1.is_a?(Hash) && v2.is_a?(Hash) ? v1.deep_merge!(v2) : v2}
  end

  def deep_do(memory=nil, &block)
    each do |key, value|
      if value.is_a?(Hash)
        value.deep_do(memory, &block)
      else
        yield(self, key, value, memory)
      end
    end
  end
end

# Exists in Rails
unless Hash.method_defined?(:symbolize_keys)
  class Hash
    def symbolize_keys
      return transform_keys(&:to_sym)
    end
  end
end

# Exists in Rails
unless Hash.method_defined?(:stringify_keys)
  class Hash
    def stringify_keys
      return transform_keys(&:to_s)
    end
  end
end
