require 'json'

module Asperalm
  # maintain a list of file_name_parts for packages that have already been downloaded
  class PersistencyFile
    @@FILE_FIELD_SEPARATOR='_'
    @@FILE_SUFFIX='.txt'
    @@WINDOWS_PROTECTED_CHAR=%r{[/:"<>\\\*\?]}

    attr_accessor :data
    # @param prefix
    # @param options[:folder]
    # @param options[:ids]
    # @param options[:url]
    def initialize(prefix,options)
      @is_active = options[:active] || true
      @persist_folder=options[:folder] || '.'
      @persist_prefix=prefix
      @persist_filepath=nil
      # by default , at save time, file is deleted if data is nil
      @delete_condition=options[:delete] || lambda{|d|d.nil?}

      return unless @is_active

      @persist_parse=options[:parse] || lambda {|t| JSON.parse(t)}
      @persist_format=options[:format] || lambda {|d| JSON.generate(d)}
        Log.log.debug(">>> #{options[:ids]} >> #{options[:url]}")
        file_name_parts=options[:ids].clone
        file_name_parts.unshift(URI.parse(options[:url]).host) if options.has_key?(:url)
        file_name_parts.unshift(@persist_prefix)
        basename=file_name_parts.map do |i|
          i.downcase.gsub(@@WINDOWS_PROTECTED_CHAR,@@FILE_FIELD_SEPARATOR)
          #.gsub(/[^a-z]+/,@@FILE_FIELD_SEPARATOR)
        end.join(@@FILE_FIELD_SEPARATOR)
        @persist_filepath=File.join(@persist_folder,basename+@@FILE_SUFFIX)
      Log.log.debug("persistency(#{@persist_prefix}) = #{@persist_filepath}")
      raise "no file defined" if @persist_filepath.nil?
      if File.exist?(@persist_filepath)
        @data=@persist_parse.call(File.read(@persist_filepath))
      else
        Log.log.debug("no persistency exists: #{@persist_filepath}")
        @data=nil
      end
      @data||=options[:default]
    end

    def save
      return unless @is_active
      if @delete_condition.call(@data)
        Log.log.debug("nil data, deleting: #{@persist_filepath}")
        File.delete(@persist_filepath) if File.exist?(@persist_filepath)
      else
        Log.log.debug("saving: #{@persist_filepath}")
        File.write(@persist_filepath,@persist_format.call(@data))
      end
    end

    def flush_all
      # TODO
      persist_files=Dir[File.join(@persist_folder,@persist_prefix+'*'+@@FILE_SUFFIX)]
      persist_files.each do |filepath|
        File.delete(filepath)
      end
      return persist_files
    end
  end
end
