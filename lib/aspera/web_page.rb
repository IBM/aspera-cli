# frozen_string_literal: true

require 'erb'

module Aspera
  # HTML pages of embedded web servers, sharing a layout: style and branding.
  # The ERB template of each page is the content of the card of the layout, with its own variables.
  module WebPage
    # ERB template of the layout, with variables `title` and `content`
    LAYOUT_PATH = File.join(__dir__, 'web_page.html.erb')
    # Context of templates: variables as methods, and `h` to escape HTML
    class Context
      include ERB::Util

      # @param variables [Hash{Symbol => Object}] Variables of the template
      def initialize(variables)
        variables.each { |name, value| define_singleton_method(name) { value } }
      end

      # @param template_path [String] Path of the ERB template
      # @return [String] Result of the template
      def render(template_path)
        ERB.new(File.read(template_path)).result(template_binding)
      end

      private

      # @return [Binding] Binding without local variables, so that they do not hide template variables
      def template_binding = binding
    end
    private_constant :LAYOUT_PATH, :Context

    class << self
      # @param template_path [String] Path of the ERB template of the content of the page
      # @param title         [String] Title of the page
      # @param variables     [Hash]   Variables of the template of the content
      # @return [String] HTML page
      def render(template_path, title:, **variables)
        content = Context.new(variables).render(template_path)
        Context.new(title: title, content: content).render(LAYOUT_PATH)
      end
    end
  end
end
