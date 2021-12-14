module Aspera
  # Manage secrets in a simple Hash
  class Secrets
    def initialize(values)
      raise "values shall be Hash" unless values.is_a?(Hash)
      @all_secrets=values
    end

    def get_secret(options)
      raise "options shall be Hash" unless options.is_a?(Hash)
      raise "options shall have username" unless options.has_key?(:username)
      return @all_secrets[options[:username]]
    end
  end
end
