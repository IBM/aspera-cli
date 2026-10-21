# frozen_string_literal: true

require 'spec_helper'
require 'aspera/markdown'

RSpec.describe(Aspera::Markdown) do
  describe '.table' do
    let(:table) { [%w[a b], ['x`x`', 'y|z']] }

    it 'generates a table with separator and escaped pipes, width without backticks' do
      expect(described_class.table(table)).to(eq("| a | b |\n|----|-----|\n| x`x` | y\\|z |"))
    end

    it 'does not modify the provided table' do
      described_class.table(table)
      expect(table).to(eq([%w[a b], ['x`x`', 'y|z']]))
    end
  end

  it 'generates a list' do
    expect(described_class.list(%w[a b])).to(eq("- a\n- b"))
  end

  it 'generates a heading' do
    expect(described_class.heading('Title')).to(eq("# Title\n\n"))
    expect(described_class.heading('Sub', level: 3)).to(eq("### Sub\n\n"))
  end

  it 'generates an admonition' do
    expect(described_class.admonition(%w[l1 l2], type: 'NOTE')).to(eq("> [!NOTE]\n> l1\n> l2\n\n"))
  end

  it 'generates a code block' do
    expect(described_class.code(%w[ls pwd])).to(eq("```shell\nls\npwd\n```\n\n"))
    expect(described_class.code(['a: 1'], type: 'yaml')).to(eq("```yaml\na: 1\n```\n\n"))
  end

  it 'generates inline code and paragraph' do
    expect(described_class.icode('x')).to(eq('`x`'))
    expect(described_class.paragraph('text')).to(eq("text\n\n"))
  end

  describe '.toc and .extract_section' do
    let(:doc) { "# Top\n\nintro\n\n## Sub `code`\n\nbody\n\n## Sub `code`\n\nagain\n\n# Next\n" }

    it 'builds anchors, disambiguating duplicates' do
      expect(described_class.toc(doc).map { |i| i['anchor'] }).to(eq(%w[top sub-code sub-code-1 next]))
    end

    it 'extracts a section until next heading of same level' do
      expect(described_class.extract_section(doc, 'sub-code-1')).to(eq("## Sub `code`\n\nagain\n\n"))
      expect(described_class.extract_section(doc, 'nope')).to(be_nil)
    end

    it 'lists headings up to a level, with the anchors of the whole document' do
      expect(described_class.toc("## Sub\n\n### Detail\n\n## Sub\n", max_level: 2).map { |i| i['anchor'] }).to(eq(%w[sub sub-1]))
    end

    context 'with fenced code blocks' do
      # a fence with an info string does not end a block
      let(:doc) { "# Top\n\n```shell\n# comment\n```ruby\n# still code\n````\n\n## Sub\n\n~~~\n# not a heading\n~~~\n\nend\n\n# Next\n" }

      it 'does not take lines of code blocks as headings' do
        expect(described_class.toc(doc).map { |i| i['title'] }).to(eq(%w[Top Sub Next]))
      end

      it 'keeps code blocks in an extracted section' do
        expect(described_class.extract_section(doc, 'top')).to(eq(doc.sub("# Next\n", '')))
      end
    end
  end
end
