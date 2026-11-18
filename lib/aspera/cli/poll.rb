# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative 'error'
require_relative 'result'
require_relative 'formatter'
require_relative '../units/duration'
require_relative '../assert'
require 'json'
require 'stringio'

module Aspera
  module Cli
    class Result
      # Result of a read-only command executed with option `poll`: the command is executed when the result is displayed,
      # once or several times, and each result is displayed according to `show`.
      # The command is not executed by `Runner#run_with_result` (MCP server): only by `Runner#run`, which displays the result.
      class Poll < Result
        # Parameters of option `poll`, see schema `PollOptions`
        PARAMETERS = %i[interval max timeout until show errors].freeze
        # Values of parameter `show`
        SHOW_MODES = %i[change each last].freeze
        # Values of parameter `errors`
        ERROR_MODES = %i[fail retry].freeze
        # Default time between runs, in seconds
        DEFAULT_INTERVAL = 5

        # Standard output that keeps the terminal properties of the real one (`tty?`, `winsize`),
        # so that a result is rendered as on the terminal, and compared with the previous one before it is displayed.
        class Capture < StringIO
          # @param terminal [IO] The real standard output
          def initialize(terminal)
            super(+'')
            @terminal = terminal
          end

          def tty? = @terminal.tty?
          def isatty = tty?
          def winsize = @terminal.winsize
        end
        private_constant :PARAMETERS, :SHOW_MODES, :ERROR_MODES, :DEFAULT_INTERVAL, :Capture

        class << self
          # Truth of a JMESPath value: `false`, `null`, empty string, empty list and empty object are false
          # @param value [Object] Value of a JMESPath expression
          # @return [Boolean]
          def truthy?(value)
            return false if value.nil? || value.eql?(false)
            return !value.empty? if value.is_a?(String) || value.is_a?(Array) || value.is_a?(Hash)
            true
          end

          # Data of a result, as seen by a JMESPath expression of `--out.query`: JSON values (keys and objects like `Time` become strings)
          # @param result [Result] Result of a command
          # @return [Object] JSON view of the data
          def json_view(result)
            data =
              case result
              when Result::Empty then []
              when Result::Special then nil
              else result.data
              end
            # A scalar is used as is: it may be binary (e.g. an image)
            return data.is_a?(Symbol) ? data.to_s : data unless data.is_a?(Hash) || data.is_a?(Array)
            JSON.parse(JSON.generate(data))
          end
        end

        # Parameters are checked before the first run.
        # @param parameters [Hash]  Value of option `poll`, see schema `PollOptions`
        # @param format     [Symbol] Output format (`--format`)
        # @raise [Cli::BadArgument] if a parameter is invalid
        def initialize(parameters, format: nil)
          super()
          Aspera.assert_type(parameters, Hash, type: BadArgument) { 'poll' }
          parameters = parameters.transform_keys(&:to_sym)
          unknown = parameters.keys - PARAMETERS
          raise BadArgument, "poll: unknown parameter: #{unknown.join(', ')}, expecting: #{PARAMETERS.join(', ')}" unless unknown.empty?
          # Nagios plugins exit after the first result
          raise BadArgument, 'poll: not with format nagios' if format.eql?(:nagios)
          @interval = seconds(parameters.fetch(:interval, DEFAULT_INTERVAL), :interval)
          @max = parameters[:max]
          Aspera.assert(@max.nil? || (@max.is_a?(Integer) && @max.positive?), type: BadArgument) { "poll.max: expecting a positive integer, not #{@max.inspect}" }
          @timeout = parameters[:timeout].nil? ? nil : seconds(parameters[:timeout], :timeout)
          @until = parameters[:until]
          Aspera.assert_type(@until, String, NilClass, type: BadArgument) { 'poll.until' }
          Formatter.check_jmespath(@until, 'poll.until') unless @until.nil?
          @show = parameters.fetch(:show, SHOW_MODES.first).to_s.to_sym
          Aspera.assert_values(@show, SHOW_MODES, type: BadArgument) { 'poll.show' }
          @errors = parameters.fetch(:errors, ERROR_MODES.first).to_s.to_sym
          Aspera.assert_values(@errors, ERROR_MODES, type: BadArgument) { 'poll.errors' }
          # Set by the dispatcher: executes the command, and returns its result
          @action = nil
        end

        # @param action [Proc] Executes the command, and returns its result
        attr_writer :action

        # Execute the command (once or several times), and display results.
        # `Ctrl-C` stops polling: the last result is displayed with `show=last`, then `Interrupt` is raised again.
        # @param formatter [Formatter] Displays each result, with formatting options
        # @raise [Cli::PollConditionNotMet] if `until` is not true after the last run
        # @raise [StandardError] error of a run: with `errors=fail`, or of the last run with `errors=retry`
        # @return [nil]
        def format(formatter)
          Aspera.assert(!@action.nil?) { 'poll: no action' }
          start = clock
          run = 0
          met = false
          previous = nil
          last = nil
          interrupted = false
          # Error of the last run, with `errors=retry`
          error = nil
          begin
            loop do
              run += 1
              error = nil
              begin
                result = @action.call
              rescue StandardError => e
                raise if @errors.eql?(:fail)
                error = e
                status(formatter, "poll: run #{run}#{"/#{@max}" unless @max.nil?} #{timestamp} error: #{e.message}")
              end
              if error.nil?
                Aspera.assert_type(result, Result) { 'result of command' }
                met = self.class.truthy?(evaluate(formatter, result)) unless @until.nil?
                output = render(formatter, result)
                case @show
                when :each then display(formatter, run, output)
                when :change then display(formatter, run, output) unless output.eql?(previous)
                when :last then last = [run, output]
                end
                previous = output
              end
              break if met || (!@max.nil? && run >= @max)
              wait = @interval
              unless @timeout.nil?
                remaining = start + @timeout - clock
                break unless remaining.positive?
                wait = [wait, remaining].min
              end
              pause(wait)
            end
          rescue Interrupt
            interrupted = true
          end
          display(formatter, *last) unless last.nil?
          raise Interrupt if interrupted
          raise error unless error.nil?
          status(formatter, "poll: condition met at run #{run}") if met
          raise PollConditionNotMet, "condition not met after #{run} run#{'s' unless run.eql?(1)}: #{@until}" unless @until.nil? || met
          nil
        end

        private

        # @param value [Numeric, String] Duration: number of seconds, or text, e.g. `30s`, `5m`, `1h 30m` (see `Units::Duration`)
        # @param name  [Symbol]          Parameter name, for errors
        # @return [Integer] Seconds
        def seconds(value, name)
          Aspera.assert_type(value, Numeric, String, type: BadArgument) { "poll.#{name}" }
          value = Units::Duration.new(value).to_unit('s')
          Aspera.assert(!value.negative?, type: BadArgument) { "poll.#{name}: must not be negative" }
          value
        rescue ParameterError => e
          raise BadArgument, "poll.#{name}: #{e.message}"
        end

        # @param formatter [Formatter] Applies `--select`
        # @param result    [Result]    Result of a run
        # @return [Object] Value of expression `until` on the result data, after `--select`, before `--fields` and `--out.query`
        def evaluate(formatter, result)
          data = self.class.json_view(result)
          data = formatter.filter_columns_on_select(data) if data.is_a?(Array) && data.all?(Hash)
          JMESPath.search(@until, data)
        rescue JMESPath::Errors::Error => e
          raise BadArgument, "poll.until: JMESPath: #{e.message}"
        end

        # @param formatter [Formatter] Displays the result
        # @param result    [Result]    Result of a run
        # @return [String] Display of the result
        def render(formatter, result)
          terminal = $stdout
          $stdout = Capture.new(terminal)
          formatter.display_results(result)
          $stdout.string
        ensure
          $stdout = terminal
        end

        # Display a status line, and the result, immediately: e.g. for a program that reads the output line by line
        # @param formatter [Formatter] Displays the status line
        # @param run       [Integer]   Run number
        # @param output    [String]    Display of the result
        # @return [nil]
        def display(formatter, run, output)
          status(formatter, "poll: run #{run}#{"/#{@max}" unless @max.nil?} #{timestamp}")
          $stdout.write(output)
          $stdout.flush
          nil
        end

        # @param formatter [Formatter] Displays the status line on `stderr`
        # @param message   [String]    Status line
        # @return [nil]
        def status(formatter, message)
          formatter.display_message(:error, message)
          $stderr.flush
          nil
        end

        # @return [String] Current local time, for status lines
        def timestamp
          Time.now.strftime('%Y-%m-%d %H:%M:%S')
        end

        # @return [Float] Monotonic time, in seconds
        def clock
          ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
        end

        # @param seconds [Numeric] Time to wait
        # @return [nil]
        def pause(seconds)
          sleep(seconds)
          nil
        end
      end
    end
  end
end
