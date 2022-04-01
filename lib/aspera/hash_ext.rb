# frozen_string_literal: true

class ::Hash
  def deep_merge(second)
    merge(second){|_key,v1,v2|Hash === v1 && Hash === v2 ? v1.deep_merge(v2) : v2}
  end

  def deep_merge!(second)
    merge!(second){|_key,v1,v2|Hash === v1 && Hash === v2 ? v1.deep_merge!(v2) : v2}
  end
end

unless Hash.method_defined?(:symbolize_keys)
  class Hash
    def symbolize_keys
      return each_with_object({}){|(k,v),memo| memo[k.to_sym] = v; }
    end
  end
end

unless Hash.method_defined?(:stringify_keys)
  class Hash
    def stringify_keys
      return each_with_object({}){|(k,v),memo| memo[k.to_s] = v }
    end
  end
end
