require 'asperalm/fasp/installation'
require 'asperalm/log'
require 'asperalm/rest_call_error'
require 'json'

module Asperalm
  # builds a meaningful error message from known formats in Aspera products
  class RestErrorAnalyzer
    attr_reader :messages
    attr_reader :request
    attr_reader :result
    def initialize(req,res)
      # multiple error messages can be found
      @messages  = []
      @request   = req
      @result    = res
      @isSuccess = @result[:http].code.start_with?('2')
      # handlers called only failure and valid JSON result found
      return if @isSuccess or !@result[:data].is_a?(Hash)
      # analyze errors from provided handlers
      RestErrorAnalyzer::ERROR_HANDLERS.each do |handler|
        begin
          handler.call(self)
        rescue => e
          Log.log.error("ERROR in handler:\n#{e.backtrace}")
        end
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
    # for logging and tracing : collect error descriptions
    # @param myself the RestErrorAnalyzer object
    # @param type a string describing type of exception, for logging purpose
    # @param msg one error message  to add to list
    def self.add_error(myself,type,msg)
      myself.messages.push(msg)
      # log error for further analysis
      exc_log_file=File.join(Fasp::Installation.instance.config_folder,"exceptions.log")
      if File.exist?(exc_log_file)
        File.open(exc_log_file,"a+") do |f|
          f.write("\n=#{type}=====\n#{myself.request.method} #{myself.request.path}\n#{myself.result[:http].code}\n#{JSON.generate(myself.result[:data])}\n#{myself.messages.join("\n")}")
        end
      end
    end

    # simplest way to add a handler:
    # check that key exists and is string under sdpecified path (hash)
    def self.add_simple_handler(type,key,path=[])
      add_handler do |myself|
        # dig and find sub entry correspopnding to path in deep hash
        error_data=path.inject(myself.result[:data]) { |subhash, key| subhash.respond_to?(:keys) ? subhash[key] : nil }
        add_error(myself,type,error_data[key]) if error_data.is_a?(Hash) and error_data[key].is_a?(String)
      end
    end
    add_simple_handler("Type 1",'user_message',['error'])
    add_simple_handler("Type 2",'description',['error'])
    add_simple_handler("Type 3",'internal_message',['error'])
    add_simple_handler("Type 4",'error')
    add_simple_handler("Type 5",'error_description')
    add_handler do |myself|
      if myself.result[:data]['message'].is_a?(String)
        add_error(myself,"Type 6",myself.result[:data]['message'])
        # add other fields as info
        myself.result[:data].each do |k,v|
          add_error(myself,"Type 6","#{k}: #{v}") unless k.eql?('message')
        end
      end
    end
    add_handler do |myself|
      if myself.result[:data]['errors'].is_a?(Hash)
        myself.result[:data]['errors'].each do |k,v|
          add_error(myself,"Type 7","#{k}: #{v}")
        end
      end
    end
    # call to upload_setup and download_setup of node api
    add_handler do |myself|
      d_t_s=myself.result[:data]['transfer_specs']
      if d_t_s.is_a?(Array)
        d_t_s.each do |res|
          r_err=res['transfer_spec']['error']
          if r_err.is_a?(Hash)
            add_error(myself,"T8:node: *_setup","#{r_err['code']}: #{r_err['reason']}: #{r_err['user_message']}")
          end
        end
      end
    end
    add_simple_handler("T9:IBM cloud IAM",'errorMessage')
    add_simple_handler("T10:faspex v4",'user_message')
    add_simple_handler("T11:AoC",'message')

    # raises a RestCallError exception if http result code is not 2XX
    def raiseOnError()
      if !@result[:http].code.start_with?('2')
        self.class.add_error(self,"Type Generic",@result[:http].message) if @messages.empty?
        raise RestCallError.new(@request,@result[:http],@messages.join("\n"))
      end
    end
  end
end
