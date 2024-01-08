# frozen_string_literal: true

require 'aspera/log'
require 'aspera/assert'
require 'date'

module Aspera
  class Nagios
    # nagios levels
    LEVELS = %i[ok warning critical unknown dependent].freeze
    ADD_PREFIX = 'add_'
    # date offset levels
    DATE_WARN_OFFSET = 2
    DATE_CRIT_OFFSET = 5
    private_constant :LEVELS, :ADD_PREFIX, :DATE_WARN_OFFSET, :DATE_CRIT_OFFSET

    # add methods to add nagios error levels, each take component name and message
    LEVELS.each_index do |code|
      name = "#{ADD_PREFIX}#{LEVELS[code]}".to_sym
      define_method(name){|comp, msg|@data.push({code: code, comp: comp, msg: msg})}
    end

    class << self
      # process results of a analysis and display status and exit with code
      def process(data)
        assert_type(data, Array)
        assert(!data.empty?){'data is empty'}
        %w[status component message].each do |c|
          assert(data.first.key?(c)){"result must have #{c}"}
        end
        res_errors = data.reject{|s|s['status'].eql?('ok')}
        # keep only errors in case of problem, other ok are assumed so
        data = res_errors unless res_errors.empty?
        # first is most critical
        data.sort!{|a, b|LEVELS.index(a['status'].to_sym) <=> LEVELS.index(b['status'].to_sym)}
        # build message: if multiple components: concatenate
        # message = data.map{|i|"#{i['component']}:#{i['message']}"}.join(', ').gsub("\n",' ')
        message = data
          .map{|i|i['component']}
          .uniq
          .map{|comp|comp + ':' + data.select{|d|d['component'].eql?(comp)}.map{|d|d['message']}.join(',')}
          .join(', ')
          .tr("\n", ' ')
        status = data.first['status'].upcase
        # display status for nagios
        puts("#{status} - [#{message}]\n")
        # provide exit code to nagios
        Process.exit(LEVELS.index(data.first['status'].to_sym))
      end
    end

    attr_reader :data

    def initialize
      @data = []
    end

    # compare remote time with local time
    def check_time_offset(remote_date, component)
      # check date if specified : 2015-10-13T07:32:01Z
      remote_time = DateTime.strptime(remote_date)
      diff_time = (remote_time - DateTime.now).abs
      diff_rounded = diff_time.round(-2)
      Log.log.debug{"DATE: #{remote_date} #{remote_time} diff=#{diff_rounded}"}
      msg = "offset #{diff_rounded} sec"
      if diff_time >= DATE_CRIT_OFFSET
        add_critical(component, msg)
      elsif diff_time >= DATE_WARN_OFFSET
        add_warning(component, msg)
      else
        add_ok(component, msg)
      end
    end

    def check_product_version(component, _product, version)
      add_ok(component, "version #{version}")
      # TODO: check on database if latest version
    end

    # translate for display
    def result
      raise 'missing result' if @data.empty?
      {type: :object_list, data: @data.map{|i|{'status' => LEVELS[i[:code]].to_s, 'component' => i[:comp], 'message' => i[:msg]}}}
    end
  end
end
