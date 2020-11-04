require 'asperalm/fasp/installation'
require 'asperalm/log'
require 'asperalm/rest_call_error'
require 'json'

module Asperalm
  # builds a meaningful error message from known formats in Aspera products
  # TODO: probably too monolithic..
  class RestErrorAnalyzer
    attr_reader :messages
    attr_reader :request
    attr_reader :result
    attr_reader :isDataHash
    def initialize(req,res)
      # multiple error messages can be found
      @messages  = []
      @request   = req
      @result    = res
      @isSuccess = @result[:http].code.start_with?('2')
      @isDataHash = @result[:data].is_a?(Hash)
      # analyze errors from provided handlers
      # note that there can be an error even if code is 2XX
      RestErrorAnalyzer::ERROR_HANDLERS.each do |handler|
        begin
          handler.call(self)
        rescue => e
          Log.log.error("ERROR in handler:\n#{e.message}\n#{e.backtrace}")
        end
      end
      if !@isSuccess
        # add generic information
        add_error("Type Generic","#{@request['host']} #{@result[:http].code} #{@result[:http].message}")
      end
    end

    # list of handlers
    # handlers should probably be defined by plugins for modularity
    ERROR_HANDLERS=[]

    #private_constant :ERROR_HANDLERS

    # define error handler, block takes one parameter: the RestErrorAnalyzer object
    def self.add_handler(&block)
      ERROR_HANDLERS.push(block)
    end

    # used by handler to add an error description to list of errors
    # for logging and tracing : collect error descriptions (create file to activate)
    # @param type a string describing type of exception, for logging purpose
    # @param msg one error message  to add to list
    def add_error(type,msg)
      @messages.push(msg)
      # log error for further analysis (file must exist to activate)
      exc_log_file=File.join(Fasp::Installation.instance.config_folder,"exceptions.log")
      if File.exist?(exc_log_file)
        File.open(exc_log_file,"a+") do |f|
          f.write("\n=#{type}=====\n#{@request.method} #{@request.path}\n#{@result[:http].code}\n#{JSON.generate(@result[:data])}\n#{@messages.join("\n")}")
        end
      end
    end

    # check that key exists and is string under sdpecified path (hash)
    # adds other keys as secondary information
    # @param onErrorOnly only if HTTP is not 2XX
    def add_if_simple_error(type,on_err_only,path)
      return if on_err_only and @isSuccess
      return unless @isDataHash
      msg_key=path.pop
      # dig and find sub entry corresponding to path in deep hash
      error_struct=path.inject(@result[:data]) { |subhash, key| subhash.respond_to?(:keys) ? subhash[key] : nil }
      if error_struct.is_a?(Hash) and error_struct[msg_key].is_a?(String)
        add_error(type,error_struct[msg_key])
        error_struct.each do |k,v|
          next if k.eql?(msg_key)
          add_error("#{type}(sub)","#{k}: #{v}") if [String,Integer].include?(v.class)
        end
      end
    end

    # simplest way to add a handler
    def self.add_simple_handler(type,on_err_only,*path)
      add_handler { |myself| myself.add_if_simple_error(type,on_err_only,path) }
    end
    # Faspex: both user_message and internal_message, and code 200
    # example: missing meta data on package creation
    add_simple_handler("Type 1",false,'error','user_message')
    add_simple_handler("Type 2",true,'error','description')
    add_simple_handler("Type 3",true,'error','internal_message')
    # AoC Automation
    add_simple_handler("Type 4",true,'error')
    add_simple_handler("Type 5",true,'error_description')
    add_simple_handler("Type 6",true,'message')
    add_handler do |myself|
      if myself.isDataHash and myself.result[:data]['errors'].is_a?(Hash)
        myself.result[:data]['errors'].each do |k,v|
          myself.add_error("Type 7","#{k}: #{v}")
        end
      end
    end
    # call to upload_setup and download_setup of node api
    add_handler do |myself|
      if myself.isDataHash
        d_t_s=myself.result[:data]['transfer_specs']
        if d_t_s.is_a?(Array)
          d_t_s.each do |res|
            #r_err=res['transfer_spec']['error']
            r_err=res['error']
            if r_err.is_a?(Hash)
              myself.add_error("T8:node: *_setup","#{r_err['code']}: #{r_err['reason']}: #{r_err['user_message']}")
            end
          end
        end
      end
    end
    add_simple_handler("T9:IBM cloud IAM",true,'errorMessage')
    add_simple_handler("T10:faspex v4",true,'user_message')
    add_handler do |myself|
      if myself.isDataHash
        d_t_s=myself.result[:data]['errors']
        if d_t_s.is_a?(Array)
          d_t_s.each do |res|
            r_err=res['message']
            if r_err.is_a?(String)
              myself.add_error("bss graphql",r_err)
            end
          end
        end
      end
    end

    # raises a RestCallError exception if http result code is not 2XX
    def raiseOnError()
      unless @messages.empty?
        raise RestCallError.new(@request,@result[:http],@messages.join("\n"))
      end
    end
  end
end
