# for older rubies
unless Hash.method_defined?(:dig)
  class Hash
    def dig(*path)
      path.inject(self) do |location, key|
        location.respond_to?(:keys) ? location[key] : nil
      end
    end
  end
end

class ::Hash
  def deep_merge(second)
    merge(second){|_key,v1,v2|Hash===v1&&Hash===v2 ? v1.deep_merge(v2) : v2}
  end

  def deep_merge!(second)
    merge!(second){|_key,v1,v2|Hash===v1&&Hash===v2 ? v1.deep_merge!(v2) : v2}
  end
end

unless Hash.method_defined?(:symbolize_keys)
  class Hash
    def symbolize_keys
      return each_with_object({}){|(k,v),memo| memo[k.to_sym] = v; }
    end
  end
end
