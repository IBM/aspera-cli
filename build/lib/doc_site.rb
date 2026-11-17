# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../lib/aspera/markdown'
require 'pathname'
require 'yaml'

# Sources of the documentation web site (MkDocs), made from the manual in a single Markdown file.
# A search engine, or an AI, finds a page about one subject better than one very large page:
# - one page per section of level 2 of the manual, named after the anchor of the section
# - anchors of headings are the ones of the manual on GitHub, so that links are the same
# - internal links (`#anchor`) lead to the page of the anchor
# - GitHub alerts (`> [!NOTE]`) are converted to admonitions
# - `llms.txt` at the root of the site lists the pages
# - the home page is the `README.md` of the project (landing page), if given, instead of the beginning of the manual
class DocSite
  # Page of the beginning of the manual, before the first section
  INDEX = 'index.md'
  # Level of the headings that start a page
  PAGE_LEVEL = 2
  # GitHub alert => admonition of MkDocs
  ADMONITIONS = {'NOTE' => 'note', 'TIP' => 'tip', 'IMPORTANT' => 'info', 'WARNING' => 'warning', 'CAUTION' => 'danger', 'INFO' => 'info'}.freeze
  ALERT_START = /^(?<indent>\s*)> \[!(?<type>[A-Z]+)\]\s*$/
  # Internal link of the manual: `](#anchor)`
  INTERNAL_LINK = /\]\(#(?<anchor>[^)\s]+)\)/
  # Local image: `![text](file)`
  LOCAL_IMAGE = /!\[[^\]]*\]\((?<file>[^):]+)\)/
  # Link to a file of the repository, relative to the manual: `[text](../Gemfile)` (not an image, not a URL, not an anchor)
  REPO_LINK = /(?<!!)\[(?<text>[^\]]*)\]\((?<path>(?![a-z]+:|#)[^)\s]+)\)/
  # Link of an image (e.g. badge) to a file of the repository: `[![text](image)](../Gemfile)`
  REPO_IMAGE_LINK = /(?<image>\[!\[[^\]]*\]\([^)\s]+\)\])\((?<path>(?![a-z]+:|#)[^)\s]+)\)/
  # Comments of the manual are for its editors, and for tools (lint, PDF)
  HTML_COMMENT = /^<!--.*?-->\n/m
  private_constant :INDEX, :PAGE_LEVEL, :ADMONITIONS, :ALERT_START, :INTERNAL_LINK, :LOCAL_IMAGE, :REPO_LINK, :REPO_IMAGE_LINK, :HTML_COMMENT

  # Title of the home page, if made from `README.md`
  HOME_TITLE = 'Home'
  private_constant :HOME_TITLE

  # A page of the site
  # @!attribute base [Pathname] folder of the source of the page: relative images and links
  # @!attribute repo [String]   URL of this folder in the repository
  Page = Struct.new(:file, :title, :lines, :base, :repo)

  # @param manual   [Pathname] Manual, Markdown, single file
  # @param llms     [Pathname] `llms.txt` of the project
  # @param site_url [String]   URL of the site, ends with `/`
  # @param repo_url [String]   URL of the folder of the manual in the repository, for links to other files
  # @param home     [Pathname, nil] `README.md` of the project, for the home page
  # @param home_url [String, nil]   URL of the folder of `home` in the repository
  def initialize(manual:, llms:, site_url:, repo_url:, home: nil, home_url: nil)
    @repo_url = repo_url
    @home = home
    @home_url = home_url
    @manual = manual
    @llms = llms
    @site_url = site_url
    @pages = []
    # anchor of the manual => file of the page that has it
    @anchor_page = {}
    split
    home_page unless @home.nil?
  end

  # @return [Array<Hash>] Navigation of the site, for `nav` of `mkdocs.yml`
  def nav
    @pages.map { |page| {page.title => page.file} }
  end

  # Write the pages, the images they use, `llms.txt`, `llms-full.txt` and `robots.txt`
  # @param folder [Pathname] Folder of the sources of the site (`docs_dir` of MkDocs)
  def write(folder)
    @pages.each do |page|
      text = admonitions(page.lines).join
      # links to files of the repository first: links between pages are then relative paths too
      text = text.gsub(REPO_IMAGE_LINK) { "#{Regexp.last_match[:image]}(#{File.join(page.repo, Regexp.last_match[:path])})" }
      text = text.gsub(REPO_LINK) { "[#{Regexp.last_match[:text]}](#{File.join(page.repo, Regexp.last_match[:path])})" }
      text = text.gsub(INTERNAL_LINK) { "](#{link_target(Regexp.last_match[:anchor], page.file)})" }
      text.scan(LOCAL_IMAGE).flatten.uniq.each do |image|
        (folder / image).dirname.mkpath
        (folder / image).write((page.base / image).binread)
      end
      (folder / page.file).write(text)
    end
    (folder / 'llms.txt').write(llms_text)
    (folder / 'llms-full.txt').write(@manual.read)
    (folder / 'robots.txt').write("User-agent: *\nAllow: /\nSitemap: #{@site_url}sitemap.xml\n")
  end

  private

  # Split the manual into pages, with explicit anchors on headings
  def split
    content = @manual.read.gsub(HTML_COMMENT, '')
    seen = {}
    page = nil
    Aspera::Markdown.each_line_with_heading(content) do |line, heading|
      if heading.nil?
        page&.lines&.push(line)
        next
      end
      level = heading[1].length
      title = heading[2].strip
      anchor = github_anchor(title, seen)
      if level <= PAGE_LEVEL
        page = Page.new(level < PAGE_LEVEL ? INDEX : "#{anchor}.md", title.delete('`'), [], @manual.dirname, @repo_url)
        @pages.push(page)
      end
      raise "Heading before the title of the manual: #{title}" if page.nil?
      @anchor_page[anchor] = page.file
      # A page starts with a heading of level 1
      page_level = page.file.eql?(INDEX) ? level : level - PAGE_LEVEL + 1
      page.lines.push("#{'#' * page_level} #{title} { ##{anchor} }\n")
    end
  end

  # Replace the beginning of the manual (title) with `README.md`: links to the manual become internal links.
  # The lines of the beginning of the manual, after its title, are kept after it.
  def home_page
    index = @pages.find { |page| page.file.eql?(INDEX) }
    raise 'Manual has no title' if index.nil?
    manual_url = Regexp.escape(File.join(@repo_url, @manual.basename.to_s))
    text = @home.read.gsub(HTML_COMMENT, '').gsub(/\]\(#{manual_url}#(?<anchor>[^)\s]+)\)/) { "](##{Regexp.last_match[:anchor]})" }
    index.lines = text.lines + index.lines.drop(1)
    index.title = HOME_TITLE
    index.base = @home.dirname
    index.repo = @home_url
  end

  # Anchor of a heading, as generated by GitHub: links of the manual use it
  # (not `Aspera::Markdown.heading_to_anchor`, which merges consecutive hyphens)
  # @param title [String] Text of the heading
  # @param seen  [Hash]   Count of anchors already used, updated
  # @return [String] Anchor
  def github_anchor(title, seen)
    anchor = title.downcase.gsub(/[^\p{Word}\- ]/u, '').tr(' ', '-')
    count = seen[anchor].to_i
    seen[anchor] = count + 1
    count.zero? ? anchor : "#{anchor}-#{count}"
  end

  # @param anchor [String] Anchor of the manual
  # @param file   [String] File of the page that has the link
  # @return [String] Target of the link in the site
  def link_target(anchor, file)
    target = @anchor_page[anchor]
    raise "Unknown anchor in manual: #{anchor}" if target.nil?
    target.eql?(file) ? "##{anchor}" : "#{target}##{anchor}"
  end

  # Convert GitHub alerts to admonitions: the lines of the quote are the content, indented
  # @param lines [Array<String>] Lines of a page
  # @return [Array<String>] Lines with admonitions
  def admonitions(lines)
    result = []
    quote = nil
    lines.each do |line|
      if (start = line.match(ALERT_START))
        quote = /^#{Regexp.escape(start[:indent])}> ?/
        result.push("#{start[:indent]}!!! #{ADMONITIONS.fetch(start[:type])}\n", "\n")
      elsif quote && line.match?(quote)
        result.push("#{line[/^\s*/]}    #{line.sub(quote, '')}")
      else
        quote = nil
        result.push(line)
      end
    end
    result
  end

  # @return [String] `llms.txt` of the site: the one of the project, followed by the pages of the manual
  def llms_text
    pages = @pages.map do |page|
      "- [#{page.title}](#{@site_url}#{page.file.eql?(INDEX) ? '' : "#{page.file.delete_suffix('.md')}/"})"
    end
    "#{@llms.read}\n## Manual, one page per section\n\n#{pages.join("\n")}\n\n## Optional\n\n- [Manual in a single file](#{@site_url}llms-full.txt)\n"
  end
end
