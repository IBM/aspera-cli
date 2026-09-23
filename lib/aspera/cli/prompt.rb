# frozen_string_literal: true

require 'io/console'
require 'aspera/assert'

module Aspera
  module Cli
    # Console input
    module Prompt
      # Prompt user for console input
      # @param prompt [String]  prompt string to display
      # @param sensitive [Boolean] whether to hide typed input
      # @return [String] user input stripped of trailing newline
      def prompt_user_input(prompt, sensitive: false)
        return $stdin.getpass("#{prompt}> ") if sensitive
        print("#{prompt}> ")
        line = $stdin.gets
        Aspera.assert_type(line, String) { 'Unexpected end of standard input' }
        line.chomp
      end

      # Prompt user for input in a list of symbols
      # @param prompt [String] prompt to display
      # @param sym_list [Array] list of symbols to select from
      # @return [Symbol] selected symbol
      def prompt_user_input_in_list(prompt, sym_list)
        loop do
          input = prompt_user_input(prompt).to_sym
          return input if sym_list.any? { |a| a.eql?(input) }
          $stderr.puts("No such #{prompt}: #{input}, select one of: #{sym_list.join(', ')}") # rubocop:disable Style/StderrPuts
        end
      end
    end
  end
end
