require 'singleton'

module Aspera
  class OauthCache
    include Singleton
    private
    # definition of token cache filename
    TOKEN_FILE_PREFIX='token'
    TOKEN_FILE_SEPARATOR='_'
    TOKEN_FILE_SUFFIX='.txt'
    WINDOWS_PROTECTED_CHAR=%r{[/:"<>\\\*\?]}
    private_constant :TOKEN_FILE_PREFIX,:TOKEN_FILE_SEPARATOR,:TOKEN_FILE_SUFFIX,:WINDOWS_PROTECTED_CHAR
    def initialize
      # change this with persistency_folder
      @token_cache_folder='.'
      # key = string unique identifier
      # value = ruby structure of data of returned value
      @token_cache={}
    end

    public

    def persistency_folder; @token_cache_folder;end

    def persistency_folder=(v); @token_cache_folder=v;end

    # delete cached tokens
    def flush_tokens
      tokenfiles=Dir[File.join(@token_cache_folder,TOKEN_FILE_PREFIX+'*'+TOKEN_FILE_SUFFIX)]
      tokenfiles.each do |filepath|
        File.delete(filepath)
      end
      return tokenfiles
    end

    def self.ids_to_id(parts)
      Log.dump("parts",parts)
      result=parts.
      join(TOKEN_FILE_SEPARATOR).
      gsub(WINDOWS_PROTECTED_CHAR,TOKEN_FILE_SEPARATOR). # remove windows forbidden chars
      gsub('.',TOKEN_FILE_SEPARATOR)  # keep dot for extension only (nicer)
      Log.log.debug("id=#{result}")
      raise "at least one non empty id required" if result.empty?
      return result
    end

    # get location of cache for token, using some unique filename
    def token_filepath(identifier)
      filepath=File.join(@token_cache_folder,TOKEN_FILE_PREFIX+TOKEN_FILE_SEPARATOR+identifier+TOKEN_FILE_SUFFIX)
      Log.log.debug("token path=#{filepath}")
      return filepath
    end

    def get(identifier)
      # if first time, try to read from file
      if !@token_cache.has_key?(identifier)
        token_state_file=token_filepath(identifier)
        if File.exist?(token_state_file) then
          Log.log.info("reading token from file cache: #{token_state_file}")
          # returns decoded data
          @token_cache[identifier]=JSON.parse(File.read(token_state_file))
        end
      end
      return @token_cache[identifier]
    end

    # save token data in memory and disk cache
    def save(identifier,token_data)
      Log.log.info("saving #{token_data}")
      @token_cache[identifier]=token_data
      token_state_file=token_filepath(identifier)
      File.write(token_state_file,token_data.to_json)
      Log.log.info("new saved token is #{@token_cache[identifier]['access_token']}")
      return nil
    end

    def discard(identifier)
      Log.log.info("deleting cache file and memory for token")
      token_state_file=token_filepath(identifier)
      File.delete(token_state_file) if File.exist?(token_state_file)
      @token_cache.delete(identifier)
    end
  end
end
