module Aspera
  # Manage secrets in CLI using secure way (encryption, wallet, etc...)
  class Secrets
    attr_accessor :default_secret,:all_secrets
    def initialize()
      @default_secret=nil
      @all_secrets={}
    end

    def get_secret(id=nil,mandatory=true)
      secret=@default_secret || @all_secrets[id]
      raise "please provide secret for #{id}" if secret.nil? and mandatory
      return secret
    end

    def get_secrets
      return @all_secrets
    end
  end
end
