require 'date'

module Asperalm
  class Nagios
    @@LEVELS=[:ok,:warning,:critical,:unknown,:dependent]
    @@ADD_PREFIX='add_'
    @@LEVELS.each_index do |code|
      name="#{@@ADD_PREFIX}#{@@LEVELS[code]}".to_sym
      define_method(name){|comp,msg|@data.push({:code=>code,:comp=>comp,:msg=>msg})}
      public name
    end

    def initialize
      @data=[]
    end
    attr_reader :data

    @@DATE_WARN_OFFSET=2
    @@DATE_CRIT_OFFSET=5

    def check_time_offset( remote_date, component )
      # check date if specified : 2015-10-13T07:32:01Z
      rtime = DateTime.strptime(remote_date)
      diff_time = (rtime - DateTime.now).abs
      diff_disp=diff_time.round(-2)
      Log.log.debug("DATE: #{remote_date} #{rtime} diff=#{diff_disp}")
      msg="offset #{diff_disp} sec"
      if diff_time >= @@DATE_CRIT_OFFSET
        add_critical(component,msg)
      elsif diff_time >= @@DATE_WARN_OFFSET
        add_warning(component,msg)
      else
        add_ok(component,msg)
      end
    end

    def check_product_version( component, product, version )
      add_ok(component,"version #{version}")
      # TODO check on database if latest version
    end

    # translate for display
    def result
      {:type=>:object_list,:data=>@data.map{|i|{'status'=>@@LEVELS[i[:code]].to_s,'component'=>i[:comp],'message'=>i[:msg]}}}
    end

    def self.process(data)
      raise "INTERNAL ERROR, result must be list and not empty" unless data.is_a?(Array) and !data.empty?
      ['status','component','message'].each{|c|raise "INTERNAL ERROR, result must have #{c}" unless data.first.has_key?(c)}
      res_errors = data.select{|s|!s['status'].eql?('ok')}
      # keep only errors in case of problem, other ok are assumed so
      data = res_errors unless res_errors.empty?
      # first is most critical
      data.sort!{|a,b|@@LEVELS.index(a['status'].to_sym)<=>@@LEVELS.index(b['status'].to_sym)}
      # build message: if multiple components: concatenate
      #message = data.map{|i|"#{i['component']}:#{i['message']}"}.join(', ').gsub("\n",' ')
      message = data.map{|i|i['component']}.uniq.map{|comp|comp+':'+data.select{|d|d['component'].eql?(comp)}.map{|d|d['message']}.join(',')}.join(', ').gsub("\n",' ')
      status=data.first['status'].upcase
      # display status for nagios
      puts("#{status} - [#{message}]\n")
      # provide exit code to nagios
      Process.exit(@@LEVELS.index(data.first['status'].to_sym))
    end
  end
end
