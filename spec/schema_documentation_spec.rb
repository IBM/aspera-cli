# frozen_string_literal: true

require 'spec_helper'
require 'aspera/schema/reader'
require 'aspera/schema/documentation'

RSpec.describe(Aspera::Schema::Documentation) do
  # Formatter without styling
  let(:formatter) do
    Module.new do
      module_function

      def markdown_text(text) = text.to_s
      def special_format(special) = "<#{special}>"
    end
  end

  let(:schema) do
    Aspera::Schema::Reader.new({
      'required'   => ['name'],
      'properties' => {
        'name'  => {'type' => 'string', 'description' => "Name of the item.\nSecond line."},
        'mode'  => {'type' => 'string', 'description' => 'Mode.', 'enum' => %w[fast slow], 'default' => 'fast', 'example' => 'slow', 'x-deprecation' => 'use speed'},
        'speed' => {'type' => 'integer'},
        'owner' => {'type' => 'object', 'properties' => {'id' => {'type' => 'integer'}}}
      }
    })
  end

  def build(**kwargs) = described_class.new(formatter, schema, **kwargs).build

  # @return [Hash] description of each property, by name
  def descriptions(documentation) = documentation.rows.to_h { |row| [row['name'], row['description']] }

  it 'has the columns name, type and description' do
    expect(build.columns).to(eq(%w[name type description]))
    expect(build.table.first).to(eq(%w[name type description]))
  end

  it 'lists properties sorted, with nested ones' do
    expect(build.rows.map { |row| [row['name'], row['type']] }).to(eq([
      %w[mode String], %w[name String], %w[owner Hash], %w[owner.id Integer], %w[speed Integer]
    ]))
  end

  it 'adds the required line after the description' do
    expect(descriptions(build)['name']).to(eq(['Name of the item.', 'Second line.', 'Required.']))
  end

  it 'adds deprecation, allowed values, default and example lines in order' do
    expect(descriptions(build)['mode']).to(eq(['DEPRECATED: use speed', 'Mode.', 'Allowed values: `fast`, `slow`.', 'Default: `fast`.', 'Example: `slow`.']))
  end

  it 'has no description when there is nothing to describe' do
    expect(build.rows.find { |row| row['name'].eql?('speed') }).not_to(have_key('description'))
  end

  it 'adds the lines of annotate, and hides a property when it returns nil' do
    annotate = ->(node, _formatter) { node['type'].eql?('integer') ? nil : ["(#{node['type']})"] }
    result = descriptions(build(annotate: annotate))
    expect(result.keys).to(eq(%w[mode name owner]))
    expect(result['name']).to(eq(['Name of the item.', 'Second line.', 'Required.', '(string)']))
    expect(result['owner']).to(eq(['(object)']))
  end

  it 'inserts extra columns before the description' do
    documentation = build(extra_columns: {'kind' => ->(node, _formatter) { node['type'][0] }})
    expect(documentation.columns).to(eq(%w[name type kind description]))
    expect(documentation.table[1]).to(eq(['mode', 'String', 's', descriptions(documentation)['mode']]))
  end

  it 'formats name and type as code' do
    expect(build(code_highlight: true).rows.first.slice('name', 'type')).to(eq({'name' => '`mode`', 'type' => '`String`'}))
  end
end
