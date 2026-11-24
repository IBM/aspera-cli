## Plugin: `orchestrator`: IBM Aspera Orchestrator

To write workflow files without the designer, refer to the [Aspera Orchestrator Development Guide](https://github.com/laurent-martin/aspera-orchestrator-plugins-doc/blob/main/docs/orchestrator-development-guide.md): file format, graph, execution, examples and REST API.

Command `workflows development` gives access to the documentation for workflow development, read from GitHub.
Without argument, it lists the documents: the guide (`guide`), the [Action Template Reference](https://github.com/laurent-martin/aspera-orchestrator-plugins-doc/blob/main/docs/action-template-reference.md) (`templates`) and the Plugin Manual (`manual`).
After the name of a document: `toc` lists its sections, `full` displays the whole document, and `section <anchor>` displays only one section: the guide and the manual are large, use `toc` first.
It does not require access to Orchestrator.
The [MCP server](#plugin-mcp-model-context-protocol-server) instructs AI assistants to read it before writing or modifying a workflow.

```shell
<%=cmd%> orchestrator workflows development guide toc
<%=cmd%> orchestrator workflows development templates section customruby
```

Commands `plugins spec` display the specifications of action plugins, read from GitHub: [plugins.yml](https://github.com/laurent-martin/aspera-orchestrator-plugins-doc/blob/main/docs/plugins.yml).
For each plugin: template attributes (label, allowed values, defaults), and inputs and outputs of its steps, with the template settings they depend on.
The fields are described in section [Plugin specifications](https://github.com/laurent-martin/aspera-orchestrator-plugins-doc/blob/main/docs/orchestrator-development-guide.md#plugin-specifications) of the guide.
`toc` lists the plugins, with the anchor of their section in the Plugin Manual (`manual_anchor`, for `workflows development manual section`).
`show` with a plugin name (class name, case insensitive) displays its specification, or one section: `attributes`, `inputs` or `outputs`.
It does not require access to Orchestrator.
Option `plugin_specs` gives another URL or path of the file, for example for another version of Orchestrator.

```shell
<%=cmd%> orchestrator plugins spec toc --select=@json:'{"category":"Triggers"}'
<%=cmd%> orchestrator plugins spec show AmazonS3Operation --format=yaml
<%=cmd%> orchestrator plugins spec show ascpclient inputs
```

### Authentication

The Orchestrator plugin supports different credentials and authentication styles configured via `--auth_style`:

- **Username / Password** (`--username` and `--password`):
  - `--auth_style=token` (default): Exchanges credentials for a JWT Bearer token via `/api/login`.
  - `--auth_style=basic`: Standard HTTP Basic Authentication.
  - `--auth_style=query`: Passes credentials in URL query parameters (`?login=...&password=...`).
- **Username / API Key** (`--username` and `--apikey`): the API key is the one of the user, so the user name is required.
  - `--auth_style=token` (default): Exchanges the API key for a JWT Bearer token via `/api/login`.
  - `--auth_style=query`: Passes the API key in URL query parameters (`?login=...&api_key=...`).

### Start a workflow

Command `workflows start` creates a work order:

```shell
<%=cmd%> orchestrator workflows start <%=ph :workflow_id%> [<%=ph :parameters%>] [<%=ph :execution%>]
```

- `parameters`: `Hash` of external parameters of the workflow (optional).
- `execution`: `Hash` controlling the execution of the work order (optional):

  | Key           | Type      | Description |
  |---------------|-----------|-------------|
  | `synchronous` | `Boolean` | Wait for completion of the work order (default: `false`). |
  | `step`        | `String`  | Name of the work step providing the result. |
  | `variable`    | `String`  | Name of the output variable of `step` returned as result. |

  `step` and `variable` must be provided together, and imply `synchronous`.

By default, the call is asynchronous and returns the work order information.

Example: Start workflow `1234` with parameter `Param`, wait for completion and display the value of output `Complete_status_message` of step `ResultStep`:

```shell
<%=cmd%> orchestrator workflows start 1234 @json:'{"Param":"world !"}' @json:'{"step":"ResultStep","variable":"Complete_status_message"}'
```

> [!NOTE]
> Options `synchronous` and `result` (`--result=<%=ph :work_step%>:<%=ph :variable%>`) are deprecated: use `execution` instead.

### Import a workflow

Command `workflows export` displays a workflow in Orchestrator's export format (YAML).
With option `dependencies`, it saves instead a package (`.wkf`) that also contains the sub-workflows and remote nodes used by the workflow, in the folder given by option `to_folder` (default: current folder).
Command `workflows import` creates a new workflow from such a file, and displays it, including its new `id`.
The imported workflow is a draft: publish it with `workflows publish` before starting it.

Example: Copy workflow `1234` to another Orchestrator, where the imported workflow gets `id` `5678`:

```shell
<%=cmd%> orchestrator workflows export 1234 --out.file=my_workflow.yml
<%=cmd%> orchestrator workflows import my_workflow.yml --preset=other_orchestrator --out.fields=id
<%=cmd%> orchestrator workflows publish 5678 --preset=other_orchestrator
```

Example: Save workflow `1234` with its dependencies in folder `/tmp`, and import the package:

```shell
<%=cmd%> orchestrator workflows export 1234 @json:'{"dependencies":true}' --to-folder=/tmp
<%=cmd%> orchestrator workflows import /tmp/Workflow_my_workflow_v100.wkf
```

Command `workflows import` always creates a new workflow.
Command `workflows import_with_constraints` imports a workflow file already present on the Orchestrator host, either as a new workflow or as a new revision of an existing workflow (`add_as_revision`), and resolves conflicts with existing global templates, sub-workflows and remote nodes.
Command `workflows import` stores each uploaded file in folder `<run_dir>/workflows/import/` of the Orchestrator host.

Example: Add the file uploaded by a previous `workflows import` as a new revision of workflow `1234`, and publish it:

```shell
<%=cmd%> orchestrator workflows import_with_constraints @json:'{"filename":"/opt/aspera/orchestrator/var/run/orchestrator/workflows/import/my_workflow.yml","add_as_revision":1234}'
<%=cmd%> orchestrator workflows publish 1234
```

#### Check a workflow before import

Orchestrator does not validate the graph of a workflow on import: an invalid workflow is imported, then fails to publish, or at run time.
Command `workflows check_import` checks a workflow file (`.yml`) or package (`.wkf`) with the rules of the workflow designer, and does not need access to Orchestrator:

```shell
<%=cmd%> orchestrator workflows check_import my_workflow.yml
```

It displays one line per issue, or `no problem found`.
The file is read as `@file:`: at [Security Level](#security-level) `medium`, only in `allowed_paths`, and not at level `high`.
An issue has these fields:

| Field      | Description |
|------------|-------------|
| `severity` | `error`: the workflow will not import, publish or run correctly. `warning`: to check. |
| `code`     | Stable identifier of the rule, for programs, for example `graph.step_orphan`. |
| `file`     | File of the package where the issue is (only for a `.wkf`). |
| `path`     | Where in the file, for example `graph/Step[Say hello]`. |
| `message`  | Description. |

Checked: format of the file (YAML, number of elements, plain format layout), attributes, `error_free`, action template keys, XML of the graph, `Start`, `End`, `Fail` and `Error` nodes, unique step names, step template, prerequisites, `Synch_factor`, steps that have no output or no prerequisite, references to outputs and parameters.

A package (`.wkf`) whose files exceed 256 MiB once decompressed is not checked: it is reported as an issue (`package.too_large`).

With the specifications of plugins (see `plugins spec show`), it also checks action templates and the inputs of steps, for the settings of each template:

- plugin class name, attributes of the template, and their values (type, allowed values),
- required inputs not mapped (`step.input_missing`),
- inputs that the plugin does not have with this template, which Orchestrator ignores (`step.input_unknown`),
- mapped outputs that the source step does not produce (`step.output_not_produced`).

If the specifications cannot be read (option `plugin_specs`), these checks are skipped, with a warning (`plugins.specs_unavailable`).
Not checked: the plugins enabled on the server (see `workflows find_constraints`).

Command `workflows import` runs the same check, and logs the issues as warnings; it does not stop the import.
Use `--log-level=warn` to see them.

The check is done by `ascli`, behind one method that has the shape of a REST operation: the file goes in, a structure with `valid`, `file_name` and the list of `issues` comes out.
It can be replaced by a call to Orchestrator if such an API becomes available.

#### Resolve conflicts before import

The web interface of Orchestrator lists the conflicts with existing sub-workflows, global templates and remote nodes, and the plugins to enable, and asks for a choice for each of them.
Command `workflows find_constraints` does the same for a file present on the Orchestrator host (see `workflows import_with_constraints`):

```shell
<%=cmd%> orchestrator workflows find_constraints /opt/aspera/orchestrator/var/run/orchestrator/workflows/import/my_workflow.yml
<%=cmd%> orchestrator workflows find_constraints /opt/aspera/orchestrator/var/run/orchestrator/workflows/import/my_workflow.yml 1234
```

The optional second argument is the id of the workflow that receives the file as a new revision.
Each line is a conflict (`type`: `subwf_constraints`, `action_template_constraints`, `remote_node_constraints`), with its `name` and the possible `choices`, or a plugin to enable (`missing_plugins`).
The `type` is the key to use in the argument of `import_with_constraints`.
Orchestrator does not check that the file exists: a wrong path gives the same answer as a file without conflict.

Orchestrator does not refuse an incomplete resolution: `workflows import_with_constraints` checks with `find_constraints` first, and refuses to import in these cases:

- Plugins are not enabled and `auto_enable_missing_plugins` is not `true` (Orchestrator fails with an internal error).
- A resolution is given for some conflicts of a type, but not all (Orchestrator imports the others as copies, without error).

`auto_enable_missing_plugins` must be a boolean (`true` or `false`): Orchestrator takes the string `"false"` as true, and `ascli` refuses a string.

<%=include_commands_for_plugin(:orchestrator)%>

