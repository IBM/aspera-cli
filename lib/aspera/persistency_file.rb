require 'json'

module Aspera
  # Persist data on file system
  class PersistencyFile
    FILE_FIELD_SEPARATOR='_'
    FILE_SUFFIX='.txt'
    WINDOWS_PROTECTED_CHAR=%r{[/:"<>\\\*\?]}
    private_constant :FILE_FIELD_SEPARATOR,:FILE_SUFFIX,:WINDOWS_PROTECTED_CHAR

    @@persistency_folder='.'
    def self.default_folder=(val);@@persistency_folder=val;end

    # @param :data     Mandatory data to persist (assume array by default)
    # @param :ids      Mandatory identifiers
    # @param :delete   Optional  delete persistency condition
    # @param :parse    Optional  parse method (default to JSON)
    # @param :format   Optional  dump method (default to JSON)
    # @param :merge    Optional  merge data from file to current data
    def initialize(options)
      Log.log.debug("persistency: #{options}")
      raise "options shall be Hash" unless options.is_a?(Hash)
      raise "mandatory :data" if options[:data].nil?
      raise "mandatory :ids (Array)" unless options[:ids].is_a?(Array)
      raise "mandatory 1 element in :ids" unless options[:ids].length >= 1
      # do not re-assign
      @Data=options[:data]
      @persist_category=options[:ids].first
      # by default , at save time, file is deleted if data is nil
      @delete_condition=options[:delete] || lambda{|d|d.empty?}
      @persist_format=options[:format] || lambda {|h| JSON.generate(h)}
      persist_parse=options[:parse] || lambda {|t| JSON.parse(t)}
      persist_merge=options[:merge] || lambda {|current,file| current.concat(file).uniq rescue current}
      identifiers=options[:ids]
      if identifiers[1].is_a?(String) and identifiers[1] =~ URI::ABS_URI
        identifiers=identifiers.clone
        identifiers[1]=URI.parse(identifiers[1]).host
      end
      basename=identifiers.
      join(FILE_FIELD_SEPARATOR).
      downcase.
      gsub(WINDOWS_PROTECTED_CHAR,FILE_FIELD_SEPARATOR)
      #.gsub(/[^a-z]+/,FILE_FIELD_SEPARATOR)
      @persist_filepath=File.join(@@persistency_folder,basename+FILE_SUFFIX)
      Log.log.debug("persistency(#{@persist_category}) = #{@persist_filepath}")
      if File.exist?(@persist_filepath)
        persist_merge.call(@Data,persist_parse.call(File.read(@persist_filepath)))
      else
        Log.log.debug("no persistency exists: #{@persist_filepath}")
      end
    end

    def save
      if @delete_condition.call(@Data)
        Log.log.debug("empty data, deleting: #{@persist_filepath}")
        File.delete(@persist_filepath) if File.exist?(@persist_filepath)
      else
        Log.log.debug("saving: #{@persist_filepath}")
        File.write(@persist_filepath,@persist_format.call(@Data))
      end
    end

    def flush_all
      # TODO
      persist_files=Dir[File.join(@@persistency_folder,@persist_category+'*'+FILE_SUFFIX)]
      persist_files.each do |filepath|
        File.delete(filepath)
      end
      return persist_files
    end
  end
end
