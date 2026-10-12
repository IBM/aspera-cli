# frozen_string_literal: true

require 'spec_helper'
require 'aspera/cli/table_fitter'

RSpec.describe(Aspera::Cli::TableFitter) do
  let(:headings) { %w[name description] }
  let(:rows) do
    [
      ['identifier_without_spaces', 'A long description that can be wrapped on several lines to fit in the width'],
      ['short', "First line\nSecond line"]
    ]
  end

  # @return [Array<String>] lines of the rendered table
  def render(width, headings: self.headings, rows: self.rows, style: {})
    described_class.table(headings: headings, rows: rows, style: style, width: width).to_s.lines.map(&:chomp)
  end

  it 'keeps natural width without width' do
    expect(render(nil)).to(eq(Terminal::Table.new(headings: headings, rows: rows).to_s.lines.map(&:chomp)))
  end

  it 'keeps natural width when table fits' do
    expect(render(200)).to(eq(render(nil)))
  end

  it 'wraps text column only, to fit width' do
    lines = render(60)
    expect(lines.map(&:length).max).to(be_between(50, 60))
    expect(lines).to(include(a_string_including('| identifier_without_spaces |')))
    expect(lines.join).to(include('Second line'))
  end

  it 'breaks words longer than the wrapped column' do
    lines = render(40, rows: [['id', "#{'x' * 30} end"]])
    expect(lines.map(&:length).max).to(eq(40))
    expect(lines.join.count('x')).to(eq(30))
  end

  it 'wraps other columns when not enough, preferably after punctuation' do
    lines = render(40)
    expect(lines.map(&:length).max).to(be <= 40)
    expect(lines.grep(/^\|/).map { |line| line.split('|')[1].strip }).to(include('identifier_', 'without_', 'spaces'))
  end

  it 'narrows columns to their minimum when table cannot fit' do
    lines = render(20)
    expect(lines.map(&:length).max).to(be_between(30, 10 + 20 + 7))
    expect(lines).to(include(a_string_starting_with('| identifier |')))
  end

  it 'closes styles at end of line and opens them again on next line' do
    lines = render(30, rows: [['id', "a \e[1m#{'x' * 30}\e[0m b"]]).select { |line| line.include?('x') }
    expect(lines.length).to(eq(2))
    expect(lines).to(all(match(/\e\[1mx+\e\[0m/)))
  end

  it 'takes style into account' do
    lines = render(60, style: {padding_left: 3, border: :unicode_round})
    expect(lines.map { |line| Unicode::DisplayWidth.of(line) }.max).to(be_between(50, 60))
  end

  it 'ignores ANSI escape sequences for width' do
    lines = render(60, rows: [["\e[1mbold\e[0m", rows.first.last]])
    expect(lines.map { |line| Unicode::DisplayWidth.of(Terminal::Table::Util.ansi_escape(line)) }.max).to(be_between(50, 60))
  end
end
