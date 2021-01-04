require 'aspera/log'
require 'aspera/rest_call_error'
require 'singleton'

module Aspera
  # analyze error codes returned by REST calls and raise ruby exception
  class RestErrorAnalyzer
    include Singleton
    attr_accessor :log_file
    # the singleton object is registered with application specific handlers
    def initialize
      # list of handlers
      @error_handlers=[]
      @log_file=nil
      self.add_handler('Type Generic') do |type,context|
        if !context[:response].code.start_with?('2')
          # add generic information
          RestErrorAnalyzer.add_error(context,type,"#{context[:request]['host']} #{context[:response].code} #{context[:response].message}")
        end
      end
    end

    # Use this method to analyze a EST result and raise an exception
    # Analyzes REST call response and raises a RestCallError exception
    # if HTTP result code is not 2XX
    def raiseOnError(req,res)
      context={
        messages: [],
        request:  req,
        response: res[:http],
        data:     res[:data]
      }
      # multiple error messages can be found
      # analyze errors from provided handlers
      # note that there can be an error even if code is 2XX
      @error_handlers.each do |handler|
        begin
          #Log.log.debug("test exception: #{handler[:name]}")
          handler[:block].call(handler[:name],context)
        rescue => e
          Log.log.error("ERROR in handler:\n#{e.message}\n#{e.backtrace}")
        end
      end
      unless context[:messages].empty?
        raise RestCallError.new(context[:request],context[:response],context[:messages].join("\n"))
      end
    end

    # add a new error handler (done at application initialisation)
    # @param name : name of error handler (for logs)
    # @param block : processing of response: takes two parameters: name, context
    # name is the one provided here
    # context is built in method raiseOnError
    def add_handler(name,&block)
      @error_handlers.unshift({name: name, block: block})
    end

    # add a simple error handler
    # check that key exists and is string under specified path (hash)
    # adds other keys as secondary information
    def add_simple_handler(name,*args)
      add_handler(name) do |type,context|
        # need to clone because we modify and same array is used subsequently
        path=args.clone
        #Log.log.debug("path=#{path}")
        # if last in path is boolean it tells if the error is only with http error code or always
        always=[true, false].include?(path.last) ? path.pop : false
        if context[:data].is_a?(Hash) and (!context[:response].code.start_with?('2') or always)
          msg_key=path.pop
          # dig and find sub entry corresponding to path in deep hash
          error_struct=path.inject(context[:data]) { |subhash, key| subhash.respond_to?(:keys) ? subhash[key] : nil }
          if error_struct.is_a?(Hash) and error_struct[msg_key].is_a?(String)
            RestErrorAnalyzer.add_error(context,type,error_struct[msg_key])
            error_struct.each do |k,v|
              next if k.eql?(msg_key)
              RestErrorAnalyzer.add_error(context,"#{type}(sub)","#{k}: #{v}") if [String,Integer].include?(v.class)
            end
          end
        end
      end
    end # add_simple_handler

    # used by handler to add an error description to list of errors
    # for logging and tracing : collect error descriptions (create file to activate)
    # @param context a Hash containing the result context, provided to handler
    # @param type a string describing type of exception, for logging purpose
    # @param msg one error message  to add to list
    def self.add_error(context,type,msg)
      context[:messages].push(msg)
      logfile=instance.log_file
      # log error for further analysis (file must exist to activate)
      if !logfile.nil? and File.exist?(logfile)
        File.open(logfile,'a+') do |f|
          f.write("\n=#{type}=====\n#{context[:request].method} #{context[:request].path}\n#{context[:response].code}\n#{JSON.generate(context[:data])}\n#{context[:messages].join("\n")}")
        end
      end
    end
  end
end
