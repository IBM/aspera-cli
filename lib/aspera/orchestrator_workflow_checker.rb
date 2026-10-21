# frozen_string_literal: true

require 'psych'
require 'rexml/document'
require 'stringio'
require 'zlib'
require 'rubygems/package'

module Aspera
  # Check of an Orchestrator workflow file (`.yml`) or package (`.wkf`), before import.
  #
  # Orchestrator 4.1.6 does not validate the graph on import (`import_workflow`, `import_with_constraints`): an invalid workflow is imported,
  # then fails to publish, or at run time. These checks follow the rules of the designer (`Whiteboard#parse_workflow`).
  # With the specifications of plugins (`plugins.yml` of the plugin documentation), action templates and inputs of steps are also checked:
  # attributes and their values, required inputs, inputs and outputs that the plugin does not have with its template.
  # Not checked: availability of plugins on the server.
  #
  # The interface is that of a REST operation, so that it can be replaced by a call to Orchestrator when one exists:
  # - request: the fields of `import_workflow`: `file_name` (`import_file_name`) and `content` (`import_file`, bytes),
  #   and the specifications of plugins (`specs`), that Orchestrator would not need
  # - response: a Hash (JSON compatible)
  #   `valid`:     `true` if there is no issue with severity `error`
  #   `file_name`: name of the checked file
  #   `issues`:    list of Hash
  #     `severity`: `error` (the workflow will not import, publish or run correctly) or `warning`
  #     `code`:     stable identifier of the rule, for programs, e.g. `graph.step_orphan`
  #     `file`:     file of the package where the issue is (absent for a single `.yml` file)
  #     `path`:     where in the file, e.g. `graph/Step[Say hello]`
  #     `message`:  description for humans
  #
  # The file is parsed without instantiating Ruby objects.
  class OrchestratorWorkflowChecker
    ERROR = 'error'
    WARNING = 'warning'
    # Columns of tables `workflows` and `whiteboards` (Orchestrator 4.1.6), and attributes ignored by the import
    WORKFLOW_ATTRIBUTES = %w[
      id name portable_id created_by folder_id generated_from revision_id label run_as source_revision comments description tags templates
      max_running cleanup_after_days purge_after_days user_lock locked_by created_at updated_at global_variables hide_workflow
    ].freeze
    WHITEBOARD_ATTRIBUTES = %w[id created_by revision_id workflow_id error_free revisions_log xml_export created_at updated_at].freeze
    VALUE_TYPES = %w[string int float flag date array hash object pwd attachment].freeze
    # Element 6 (plugin versions) is informational: Orchestrator 4.1.6 only reads elements 1 to 5
    ELEMENT_COUNTS = [5, 6].freeze
    TRUE_VALUES = %w[true 1 t].freeze
    UNNAMED = ['', 'undefined', 'null'].freeze
    SUCCESS_STATUSES = %w[complete true].freeze
    BOOLEAN_TEXT = %w[true false].freeze
    STEP_CHILDREN = %w[Inputs Outputs].freeze
    PARAMETER_MAPPINGS = %w[parameter global].freeze
    # Columns of every action template, besides those of the plugin
    TEMPLATE_COLUMNS = %w[id name comments created_at updated_at].freeze
    # Texts that the database layer (ActiveRecord) reads as false
    FALSE_VALUES = %w[false 0 f off].freeze
    INTEGER_TYPES = %w[integer bigint].freeze
    # Template attribute with Ruby code that computes the inputs or the outputs: they are then unknown
    SPEC_CODE = {inputs: 'inputs_spec_code', outputs: 'outputs_spec_code'}.freeze
    # Note of a plugin specification: some inputs or outputs come from the template, other than through declared lists
    PARTLY_DEFINED = {inputs: /\AInputs are partly defined/, outputs: /\AOutputs are partly defined/}.freeze
    # Placeholder that creates a required input: <%= variable %>
    PLACEHOLDER = /<%=\s*([A-Za-z_]\w*)\s*%>/
    # Elements of a step that a `Map_to` of type `output` gives as attributes (in lower case)
    STEP_IDENTITY = %w[Step_name Step_type Action_id].freeze
    private_constant :WORKFLOW_ATTRIBUTES, :WHITEBOARD_ATTRIBUTES, :VALUE_TYPES, :ELEMENT_COUNTS, :TRUE_VALUES, :UNNAMED, :SUCCESS_STATUSES,
      :BOOLEAN_TEXT, :STEP_CHILDREN, :PARAMETER_MAPPINGS, :TEMPLATE_COLUMNS, :FALSE_VALUES, :INTEGER_TYPES, :SPEC_CODE, :PARTLY_DEFINED, :PLACEHOLDER,
      :STEP_IDENTITY

    class << self
      # @param file_name [String] Name of the file, ending with `yml` or `wkf`
      # @param content   [String] Bytes of the file
      # @param specs     [Hash, nil] Specifications of plugins (`plugins.yml`), to check templates and inputs of steps, or nil
      # @return [Hash] Response, see class description
      def check(file_name:, content:, specs: nil)
        checker = new(file_name, specs)
        checker.run(content)
        {
          'valid'     => checker.issues.none? { |issue| issue['severity'].eql?(ERROR) },
          'file_name' => file_name,
          'issues'    => checker.issues
        }
      end
    end

    attr_reader :issues

    # @param file_name [String] Name of the file
    # @param specs     [Hash, nil] Specifications of plugins: class name => attributes, inputs, outputs
    def initialize(file_name, specs = nil)
      @file_name = file_name
      @specs = specs
      @issues = []
      # file of the package being checked
      @member = nil
      # attributes of the action templates of the workflow being checked, by key <StepType>__<N>
      @template_attributes = {}
    end

    # @param content [String] Bytes of the file
    def run(content)
      case File.extname(@file_name)
      when '.yml' then check_yaml(content)
      when '.wkf' then check_package(content)
      else add(ERROR, 'file.extension', 'file', "extension must be yml or wkf: #{@file_name}")
      end
    end

    private

    def add(severity, code, path, message)
      @issues.push({'severity' => severity, 'code' => code, 'file' => @member, 'path' => path, 'message' => message}.compact)
    end

    # @param content [String] Bytes of a `.wkf` file: gzipped tar with a manifest (list of files, the first one is the main workflow)
    def check_package(content)
      files = {}
      begin
        Zlib::GzipReader.wrap(StringIO.new(content)) do |gzip|
          Gem::Package::TarReader.new(gzip) do |tar|
            tar.each { |entry| files[entry.full_name] = entry.read if entry.file? }
          end
        end
      rescue Zlib::Error, Gem::Package::Error => e
        return add(ERROR, 'package.archive', 'file', "not a gzipped tar archive: #{e.message}")
      end
      manifest = files.keys.find { |name| File.basename(name).match?(/\AWorkflow_.*\.txt\z/) }
      return add(ERROR, 'package.manifest_missing', 'file', 'no manifest file (Workflow_*.txt) in package') if manifest.nil?
      list = Psych.safe_load(files[manifest])
      return add(ERROR, 'package.manifest_invalid', manifest, 'manifest must be a list of file names') unless list.is_a?(Array) && !list.empty? && list.all?(String)
      list.each_with_index do |name, index|
        member = files.find { |key, _| File.basename(key).eql?(File.basename(name)) }&.last
        next add(ERROR, 'package.file_missing', manifest, "file listed but not in package: #{name}") if member.nil?
        # sub-workflows are checked as the main workflow; remote nodes and nested packages are not
        next unless name.end_with?('.yml') && (index.zero? || File.basename(name).start_with?('Workflow_'))
        @member = File.basename(name)
        check_yaml(member)
      end
      @member = nil
    rescue Psych::Exception => e
      add(ERROR, 'package.manifest_invalid', manifest.to_s, "invalid manifest: #{e.message}")
    end

    # @param content [String] Bytes of a workflow file
    def check_yaml(content)
      text = content.dup.force_encoding(Encoding::UTF_8)
      return add(ERROR, 'yaml.encoding', 'file', 'file is not UTF-8') unless text.valid_encoding?
      begin
        root = Psych.parse_stream(text).children.first&.root
      rescue Psych::SyntaxError => e
        return add(ERROR, 'yaml.invalid', 'file', "invalid YAML: #{e.message}")
      end
      return add(ERROR, 'yaml.empty', 'file', 'empty file') if root.nil?
      return add(ERROR, 'yaml.not_list', 'file', 'a workflow file is a YAML list of elements') unless root.is_a?(Psych::Nodes::Sequence)
      @plain = text.lines.none? { |line| line.match?(/^ *concise_attributes:/) }
      @template_attributes = {}
      check_layout(text) if @plain
      elements = root.children
      add(ERROR, 'yaml.element_count', 'file', "expected #{ELEMENT_COUNTS.join(' or ')} elements (workflow, whiteboard, templates, dependencies, packed dependencies, plugin versions), found #{elements.size}") unless ELEMENT_COUNTS.include?(elements.size)
      return if elements.size < 2
      workflow = check_attributes(elements[0], 'Workflow', 'workflow', WORKFLOW_ATTRIBUTES)
      add(ERROR, 'workflow.name_missing', 'workflow', 'attribute name is missing') if workflow['name'].to_s.strip.empty?
      whiteboard = check_attributes(elements[1], 'Whiteboard', 'whiteboard', WHITEBOARD_ATTRIBUTES)
      add(ERROR, 'whiteboard.error_free', 'whiteboard', 'error_free is not true: the workflow cannot be published') unless TRUE_VALUES.include?(whiteboard['error_free'].to_s.downcase)
      templates = elements.size > 2 ? check_templates(elements[2]) : []
      elements[3..4]&.each_with_index do |element, index|
        add(ERROR, 'dependencies.not_map', "element #{index + 4}", 'must be a map') unless element.is_a?(Psych::Nodes::Mapping)
      end
      if whiteboard['xml_export'].to_s.strip.empty?
        add(ERROR, 'whiteboard.xml_missing', 'whiteboard', 'attribute xml_export is missing')
      else
        check_graph(whiteboard['xml_export'], templates)
      end
      check_dependencies(elements[3], elements[4]) if elements.size > 4
    end

    # Plain format is converted by Orchestrator line by line: each element starts with a dash at column 0
    def check_layout(text)
      count = text.lines.count { |line| line.match?(/^- /) }
      return if ELEMENT_COUNTS.include?(count)
      add(ERROR, 'yaml.layout', 'file', "plain format: each element must start with '- ' at column 0 (#{ELEMENT_COUNTS.join(' or ')} expected), found #{count} such lines")
    end

    # @return [Hash{String=>Psych::Nodes::Node}] Keys and values of a mapping
    def pairs(node)
      return {} unless node.is_a?(Psych::Nodes::Mapping)
      node.children.each_slice(2).to_h { |key, value| [key.respond_to?(:value) ? key.value : nil, value] }
    end

    def scalar(node)
      node.is_a?(Psych::Nodes::Scalar) ? node.value : nil
    end

    # @return [Hash{String=>String}] Attributes of a workflow, a whiteboard or a template, in plain or Rails format
    def attributes(node)
      content = pairs(node)
      if content.key?('concise_attributes')
        content['concise_attributes'].children.to_h do |item|
          item_pairs = pairs(item)
          [scalar(item_pairs['name']), scalar(item_pairs['value_before_type_cast'])]
        end
      else
        inner = content['attributes']
        (inner.is_a?(Psych::Nodes::Mapping) ? pairs(inner) : content.except('attributes', 'new_record', 'active_record_yaml_version')).transform_values { |value| scalar(value) }
      end
    end

    def check_attributes(node, klass, path, known)
      unless node.is_a?(Psych::Nodes::Mapping) && node.tag.eql?("!ruby/object:#{klass}")
        add(ERROR, "#{path}.type", path, "element must be a map tagged !ruby/object:#{klass}")
        return {}
      end
      attributes(node).tap do |attrs|
        attrs.each_key { |name| add(WARNING, "#{path}.attribute_unknown", path, "unknown attribute: #{name} (the import may fail)") unless known.include?(name) }
      end
    end

    # @return [Array<String>] Keys of the action templates
    def check_templates(node)
      return [] unless node.is_a?(Psych::Nodes::Mapping)
      pairs(node).filter_map do |key, template|
        path = "templates/#{key}"
        match = key.to_s.match(/\A(.+)__(\d+)\z/)
        if match.nil?
          add(ERROR, 'template.key', path, "key must be <StepType>__<N>: #{key}")
        elsif !template.respond_to?(:tag) || !template.tag.eql?("!ruby/object:#{match[1]}")
          add(ERROR, 'template.tag', path, "value must be tagged !ruby/object:#{match[1]}")
        else
          check_boolean_values(path, template) if @plain
          @template_attributes[key] = attributes(template)
          check_template_attributes(path, match[1], @template_attributes[key]) unless @specs.nil?
        end
        key
      end
    end

    # In plain format, a blank attribute is dropped, and false is blank
    def check_boolean_values(path, template)
      attributes(template).each do |name, value|
        add(WARNING, 'template.boolean', path, "#{name} is #{value}: write 1 or 0, false is dropped in plain format") if BOOLEAN_TEXT.include?(value)
      end
    end

    def check_dependencies(listed, packed)
      return unless listed.is_a?(Psych::Nodes::Mapping) && packed.is_a?(Psych::Nodes::Mapping)
      external = pairs(listed).values.flat_map { |list| list.is_a?(Psych::Nodes::Sequence) ? list.children : [] }
      return if external.empty? || !packed.children.empty?
      names = external.map do |dep|
        fields = pairs(dep)
        "#{scalar(fields[':entity'] || fields['entity'])} #{scalar(fields[':id_value'] || fields['id_value'])}".strip
      end
      add(WARNING, 'dependencies.external', 'dependencies', "uses entities not included in the file, they must exist on the server: #{names.uniq.join(', ')}")
    end

    def text_of(element, name)
      element.elements[name]&.text&.strip
    end

    def check_graph(xml, templates)
      begin
        root = REXML::Document.new(xml).root
      rescue REXML::ParseException => e
        return add(ERROR, 'graph.xml_invalid', 'xml_export', "invalid XML: #{e.message.lines.first&.strip}")
      end
      return add(ERROR, 'graph.xml_invalid', 'xml_export', 'no XML root element') if root.nil?
      terminals = %w[Start End Fail Error].to_h { |name| [name, root.get_elements(name)] }
      terminals.each do |name, nodes|
        add(ERROR, 'graph.terminal_count', "graph/#{name}", "#{name} must be present once, found #{nodes.size}") unless nodes.size.eql?(1)
      end
      steps = root.get_elements('Steps/Step')
      add(ERROR, 'graph.no_step', 'graph', 'at least one Step is required') if steps.empty?
      ids = (terminals.values.flatten + steps).map { |node| node.attributes['id'] }
      (ids.tally.select { |_, count| count > 1 }.keys + ids.compact.select(&:empty?)).each do |id|
        add(ERROR, 'graph.id_not_unique', 'graph', "node id must be unique and not empty: '#{id}'")
      end
      check_steps(steps, templates)
      closing = terminals.values_at('End', 'Fail', 'Error').flatten
      (closing + steps).each { |node| check_node(node, ids) }
      check_branches(closing, steps)
      check_parameters(root, steps)
      check_step_interfaces(steps) unless @specs.nil?
    end

    def node_path(node)
      node.name.eql?('Step') ? "graph/Step[#{text_of(node, 'Step_name')}]" : "graph/#{node.name}"
    end

    def check_node(node, ids)
      path = node_path(node)
      factor = text_of(node, 'Synch_factor')
      if factor.nil? || !factor.match?(/\A-?\d+\z/)
        add(ERROR, 'graph.synch_factor', path, 'Synch_factor is missing or not an integer')
      elsif factor.to_i.negative?
        add(ERROR, 'graph.synch_factor_negative', path, 'negative Synch_factor is never met')
      end
      node.get_elements('Prerequisites/Prerequisite').each do |pre|
        add(ERROR, 'graph.prerequisite_unknown', path, "prerequisite refers to unknown node '#{pre.attributes['id']}'") unless ids.include?(pre.attributes['id'])
      end
    end

    def check_steps(steps, templates)
      names = []
      steps.each do |step|
        name = text_of(step, 'Step_name')
        type = text_of(step, 'Step_type')
        action_id = text_of(step, 'Action_id')
        path = node_path(step)
        if UNNAMED.include?(name.to_s)
          add(ERROR, 'graph.step_unnamed', "graph/Step[#{step.attributes['id']}]", 'step is not named')
        elsif names.include?(name)
          add(ERROR, 'graph.step_name_not_unique', path, 'step name is not unique')
        end
        names.push(name)
        if UNNAMED.include?(type.to_s)
          add(ERROR, 'graph.step_type_missing', path, 'Step_type is not defined')
        elsif action_id.to_s.empty?
          add(ERROR, 'graph.action_id_missing', path, 'Action_id is missing')
        elsif !templates.include?("#{type}__#{action_id}")
          add(ERROR, 'graph.template_missing', path, "no action template #{type}__#{action_id} in element 3")
        end
        STEP_CHILDREN.each do |child|
          add(ERROR, 'graph.step_element_missing', path, "#{child} is missing (may be empty)") if step.elements[child].nil?
        end
        add(ERROR, 'graph.step_orphan', path, 'no prerequisite, the step never runs (orphaned)') if step.get_elements('Prerequisites/Prerequisite').empty?
        check_output_references(step, steps, path)
      end
    end

    def check_output_references(step, steps, path)
      step.get_elements('Inputs/Input/Map_to').each do |map|
        next unless map.attributes['type'].eql?('output')
        source = steps.find { |other| text_of(other, 'Step_name').eql?(map.attributes['step_name']) }
        next unless source.nil? || !text_of(source, 'Step_type').eql?(map.attributes['step_type']) || !text_of(source, 'Action_id').eql?(map.attributes['action_id'])
        add(ERROR, 'graph.output_unknown', path, "input #{map.parent.attributes['name']} refers to unknown output of step '#{map.attributes['step_name']}' (step_name, step_type, action_id must match)")
      end
    end

    def check_branches(closing, steps)
      success = ->(pre) { SUCCESS_STATUSES.include?(pre.attributes['status'].to_s.downcase) }
      consumers = (closing + steps).flat_map { |node| node.get_elements('Prerequisites/Prerequisite').select(&success).map { |pre| pre.attributes['id'] } }
      steps.each do |step|
        next if consumers.include?(step.attributes['id'])
        add(ERROR, 'graph.step_no_output', node_path(step), 'no node follows it with status Complete (step does not have output)')
      end
      return unless closing.all? { |node| node.get_elements('Prerequisites/Prerequisite').empty? }
      add(ERROR, 'graph.no_termination', 'graph', 'workflow does not terminate: End, Fail and Error have no prerequisite')
    end

    def check_parameters(root, steps)
      linked = (root.get_elements('Start/Parameters/Parameter') + steps.flat_map { |step| step.get_elements('Parameters/Parameter') }).map { |link| link.attributes['id'] }
      defined = {}
      root.get_elements('Parameters/Parameter').each do |parameter|
        name = text_of(parameter, 'Name')
        type = text_of(parameter, 'Value_type')
        path = "graph/Parameter[#{name || parameter.attributes['id']}]"
        add(ERROR, 'graph.parameter_name', path, 'Name is missing') if name.to_s.empty?
        add(ERROR, 'graph.parameter_type', path, "Value_type must be one of #{VALUE_TYPES.join(', ')}") unless VALUE_TYPES.include?(type)
        mandatory_at_runtime = text_of(parameter, 'Runtime_override').eql?('true') && !text_of(parameter, 'Runtime_optional').eql?('true')
        add(WARNING, 'graph.parameter_value', path, 'Value is missing') if !mandatory_at_runtime && parameter.elements['Value'].nil?
        defined[name] = parameter.attributes['id']
      end
      steps.each do |step|
        step.get_elements('Inputs/Input/Map_to').each do |map|
          next unless PARAMETER_MAPPINGS.include?(map.attributes['type'])
          id = defined[map.attributes['name']]
          if id.nil?
            add(ERROR, 'graph.parameter_undefined', node_path(step), "input refers to undefined parameter '#{map.attributes['name']}'")
          elsif !linked.include?(id)
            add(ERROR, 'graph.parameter_not_linked', node_path(step), "parameter '#{map.attributes['name']}' is not linked to Start or to a step: inputs mapped to it are not created")
          end
        end
      end
    end

    # --- Checks with the specifications of plugins ---

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end

    # @param values [Hash{String=>String}] Attributes of the template
    def check_template_attributes(path, type, values)
      spec = @specs[type]
      if spec.nil?
        similar = @specs.keys.find { |name| name.casecmp?(type) }
        return add(ERROR, 'template.plugin_case', path, "plugin #{type} does not exist, class names are case sensitive: #{similar}") if similar
        return add(WARNING, 'template.plugin_unknown', path, "plugin #{type} is not in the specifications: its template and the inputs of its steps are not checked")
      end
      columns = spec['attributes'] || {}
      values.each do |name, value|
        attribute = columns[name]
        if attribute.nil?
          next if TEMPLATE_COLUMNS.include?(name)
          next add(ERROR, 'template.attribute_unknown', path, "#{type} has no attribute #{name}: the import fails") if @plain
          next add(WARNING, 'template.attribute_unknown', path, "#{type} has no attribute #{name}: the import may fail")
        end
        # a placeholder is replaced at run time
        next if blank?(value) || value.include?('<%')
        check_value(path, name, attribute, value)
      end
    end

    # Values are cast by the database layer (ActiveRecord): a text that is not false is true, a text that is not a number is 0
    def check_value(path, name, attribute, value)
      case attribute['type']
      when 'boolean'
        return if (TRUE_VALUES + FALSE_VALUES).include?(value.downcase)
        return add(WARNING, 'template.attribute_value', path, "#{name}: #{value} is read as true: write 1 or 0")
      when *INTEGER_TYPES
        return add(WARNING, 'template.attribute_value', path, "#{name}: #{value} is not an integer, it is read as #{value.to_i}") unless value.match?(/\A-?\d+\z/)
      end
      allowed = attribute['values']
      return if allowed.nil? || allowed.map(&:to_s).include?(value)
      add(ERROR, 'template.attribute_value', path, "#{name}: #{value} is not an allowed value: #{allowed.join(', ')}")
    end

    # Value of an attribute as the plugin sees it: typed for booleans and integers
    def typed(value, type)
      return value unless value.is_a?(String)
      case type
      when 'boolean' then !FALSE_VALUES.include?(value.downcase)
      when *INTEGER_TYPES then value.to_i
      else value
      end
    end

    # Values of the attributes of a template as the plugin sees them: nil when blank
    # An attribute not in the template takes its database default; in plain format, so does a blank one (and false is blank)
    # @return [Hash{String=>Object}]
    def effective_values(spec, values)
      (spec['attributes'] || {}).to_h do |name, attribute|
        value = values[name]
        value = nil if blank?(value) || (@plain && value.eql?('false'))
        value = attribute['default'] if value.nil? && (@plain || !values.key?(name))
        [name, typed(value, attribute['type'])]
      end
    end

    # @param conditions [Hash] `if_blank`, `if_set`, `when` and `conditional` of an input or output of the specifications
    # @return [Boolean, nil] true if the conditions are met, nil if unknown
    def met(conditions, values)
      return if conditions['conditional']
      Array(conditions['if_blank']).all? { |name| values[name].nil? } &&
        Array(conditions['if_set']).all? { |name| !values[name].nil? } &&
        (conditions['when'] || {}).all? do |name, condition|
          value = values[name]
          if condition.key?('in')
            condition['in'].any? { |item| item.nil? ? value.nil? : item.to_s.eql?(value.to_s) }
          else
            !value.nil? && condition['not_in'].none? { |item| item.to_s.eql?(value.to_s) }
          end
        end
    end

    # @return [Array<String>] Names declared by a type map `{'name'=>'type'}` (Ruby or JSON syntax) or a list `['name']`
    def declared_names(value)
      text = value.strip
      return text.scan(/['"]([^'"]+)['"]\s*(?:=>|:)/).flatten if text.start_with?('{')
      return text.scan(/['"]([^'"]+)['"]/).flatten if text.start_with?('[')
      []
    end

    # Inputs and outputs of a step, for the attributes of its template
    # @return [Hash] `:inputs` and `:outputs`: name => {`exists`, `required`} (true, false or nil if unknown),
    #   and `:complete`: kind => true if all inputs (or outputs) are known, so that an other one does not exist
    def step_interface(spec, attributes)
      values = effective_values(spec, attributes)
      interface = {inputs: {}, outputs: {}, complete: {}}
      %i[inputs outputs].each do |kind|
        (spec[kind.to_s] || {}).each do |name, info|
          # a name in angle brackets is the value of that attribute
          name = values[Regexp.last_match(1)]&.to_s if name =~ /\A<(\w+)>\z/
          exists = met(info, values)
          next if name.nil? || exists.eql?(false)
          required = info['required'].is_a?(Hash) ? met(info['required'], values) : info['required']
          interface[kind][name] = {'exists' => exists, 'required' => required.eql?('depends') ? nil : required}
        end
        declared = (spec['attributes'] || {}).values.any? { |attribute| attribute['declares'].to_s.end_with?(kind.to_s) }
        partly = Array(spec['notes']).any? { |note| note.match?(PARTLY_DEFINED[kind]) }
        interface[:complete][kind] = (declared || !partly) && blank?(attributes[SPEC_CODE[kind]])
      end
      (spec['attributes'] || {}).each do |name, attribute|
        value = attributes[name]
        next if blank?(value)
        case attribute['declares']
        when 'required_inputs', 'optional_inputs'
          required = attribute['declares'].eql?('required_inputs')
          declared_names(value).each { |input| interface[:inputs][input] ||= {'exists' => true, 'required' => required} }
        when 'outputs'
          declared_names(value).each { |output| interface[:outputs][output] ||= {'exists' => true} }
        end
        next unless attribute['placeholders']
        value.scan(PLACEHOLDER).flatten.each { |input| interface[:inputs][input] ||= {'exists' => true, 'required' => true} }
        # inputs of other placeholders (functions of variables) are not known
        interface[:complete][:inputs] = false if value.scan('<%').size > value.scan(PLACEHOLDER).size
      end
      interface
    end

    def check_step_interfaces(steps)
      interfaces = {}
      interface_of = lambda do |step|
        type = text_of(step, 'Step_type')
        key = "#{type}__#{text_of(step, 'Action_id')}"
        next if @specs[type].nil? || !@template_attributes.key?(key)
        interfaces[key] ||= step_interface(@specs[type], @template_attributes[key])
      end
      steps.each do |step|
        path = node_path(step)
        type = text_of(step, 'Step_type')
        interface = interface_of.call(step)
        unless interface.nil?
          inputs = step.get_elements('Inputs/Input').map { |input| input.attributes['name'] }
          # a carried variable is also given to the step under its name
          provided = inputs + step.get_elements('Outputs/Carry_thru').map { |carry| carry.attributes['name'] }
          unknown = interface[:complete][:inputs] ? inputs - interface[:inputs].keys : []
          unknown.each { |name| add(WARNING, 'step.input_unknown', path, "#{type} has no input #{name} with this template: Orchestrator ignores it") }
          interface[:inputs].each do |name, input|
            next unless input['exists'].eql?(true) && input['required'].eql?(true) && !provided.include?(name)
            add(ERROR, 'step.input_missing', path, "required input #{name} is not mapped")
          end
          if interface[:complete][:outputs]
            (step.get_elements('Outputs/Output').map { |output| output.attributes['name'] } - interface[:outputs].keys).each do |name|
              add(WARNING, 'step.output_unknown', path, "#{type} has no output #{name} with this template: its settings are ignored")
            end
          end
        end
        step.get_elements('Inputs/Input/Map_to').each do |map|
          next unless map.attributes['type'].eql?('output')
          source = steps.find { |other| STEP_IDENTITY.all? { |name| text_of(other, name).eql?(map.attributes[name.downcase]) } }
          source_interface = source && interface_of.call(source)
          next if source_interface.nil? || !source_interface[:complete][:outputs] || source_interface[:outputs].key?(map.attributes['name'])
          add(
            WARNING, 'step.output_not_produced', path,
            "input #{map.parent.attributes['name']} maps output #{map.attributes['name']} of step '#{map.attributes['step_name']}', which #{map.attributes['step_type']} does not produce with its template"
          )
        end
      end
    end
  end
end
