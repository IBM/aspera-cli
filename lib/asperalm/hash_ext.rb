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
    self.merge(second){|key,v1,v2|Hash===v1&&Hash===v2 ? v1.deep_merge(v2) : v2}
  end

  def deep_merge!(second)
    self.merge!(second){|key,v1,v2|Hash===v1&&Hash===v2 ? v1.deep_merge!(v2) : v2}
  end
end
