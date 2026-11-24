# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0
# cspell:ignore fixedsize nodesep rankdir ranksep

require 'yaml'
require 'json'
require 'open3'
require 'cgi'

# Diagram of the dependencies between plugin bundles: field `depends` of each manifest `plugin.yaml`.
# Written as an uncompressed draw.io document, laid out by Graphviz `dot` (dependent on the left, dependency on the right),
# with edges that follow the splines of `dot` around the boxes.
# `rake doc:plugin_dependencies` writes it, `rake doc:diagrams` exports its images, a spec checks it against the manifests.
module PluginDependencies
  # Name of the diagram (tab of the draw.io document): name of its exported images
  TAB = 'plugin-dependencies'
  # Size of a bundle box, in points (= draw.io pixels)
  BOX_W = 170
  BOX_H = 64
  # A bundle with at least this number of dependents gets a taller box, so that their arrows do not converge on one point
  TALL_FROM = 6
  # Height of such a box per dependent
  HEIGHT_PER_DEPENDENT = 50
  # Room above the graph for the title and the legend
  TOP = 170
  LEFT = 40
  # Colors of a box by kind of bundle
  KINDS = {
    both:     {fill: '#d5e8d4', stroke: '#82b366', text: 'commands and transfer agent'},
    commands: {fill: '#dae8fc', stroke: '#6c8ebf', text: 'commands'},
    agent:    {fill: '#ffe6cc', stroke: '#d79b00', text: 'transfer agent, no command'},
    library:  {fill: '#f5f5f5', stroke: '#666666', text: 'no command, no agent: code for other bundles'}
  }.freeze
  # Color of the arrows to the bundle that most bundles depend on, other arrows
  HUB_EDGE = '#9E9E9E'
  EDGE = '#333333'
  # Points of each cubic segment of an edge used as waypoints (parameter t of the curve)
  SAMPLES = [0.25, 0.5, 0.75, 1.0].freeze

  class << self
    # @param plugins_dir [String] Folder with one folder per bundle, e.g. `lib/aspera/plugins`
    # @return [Array<Hash>] Bundles, sorted by name: `name`, `title`, `depends`, `kind`
    # @raise [RuntimeError] if a bundle depends on an unknown bundle
    def bundles(plugins_dir)
      list = Dir.glob(File.join(plugins_dir, '*', 'plugin.yaml')).sort.map do |file|
        manifest = YAML.safe_load_file(file)
        {
          name:    manifest['name'],
          title:   manifest['title'],
          depends: Array(manifest['depends']),
          kind:    kind(manifest['commands'] ? true : false, !manifest.dig('extensions', 'agent').nil?)
        }
      end
      raise "no plugin.yaml found under #{plugins_dir}" if list.empty?
      names = list.map { |bundle| bundle[:name] }
      list.each do |bundle|
        unknown = bundle[:depends] - names
        raise "#{bundle[:name]}: unknown dependency #{unknown.join(', ')}" unless unknown.empty?
      end
      list
    end

    # @param bundles [Array<Hash>] Bundles, as given by `bundles`
    # @return [Hash] What the diagram shows: `bundles` (name => kind) and `edges` (sorted pairs [dependent, dependency])
    def graph(bundles)
      {
        bundles: bundles.to_h { |bundle| [bundle[:name], bundle[:kind]] },
        edges:   bundles.flat_map { |bundle| bundle[:depends].map { |dependency| [bundle[:name], dependency] } }.sort
      }
    end

    # @param xml [String] Diagram written by `drawio`
    # @return [Hash] What the diagram shows, as `graph`
    def graph_of_drawio(xml)
      kinds = KINDS.to_h { |kind, colors| [colors[:fill], kind] }
      {
        bundles: xml.scan(/<mxCell id="b-([a-z0-9_]+)" [^>]*fillColor=(#[0-9a-f]{6});/).to_h { |name, fill| [name, kinds.fetch(fill)] },
        edges:   xml.scan(/<mxCell id="e-([a-z0-9_]+)-([a-z0-9_]+)" /).sort
      }
    end

    # @param bundles [Array<Hash>] Bundles, as given by `bundles`
    # @return [String] Uncompressed draw.io document
    # @raise [RuntimeError] if Graphviz `dot` fails or is not installed
    def drawio(bundles)
      dependents = bundles.to_h { |bundle| [bundle[:name], bundles.count { |other| other[:depends].include?(bundle[:name]) }] }
      hub = dependents.max_by { |name, count| [count, name] }.first
      layout = dot_layout(bundles, dependents)
      _, _, graph_width, graph_height = layout['bb'].split(',').map(&:to_f)
      # Graphviz point (y up) to draw.io point (y down)
      to_xy = ->(point) { [(LEFT + point[0]).round, (TOP + graph_height - point[1]).round] }
      cells = []
      boxes = {}
      layout['objects'].each do |object|
        # The objects are the subgraph of the last rank (no position), then the nodes
        next unless object.key?('pos')
        bundle = bundles.find { |item| item[:name].eql?(object['name']) }
        raise "unexpected object in the layout: #{object['name']}" if bundle.nil?
        box = box_of(object, to_xy)
        boxes[object['_gvid']] = [bundle[:name], *box]
        cells.concat(box_cells(bundle, *box))
      end
      layout['edges'].each do |edge|
        tail = boxes.fetch(edge['tail'])
        head = boxes.fetch(edge['head'])
        cells.push(edge_cell(edge, tail, head, to_xy, head.first.eql?(hub) ? HUB_EDGE : EDGE))
      end
      cells.concat(legend_cells(hub))
      document(cells, [(LEFT * 2) + graph_width.round, 1100].max, TOP + graph_height.round + 40)
    end

    # Write the diagram of the bundles of a folder
    # @param plugins_dir [String] Folder with one folder per bundle
    # @param out_file    [String] draw.io file to write
    # @return [nil]
    def write(plugins_dir, out_file)
      File.write(out_file, drawio(bundles(plugins_dir)))
      nil
    end

    private

    # @return [Symbol] Kind of a bundle, key of `KINDS`
    def kind(commands, agent)
      return :both if commands && agent
      return :commands if commands
      return :agent if agent
      :library
    end

    # @return [Hash] Layout computed by Graphviz `dot` (JSON output)
    def dot_layout(bundles, dependents)
      dot = +"digraph G {\n  rankdir=LR; nodesep=0.22; ranksep=1.3; splines=true;\n"
      dot << "  node [shape=box, fixedsize=true, width=#{BOX_W / 72.0}, height=#{BOX_H / 72.0}];\n"
      bundles.each { |bundle| dot << %(  "#{bundle[:name]}" [height=#{height(dependents[bundle[:name]]) / 72.0}];\n) }
      bundles.each { |bundle| bundle[:depends].each { |dependency| dot << %(  "#{bundle[:name]}" -> "#{dependency}";\n) } }
      # Bundles without dependency in the last column
      sinks = bundles.select { |bundle| bundle[:depends].empty? }.map { |bundle| %("#{bundle[:name]}") }
      dot << "  { rank=sink; #{sinks.join('; ')}; }\n}\n"
      json, status = Open3.capture2('dot', '-Tjson', stdin_data: dot)
      raise 'Graphviz dot failed' unless status.success?
      JSON.parse(json)
    rescue Errno::ENOENT
      raise 'Graphviz dot is required (e.g. brew install graphviz)'
    end

    # @return [Integer] Height of the box of a bundle with this number of dependents
    def height(dependent_count)
      dependent_count >= TALL_FROM ? dependent_count * HEIGHT_PER_DEPENDENT : BOX_H
    end

    # @return [Array(Integer, Integer, Integer, Integer)] x, y, width, height of a node, in draw.io coordinates
    def box_of(object, to_xy)
      width = (object['width'].to_f * 72).round
      height = (object['height'].to_f * 72).round
      cx, cy = to_xy.call(object['pos'].split(',').map(&:to_f))
      [cx - (width / 2), cy - (height / 2), width, height]
    end

    # @return [Array<String>] Cells of the box of a bundle and of its title
    def box_cells(bundle, x, y, width, height)
      colors = KINDS.fetch(bundle[:kind])
      [
        %(<mxCell id="b-#{bundle[:name]}" value="#{xml_attr(bundle[:name])}" style="rounded=1;arcSize=#{height > BOX_H ? 3 : 12};html=0;fillColor=#{colors[:fill]};strokeColor=#{colors[:stroke]};fontStyle=1;fontSize=13;verticalAlign=top;spacingTop=2;" vertex="1" parent="1"><mxGeometry x="#{x}" y="#{y}" width="#{width}" height="#{height}" as="geometry"/></mxCell>),
        %(<mxCell id="t-#{bundle[:name]}" value="#{xml_attr(wrap(bundle[:title]))}" style="text;html=0;align=center;verticalAlign=middle;fontSize=10;fontColor=#4D4D4D;" vertex="1" connectable="0" parent="b-#{bundle[:name]}"><mxGeometry y="22" width="#{width}" height="#{BOX_H - 24}" as="geometry"/></mxCell>)
      ]
    end

    # @return [String] Cell of an edge, following the B-spline of `dot` (each cubic segment sampled), with fixed ends on the boxes
    def edge_cell(edge, tail, head, to_xy, color)
      tokens = edge['pos'].split
      tip = tokens.find { |token| token.start_with?('e,') }
      spline = tokens.grep_v(/^[es],/).map { |token| token.split(',').map(&:to_f) }
      points = (0...((spline.size - 1) / 3)).flat_map do |index|
        p0, p1, p2, p3 = spline[3 * index, 4]
        SAMPLES.map { |t| bezier(p0, p1, p2, p3, t) }
      end
      start = to_xy.call(spline.first)
      finish = to_xy.call(tip.nil? ? spline.last : tip.delete_prefix('e,').split(',').map(&:to_f))
      exit_x, exit_y = port(tail, start)
      entry_x, entry_y = port(head, finish)
      waypoints = points.map { |point| to_xy.call(point).then { |x, y| %(<mxPoint x="#{x}" y="#{y}"/>) } }.join
      style = "endArrow=block;endFill=1;endSize=5;html=0;curved=1;strokeColor=#{color};strokeWidth=1.3;" \
              "exitX=#{exit_x};exitY=#{exit_y};exitDx=0;exitDy=0;entryX=#{entry_x};entryY=#{entry_y};entryDx=0;entryDy=0;"
      %(<mxCell id="e-#{tail.first}-#{head.first}" style="#{style}" edge="1" parent="1" source="b-#{tail.first}" target="b-#{head.first}"><mxGeometry relative="1" as="geometry"><Array as="points">#{waypoints}</Array></mxGeometry></mxCell>)
    end

    # @return [Array<String>] Cells of the title, the note and the legend of the colors
    def legend_cells(hub)
      note = "Arrow A → B: bundle A depends on bundle B (field `depends` of lib/aspera/plugins/<name>/plugin.yaml). Arrows to #{hub} in gray.\n" \
             'Not shown: the framework (with the built-in plugins config and mcp) and the domain library, which every bundle may use.'
      cells = [
        %(<mxCell id="title" value="#{xml_attr('Plugin bundles: dependencies')}" style="text;html=0;align=left;verticalAlign=top;fontSize=20;fontStyle=1;" vertex="1" parent="1"><mxGeometry x="#{LEFT}" y="20" width="600" height="30" as="geometry"/></mxCell>),
        %(<mxCell id="note" value="#{xml_attr(note)}" style="text;html=0;align=left;verticalAlign=top;fontSize=11;fontColor=#4D4D4D;" vertex="1" parent="1"><mxGeometry x="#{LEFT}" y="56" width="900" height="36" as="geometry"/></mxCell>)
      ]
      KINDS.each_with_index do |(name, colors), index|
        x = LEFT + (index * 250)
        cells.push(%(<mxCell id="legend-#{name}" value="" style="rounded=1;arcSize=12;html=0;fillColor=#{colors[:fill]};strokeColor=#{colors[:stroke]};" vertex="1" parent="1"><mxGeometry x="#{x}" y="112" width="30" height="20" as="geometry"/></mxCell>))
        cells.push(%(<mxCell id="legend-#{name}-text" value="#{xml_attr(wrap(colors[:text], 30))}" style="text;html=0;align=left;verticalAlign=middle;fontSize=11;" vertex="1" parent="1"><mxGeometry x="#{x + 36}" y="104" width="210" height="36" as="geometry"/></mxCell>))
      end
      cells
    end

    # @return [String] The draw.io document with its cells
    def document(cells, width, height)
      <<~XML
        <mxfile host="Electron" type="device">
          <diagram id="#{TAB}" name="#{TAB}">
            <mxGraphModel dx="#{width}" dy="#{height}" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="#{width}" pageHeight="#{height}" math="0" shadow="0">
              <root>
                <mxCell id="0"/>
                <mxCell id="1" parent="0"/>
                #{cells.join("\n          ")}
              </root>
            </mxGraphModel>
          </diagram>
        </mxfile>
      XML
    end

    # @return [Array(Float, Float)] Relative position (0..1) of a point on a box, for the fixed end of an edge
    def port(box, point)
      _, x, y, width, height = box
      [((point[0] - x).to_f / width).clamp(0, 1).round(3), ((point[1] - y).to_f / height).clamp(0, 1).round(3)]
    end

    # @return [Array(Float, Float)] Point of a cubic Bezier curve
    def bezier(p0, p1, p2, p3, t)
      u = 1 - t
      [0, 1].map { |i| (u**3 * p0[i]) + (3 * u**2 * t * p1[i]) + (3 * u * t**2 * p2[i]) + (t**3 * p3[i]) }
    end

    # @return [String] Text broken into lines of at most `width` characters
    def wrap(text, width = 26)
      text.split.each_with_object([+'']) do |word, lines|
        if lines.last.empty? then lines.last << word
        elsif lines.last.length + 1 + word.length <= width then lines.last << ' ' << word
        else lines.push(word.dup)
        end
      end.join("\n")
    end

    # @return [String] Text escaped for an XML attribute, new lines kept
    def xml_attr(text)
      CGI.escapeHTML(text).gsub("\n", '&#10;')
    end
  end
end
