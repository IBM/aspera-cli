## Plugin: `aoc`: IBM Aspera on Cloud

The `aoc` plugin enables integration with IBM Aspera on Cloud.
Because the Aspera on Cloud API requires **OAuth 2.0** for authentication, HTTP Basic authentication is **not** supported.

> [!NOTE]
> This plugin is also used for Aspera Enterprise Web Apps (AEWA).

### AoC configuration: Using Wizard

<%=tool%> includes an interactive configuration [wizard](#wizard) to simplify the OAuth setup.
While manual configuration is possible, using the wizard is the recommended method for most deployments.

#### Prerequisites

To complete the setup, you must have:

- **The URL or organization name** of your Aspera on Cloud instance:

  - `_your_organization_`
  - `_your_organization_.ibmaspera.com`
  - `https://_your_organization_.ibmaspera.com`

- **User Credentials**: Access to the Aspera on Cloud web interface to update your Public Key.

#### Wizard Invocation

The wizard accepts an optional argument, a `Hash` with keys:

- `url`: The organization name or the full FQDN.

- `plugin`: Specify `aoc` to bypass automatic application detection.

- `preset`: Name of the preset to create.

If the URL is omitted, the wizard will prompt for it interactively.

#### Example: Standard Configuration

During the process, the wizard generates or identifies a PEM-formatted Public Key.
You must copy this key (including the `BEGIN` and `END` headers) and paste it into the **Public Key** field in the Aspera on Cloud UI.
Once saved in the UI, return to the terminal and press Enter.

> [!IMPORTANT]
> In the following example, replace `https://<%=ph :org_name%>.ibmaspera.com` with your actual organization URL.
> `(User)` represents the user menu on the top right of the page.

```console
$ <%=cmd%> config wizard
Using: Aspera on Cloud at https://<%=ph :org_name%>.ibmaspera.com
Private RSA key, e.g. @file:<path> (leave empty to generate):
option: private_key>
Using existing key:
/home/john/.aspera/<%=cmd%>/<%=ph :pkey_name%>.pem
Please Log in as user john@example.com at: https://<%=ph :org_name%>.ibmaspera.com
Navigate to: (User) → Account Settings → Profile → Public Key
Check or update the value to (including BEGIN/END lines):
-----BEGIN PUBLIC KEY-----
MIICIjANBg....
....
....kCAwEAAQ==
-----END PUBLIC KEY-----
Once updated or validated, press [Enter].

Using global client_id.
Preparing preset: aoc<%=ph :org_name%>ibmaspera_com_john_example_com
Setting config preset as default for aoc
You can test with:
<%=cmd%> aoc user profile show
Saving config file.
```

#### Advanced Options

- **Custom Client Identification**:
  By default, <%=tool%> uses a pre-registered global client ID.
  To create and use an organization-specific integration, give the option `--use-generic-client=no` of plugin `aoc` to the wizard command.

- **Direct Plugin Targeting**: To limit detection to the `aoc` plugin and skip discovery, provide both the URL and plugin name:

  ```shell
  <%=cmd%> config wizard @: url=<%=ph :org_name%> plugin=aoc
  ```

#### Verifying the Configuration

Upon successful completion, the wizard creates a configuration preset and assigns it as the default for the `aoc` plugin.

To verify the current configuration presets, execute:

```shell
<%=cmd%> config preset list
```

To test the connection and display your profile information:

```shell
<%=cmd%> aoc user profile show
```

### AoC configuration: Using manual setup

> [!NOTE]
> If you used the wizard (recommended): skip this section.

#### AoC manual configuration: Details

IBM Aspera on Cloud (AoC) supports several OAuth 2.0 authentication mechanisms to secure API interactions.
The method used is determined by the `auth` option.

Supported Authentication Methods:

| Method         | `auth` | Description |
|----------------|--------|-------------|
| JSON Web Token | `jwt`  | **Recommended**. Uses a private RSA key for secure, headless authentication.<%=br%>Ideal for automation and scripts. |
| Web-based      | `web`  | Redirects the user to a browser for interactive login.<%=br%>Suitable for manual operations on local workstations. |
| URL Token      | -      | Facilitates authentication for external users via public link tokens. |

<%=tool%> automatically manages the lifecycle of Bearer tokens.
Once a token is generated, it is cached in the local configuration folder (option `cache_tokens`).
The tool reuses valid tokens and automatically triggers a refresh or regeneration when they expire, according to the expiration policy defined by the AoC administrator.

#### API Client Registration

> [!NOTE]
> The pre-registered `client_id` (default, and used by the wizard) supports only `auth=jwt`: in that case, skip this and do not set `client_id` and `client_secret` in next section.
> For `auth=web`, register an API client as below, and set its `client_id`, `client_secret` and a `redirect_uri` equal to one of its **Redirect URIs**.

You can use a specific OAuth API `client_id`.
The first step is to declare <%=tool%> in Aspera on Cloud using the admin interface.

([AoC documentation: Registering an API Client](https://ibmaspera.com/help/admin/organization/registering_an_api_client)).

To register with web-based authentication (auth=web):

- Open a web browser, log in to your instance: for example, `https://<%=ph :org_name%>.ibmaspera.com/`
  (use your actual AoC instance URL)
- Go to (Apps) &rarr; Admin &rarr; Organization &rarr; Integrations
- Click **Create New**
  - **Client Name**: <%=tool%>
  - **Redirect URIs**: `http://localhost:12345`
  - **Origins**: `localhost`
  - Uncheck **Prompt users to allow client to access**
  - Leave the JWT part for now
- **Save**

> [!NOTE]
> For web based authentication, <%=tool%> listens on a local port (for example, specified by the `redirect_uri` parameter, in this example: `12345`), and the browser will provide the OAuth code there.
> See [Web login flow](#web-login-flow).
> For <%=tool%>, HTTP is required, and `12345` is the default port.
> The host of `redirect_uri` shall be loopback: `localhost`, an address of `127.0.0.0/8`, or `[::1]`.

Once the client is registered, a **Client ID** and **Secret** are created; these values are used in the next step.

#### Configuration for Aspera on Cloud

If you did not use the wizard, you can also manually create an [Option Preset](#option-preset) for <%=tool%> in its configuration file.

Create an [Option Preset](#option-preset) called `<%=ph :aoc_org%>` using `ask` for interactive input (client info from previous step):

```shell
<%=cmd%> config preset ask <%=ph :aoc_org%> url client_id client_secret
option: url> https://<%=ph :org_name%>.ibmaspera.com/
option: client_id> <%=ph :client_id%>
option: client_secret> <%=ph :client_secret%>
updated: <%=ph :aoc_org%>
```

> [!NOTE]
> In above example, replace `https://<%=ph :org_name%>.ibmaspera.com` with your actual AoC URL.

(This can also be done in one line using the command `config preset set <%=ph :aoc_org%> @: url=...`)

Define this [Option Preset](#option-preset) as default configuration for the `aoc` plugin:

```shell
<%=cmd%> config preset set default aoc <%=ph :aoc_org%>
```

> [!NOTE]
> Default `auth` is `jwt` (see next section).
> For web authentication, also set `auth=web` and `redirect_uri=http://localhost:12345` (the value registered in the API client):
>
> ```shell
> <%=cmd%> config preset set <%=ph :aoc_org%> @: auth=web redirect_uri=http://localhost:12345
> ```

If the browser shows: _Add the redirect URI for your API client in the admin application of IBM Aspera on Cloud and make sure it matches 'redirect_uri' query parameter exactly_, then either:

- no `client_id` is set: the pre-registered client does not support `auth=web`, or
- `redirect_uri` is not exactly one of the **Redirect URIs** of the API client: scheme (`http` or `https`), host (`localhost` or `127.0.0.1`), port, and trailing `/` shall be identical.

#### Authentication with private key

For browser-less, private key-based authentication, use the following steps.

To use JSON Web Token (JWT) for Aspera on Cloud API client authentication,
a [private/public key pair](#private-key) must be used.

##### API Client JWT activation

If you are not using the built-in client_id and secret, JWT needs to be authorized in Aspera on Cloud.
This can be done in two ways:

- Graphically

  - Open a web browser, log in to your instance: `https://<%=ph :org_name%>.ibmaspera.com/`
    (Use your actual AoC instance URL)
  - Go to Apps &rarr; Admin &rarr; Organization &rarr; Integrations
  - Click the previously created application
  - Select tab: **JSON Web Token Auth**
  - Modify options if necessary, for instance: activate both options in section **Settings**
  - **Save**

- Using command line

```shell
<%=cmd%> aoc admin client list
```

```text
Items: 4/4
╭────────────┬─────────────────────╮
│ id         │ name                │
╞════════════╪═════════════════════╡
│ oXPUyJ7JpQ │ ALM                 │
│ <%=ph :id%> │ web_client         │
│ TDNl2bLZqw │ jwt_client          │
│ VTh92i5OfQ │ iPaaS               │
╰────────────┴─────────────────────╯
```

```shell
<%=cmd%> aoc admin client modify <%=ph :id%> @json:'{"jwt_grant_enabled":true,"explicit_authorization_required":false}'
```

```text
modified
```

#### User key registration

The public key must be assigned to your user.
This can be done in two ways as follows.

##### Graphically

Open the previously generated public key located here: `$HOME/.aspera/<%=cmd%>/<%=ph :pkey_name%>.pub`

- Open a web browser, log in to your instance: `https://<%=ph :org_name%>.ibmaspera.com/`
  (Use your actual AoC instance URL)
- Click the user icon (top right)
- Select **Account Settings**
- Paste the Public Key PEM value in the **Public Key** section
- Click **Submit**

##### Using command line

```shell
<%=cmd%> aoc admin user list
```

```text
╭─────────┬────────────────┬────────────────────╮
│ id      │ name           │ email              │
╞═════════╪════════════════╪════════════════════╡
│ 1234567 │ John Doe       │ john@example.com   │
│ 7654321 │ Alice Saprich  │ alice@example.com  │
│ 1234321 │ Sponge Bob     │ bob@example.com    │
╰─────────┴────────────────┴────────────────────╯
```

```shell
<%=cmd%> aoc user profile modify @: public_key=@file:~/.aspera/<%=cmd%>/<%=ph :pkey_name%>.pub
```

```text
modified
```

> [!TIP]
> The `<%=cmd%> aoc user profile show` command can be used to verify modifications.

#### [Option Preset](#option-preset) modification for JWT

To activate default use of JWT authentication for <%=tool%> using the [Option Preset](#option-preset), do the following:

- Change auth method to JWT
- Provide location of private key
- Provide username to login as (OAuth **subject**)

Execute:

```shell
<%=cmd%> config preset set <%=ph :aoc_org%> @: auth=jwt private_key=@val:@file:~/.aspera/<%=cmd%>/<%=ph :pkey_name%> username=someuser@example.com
```

> [!NOTE]
> The private key argument represents the actual PEM string.
> To read the content from a file, use the `@file:` prefix.
> But if the `@file:` argument is used as is, it will read the file and set in the configuration file.
> So, to keep the `@file:` tag in the configuration file, the `@val:` prefix is added.

After this last step, commands do not require web login anymore.

#### AoC bootstrap authentication

For quick access using an existing browser session, use `--auth=boot`.

- Open a Web browser and log in to your AoC instance
- Open the browser developer tools
- In **Network**, select any request to `api.ibmaspera.com`.
- In **Headers**, right-click the `Cookie` Request Header and select **Copy Value**

Alternatively:

- Go to the **Application** tab &rarr; **Cookies**
- Copy the full cookie string, all values on one line, separated by `"; "` (semi-colon + space).

For a simpler use, configure a preset with the `url` option, and optionally `username`.
(If the username is not provided, then the subject from the token is used, else both must match.)

Use the cookie string as the value of option `password`; an environment variable is convenient, as the value is temporary anyway:

```shell
export <%=opt_env :password%>="...; aoc.token=...; aoc.refresh=...; ..."

<%=cmd%> aoc user profile show --auth=boot
```

> [!NOTE]
> The cookie string contains `aoc.token` (bearer JWT, mandatory) and `aoc.refresh` (refresh token, optional).
> Only those two are used.
> On first use, the tokens are cached locally.
> Subsequent calls reuse the cache and refresh automatically: the `password` option is used only to get the `username` unless the option `username` is already provided.

#### Public and private links

AoC gives the possibility to generate public links for both the `Files` and `Packages` modules.
Public links embed the authorization of access.
Provide the public link using option `url` alone.

In addition, the `Files` application supports private links.
Private links require the user to authenticate.
So, provide the same options as for regular authentication, and provide the private link using option `url`.

A user may not be part of any workspace, but still have access to shared folders (using private links).
In that case, it is possible to list those shared folders by using a value for option `workspace` equal to `@none:` or `@json:null` or `@ruby:nil`.

#### AoC: First Use

Once client has been registered and [Option Preset](#option-preset) created: <%=tool%> can be used:

```shell
<%=cmd%> aoc files browse /
```

```text
Current Workspace: Default Workspace (default)
empty
```

### Calling AoC APIs from command line

The command `<%=cmd%> aoc bearer_token` generates an OAuth token to call AoC APIs as user (scope `user:all`).
The command `<%=cmd%> aoc admin bearer_token` generates a token with scope `admin:all`, required by administration APIs, such as `group_memberships`.
This can be useful when a command is not yet available.
The token is a secret: it is hidden in the output, unless option `--out.secrets=yes` is used.

Example: list members of groups, with the name of group and member (option `-g` of `curl`: the brackets of `embed[]` are not a URL range):

```shell
curl -s -g -H "Authorization: $(<%=cmd%> aoc admin bearer_token --out.secrets=yes)" 'https://api.ibmaspera.com/api/v1/group_memberships?embed[]=group&embed[]=member'|jq -r '.[]|(.group.name + " -> " + .member.name)'
```

The same with `<%=cmd%>` (a parameter with several values is given as an array, with `[]` in its name):

```shell
<%=cmd%> aoc admin group_membership list --query=@json:'{"embed[]":["group","member"]}' --fields=group.name,member.name
```

It is also possible to get the bearer token for node, as user or as admin using:

```shell
<%=cmd%> aoc files bearer_token_node /
```

```shell
<%=cmd%> aoc admin node bearer_token <%=ph :node_id%>
```

### Administration

The `admin` command allows several administrative tasks (and requires admin privilege).

It allows actions (create, update, delete) on **resources**: users, groups, nodes, workspaces, and so on, with the `admin <%=ph :resource_type%>` commands.

#### Listing resources

The command `aoc admin <%=ph :type%> list` lists all entities of given type.
It uses paging and multiple requests if necessary.

The option `query` can be optionally used.
It expects a `Hash` using [Extended Value](#extended-value-syntax) syntax.
For a single filter key, the dot-path option form is the most direct (for example, `--query.sort=name`).
For multiple keys or values copied from API documentation, `--query=@json:{...}` is more suitable.
Values are directly sent to the API call and used as a filter on server side.

The following parameters are supported:

| Parameter | Source | Description                                        |
|-----------|--------|----------------------------------------------------|
| `q`       | Native | A filter on name of resource.<%=br%>(case-insensitive, matches if value is contained in name) |
| `sort`    | Native | Name of fields to sort results, prefix with `-` for reverse order. |
| `page`    | Native | Do not use.<%=br%>Managed by <%=tool%>. |
| `per_page`| Native | Do not use.<%=br%>Managed by <%=tool%>. |
| `max`     | <%=tool%> | Maximum number of items to retrieve. |
| `pmax`    | <%=tool%> | Maximum number of pages to request.  |
| other     | Native | Other specific parameters depending on resource type. |

> [!NOTE]
> Both `max` and `pmax` are processed by <%=tool%> (see [option `--query`](#option---query-parameters-of-the-api)).
> <%=tool%> will return all values using paging if not provided.
> `page` and `per_page` are normally added by <%=tool%> to build successive API calls to get all values if there are more than 1000
> (AoC allows a maximum page size of 1000).
> Other parameters depend on the type of resource (refer to AoC API) and are directly sent as parameters to the `GET` request on API.

> [!TIP]
> Use `--query=help` to display the full list of supported query parameters for any `list` command.
> For example: `<%=cmd%> aoc admin user list --query=help`

> [!TIP]
> Options `--out.query` and `--out.select` can also be used to further refine selection, refer to [Filtering results](#filtering-results).

Examples:

- List users with `laurent` in name:

```shell
<%=cmd%> aoc admin user list --query.q=laurent
```

- List users who logged in before a date:

```shell
<%=cmd%> aoc admin user list --query.q='last_login_at:<2018-05-28'
```

- List external users and sort in reverse alphabetical order using name:

```shell
<%=cmd%> aoc admin user list --query=@json:'{"member_of_any_workspace":false,"sort":"-name"}'
```

#### Selecting a resource

Resources are identified by a unique `id` and a unique `name` (case-insensitive).

To execute an action on a specific resource, select it using one of those methods:

- **recommended**: give the ID directly on the command line **after the action**: `aoc admin node show 123`
- Give another unique field, such as the name, using the [percent selector](#percent-selector) **after the action**: `aoc admin node show %name:abc`

#### Creating a resource

New resources (users, groups, workspaces, and so on) can be created using a command like:

```shell
<%=cmd%> aoc admin <%=ph :resource_type%> create @json:'{<...parameters...>}'
```

Some API endpoints are described in [IBM API Hub](https://developer.ibm.com/apis/catalog?search=%22aspera%20on%20cloud%20api%22).
Not all endpoints are documented there.

Nevertheless, it is possible to infer the structure of the creation payload by dumping an existing resource and using the same parameters for creation.

```shell
<%=cmd%> aoc admin group show 12345 --format=json
```

```json
{"created_at":"2018-07-24T21:46:39.000Z","description":null,"id":"12345","manager":false,"name":"A8Demo WS1","owner":false,"queued_operation_count":0,"running_operation_count":0,"stopped_operation_count":0,"updated_at":"2018-07-24T21:46:39.000Z","saml_group":false,"saml_group_dn":null,"system_group":true,"system_group_type":"workspace_members"}
```

Remove the parameters that are set by the system (`id`, `created_at`, `updated_at`), and optional ones.

And then craft your command:

```shell
<%=cmd%> aoc admin group create @json:'{"wrong":"param"}'
```

If the command returns an error, for example:

```text
ERRR Rest: found unpermitted parameter: :wrong
code: unpermitted_parameters
request_id: 2a487dbc-bc5c-41ab-86c8-3b9972dfd4c4
api.ibmaspera.com 422 Unprocessable Entity
```

Remove the offending parameters and try again.

> [!NOTE]
> Some properties that are shown in the web UI, such as membership, are not listed directly in the resource, but instead another resource is created to link a user and its group: `group_membership`, or the owners and managers of a group: `group_permission`

#### Access Key secrets

To access some administrative actions on **nodes** (in fact, access keys), the associated secret may be required.
The secret is provided using the `secret` option.
For example, in a command like:

```shell
<%=cmd%> aoc admin node do <%=ph :node_id%> v3 info
```

It is also possible to store secrets in the [secret vault](#secret-vault) and then automatically find the related secret using the [config finder](#configuration-finder).

#### Activity

The activity app can be queried with:

```shell
<%=cmd%> aoc admin analytics transfers
```

It supports filters and can send notifications using option `notify_to`.
A template is defined using option `notify_template`:

`mytemplate.erb`:

```yaml
From: <%='<'%>%=from_name%> <<%='<'%>%=from_email%>>
To: <<%='<'%>%=ev['user_email']%>>
Subject: <%='<'%>%=ev['files_completed']%> files received

Dear <%='<'%>%=ev[:user_email.to_s]%>,
We received <%='<'%>%=ev['files_completed']%> files for a total of <%='<'%>%=ev['transferred_bytes']%> bytes, starting with file:
<%='<'%>%=ev['content']%>

Thank you.
```

The environment provided contains the following additional variable:

- `ev` : all details on the transfer event

Example:

```shell
<%=cmd%> aoc admin analytics transfers --once-only=yes --lock-port=12345 --query=@json:'{"status":"completed","direction":"receive"}' --notify-to=active --notify-template=@file:mytemplate.erb
```

Options:

- `once_only`: keep track of the last date it was called, so that the next call gets only new events
- `query`: filter (on API call)
- `notify_to`, `notify_template`: send an email as specified by the template; the template can be placed in a file with the `@file:` modifier.

> [!NOTE]
> This must not be executed in less than 5 minutes because the analytics interface accepts only a period of time between 5 minutes and 6 months.
> The period is `[date of previous execution]..[now]`.

#### Using ATS

See the section **Examples** of [ATS](#plugin-ats-ibm-aspera-transfer-service) and substitute command `ats` with `aoc admin ats`.

#### Files with type `link`

Aspera on Cloud Shared folders are implemented through a special type of file: `link`.
A `link` is the equivalent of a symbolic link on a file system: it points to another folder (not file).

Listing a link (as the last element of the path) shows information on the link itself, not the content of the folder it points to.
To list the target folder content, add a `/` at the end of the path.

Example:

```shell
<%=cmd%> aoc files browse the_link
```

```text
Current Workspace: Default (default)
╭──────────┬──────┬────────────────┬──────┬──────────────────────┬──────────────╮
│ name     │ type │ recursive_size │ size │ modified_time        │ access_level │
╞══════════╪══════╪════════════════╪══════╪══════════════════════╪══════════════╡
│ the_link │ link │                │      │ 2021-04-28T09:17:14Z │ edit         │
╰──────────┴──────┴────────────────┴──────┴──────────────────────┴──────────────╯
```

```shell
<%=cmd%> aoc files browse the_link/
```

```text
Current Workspace: Default (default)
╭─────────────┬──────┬────────────────┬──────┬──────────────────────┬──────────────╮
│ name        │ type │ recursive_size │ size │ modified_time        │ access_level │
╞═════════════╪══════╪════════════════╪══════╪══════════════════════╪══════════════╡
│ file_inside │ file │                │      │ 2021-04-26T09:00:00Z │ edit         │
╰─────────────┴──────┴────────────────┴──────┴──────────────────────┴──────────────╯
```

#### Example: Bulk creation of users

```shell
<%=cmd%> aoc admin user create --bulk=yes @json:'[{"email":"dummyuser1@example.com"},{"email":"dummyuser2@example.com"}]'
```

```text
╭───────┬─────────╮
│ id    │ status  │
╞═══════╪═════════╡
│ 98398 │ created │
│ 98399 │ created │
╰───────┴─────────╯
```

#### Example: Find with filter and delete

```shell
<%=cmd%> aoc admin user list --query.q=dummyuser --fields=id,email
```

```text
╭───────┬────────────────────────╮
│ id    │ email                  │
╞═══════╪════════════════════════╡
│ 98398 │ dummyuser1@example.com │
│ 98399 │ dummyuser2@example.com │
╰───────┴────────────────────────╯
```

```shell
<%=cmd%> aoc admin user list --query.q=dummyuser --fields=id --out.level=data --format=csv | <%=cmd%> aoc admin user delete @lines:@stdin: --bulk=yes
```

```text
╭───────┬─────────╮
│ id    │ status  │
╞═══════╪═════════╡
│ 98398 │ deleted │
│ 98399 │ deleted │
╰───────┴─────────╯
```

#### Example: Find deactivated users for more than 2 years

```shell
<%=cmd%> aoc admin user list --query=@ruby:'{"deactivated"=>true,"q"=>"last_login_at:<#{(DateTime.now.to_time.utc-2*365*86400).iso8601}"}'
```

To delete them use the same method as before.

#### Example: Display current user's workspaces

```shell
<%=cmd%> aoc user workspaces list
```

```text
╭────────┬─────────────────────────╮
│ id     │ name                    │
╞════════╪═════════════════════════╡
│ 45073  │ Engineering             │
│ 145222 │ Marketing               │
│ 149207 │ Sales                   │
│ 149699 │ Secret Project          │
╰────────┴─────────────────────────╯
```

#### User client settings

The `aoc user settings` sub-command manages persistent client-side settings stored server-side in AoC.

```shell
<%=cmd%> aoc user settings list
<%=cmd%> aoc user settings show <%=ph :id%>
<%=cmd%> aoc user settings modify <%=ph :id%> @json:'{"value":"..."}'
```

> [!NOTE]
> The AoC API endpoint `client_settings` filters entries by two implicit criteria:
>
> - **User identity**: derived from the OAuth bearer token (the authenticated user).
> - **Application identity**: derived from the `client_id` used during authentication.
>
> This means that settings stored by one client application (for example, the AoC web UI) are not visible to another (for example, <%=tool%> using a different `client_id`).
> By default, <%=tool%> uses the pre-registered global `client_id` (see option `--use-generic-client` of plugin `aoc`).

#### Example: Create a sub access key in a `node`

Creation of a sub-access key is like creation of an access key, with the following differences: authentication to the Node API is made with an access key (the master access key), and only the path parameter is provided, relative to the storage root of the master key (`id` and `secret` are optional).

```shell
<%=cmd%> aoc admin node do %name:'<%=ph :node_name%>' v3 access_keys create @: storage.path=/folder1
```

#### Example: Display transfer events (ops/transfer)

```shell
<%=cmd%> aoc admin node do <%=ph :node_id%> v3 transfer list --query.q='*' --query.max=5
```

Examples of query:

```json
{"q":"type(file_upload OR file_delete OR file_download OR file_rename OR folder_create OR folder_delete OR folder_share OR folder_share_via_public_link)","sort":"-date"}
```

```json
{"tag":"aspera.files.package_id=LA8OU3p8w"}
```

#### Example: Display node events (events)

```shell
<%=cmd%> aoc admin node do <%=ph :node_id%> v3 events
```

#### Example: Display members of a workspace

```shell
<%=cmd%> aoc admin workspace_membership list --fields=member_type,manager,member.email --query=@json:'{"embed":"member","inherited":false,"workspace_id":11363,"sort":"name"}'
```

```text
╭─────────────┬─────────┬──────────────────────────╮
│ member_type │ manager │ member.email             │
╞═════════════╪═════════╪══════════════════════════╡
│ user        │ true    │ john.curtis@email.com    │
│ user        │ false   │ someuser@example.com     │
│ user        │ false   │ jean.dupont@me.com       │
│ user        │ false   │ another.user@example.com │
│ group       │ false   │                          │
│ user        │ false   │ aspera.user@gmail.com    │
╰─────────────┴─────────┴──────────────────────────╯
```

Other query parameters:

```json
{"workspace_membership_through":true,"include_indirect":true}
```

#### Example: Add all members of a workspace to another workspace

a- Get ID of first workspace

```shell
WS1='First Workspace'
WS1ID=$(<%=cmd%> aoc admin workspace list --query=@json:'{"q":"'"$WS1"'"}' --select=@json:'{"name":"'"$WS1"'"}' --fields=id --format=csv)
```

b- Get ID of second workspace

```shell
WS2='Second Workspace'
WS2ID=$(<%=cmd%> aoc admin workspace list --query=@json:'{"q":"'"$WS2"'"}' --select=@json:'{"name":"'"$WS2"'"}' --fields=id --format=csv)
```

c- Extract membership information

```shell
<%=cmd%> aoc admin workspace_membership list --fields=manager,member_id,member_type,workspace_id --query=@json:'{"workspace_id":'"$WS1ID"'}' --format=jsonpp --out.file=ws1_members.json
```

d- Convert to creation data for second workspace:

```shell
grep -Eve '(direct|effective_manager|_count|storage|"id")' ws1_members.json|sed '/workspace_id/ s/"'"$WS1ID"'"/"'"$WS2ID"'"/g' > ws2_members.json
```

Or, using `jq`:

```shell
jq '[.[] | {member_type,member_id,workspace_id,manager,workspace_id:"'"$WS2ID"'"}]' ws1_members.json > ws2_members.json
```

e- Add members to second workspace

```shell
<%=cmd%> aoc admin workspace_membership create --bulk=yes @json:@file:ws2_members.json
```

#### Example: Get users who did not log in since a date

```shell
<%=cmd%> aoc admin user list --fields=email --query=@json:'{"q":"last_login_at:<2018-05-28"}'
```

```text
╭──────────────────────────╮
│ email                    │
╞══════════════════════════╡
│ John.curtis@acme.com     │
│ Jean.Dupont@tropfort.com │
╰──────────────────────────╯
```

#### Example: List **Limited** users

```shell
<%=cmd%> aoc admin user list --fields=email --select=@json:'{"member_of_any_workspace":false}'
```

#### Example: Create a group, add to workspace and add user to group

- Create the group and take note of `id`

```shell
<%=cmd%> aoc admin group create @json:'{"name":"group 1","description":"<%=ph :description%>"}'
```

Group: `<%=ph :group_id%>`

- Get the workspace ID

```shell
<%=cmd%> aoc admin workspace show %name:"<%=ph :workspace_name%>" --fields=id
```

Or (similar, but may return several entries, as it is a simple search):

```shell
<%=cmd%> aoc admin workspace list --query.q="<%=ph :workspace_name%>" --fields=id
```

Workspace: <%=ph :workspace_id%>

- Add group to workspace

```shell
<%=cmd%> aoc admin workspace_membership create @json:'{"workspace_id":<%=ph :workspace_id%>,"member_type":"group","member_id":<%=ph :group_id%>}'
```

- Get a user's ID

```shell
<%=cmd%> aoc admin user list --query=@json:'{"q":"manu.macron@example.com"}' --fields=id --format=csv --out.level=data
```

User: <%=ph :user_id%>

- Add user to group

```shell
<%=cmd%> aoc admin group_membership create @json:'{"group_id":<%=ph :group_id%>,"member_type":"user","member_id":<%=ph :user_id%>}'
```

#### Example: Owners and managers of a group

An owner or a manager of a group can manage its members, an owner can also modify or delete the group.
A `group_permission` gives the level `owner` or `manager` on a group to a user or a group (`entity_type` and `entity_id`).
Organization administrators are owners of all groups, without `group_permission`.

- List the owners and managers of a group (tab **Managers** of the group in the web UI)

```shell
<%=cmd%> aoc admin group_permission list --query=@json:'{"group_id":<%=ph :group_id%>,"embed[]":["entity"],"sort":"entity_name"}' --fields=id,level,entity_type,entity.name
```

- Make a user manager of a group

```shell
<%=cmd%> aoc admin group_permission create @json:'{"group_id":<%=ph :group_id%>,"entity_type":"user","entity_id":<%=ph :user_id%>,"level":"manager"}'
```

- Change the level of a permission (only the level can be changed)

```shell
<%=cmd%> aoc admin group_permission modify <%=ph :permission_id%> @json:'{"level":"owner"}'
```

- Revoke a permission

```shell
<%=cmd%> aoc admin group_permission delete <%=ph :permission_id%>
```

#### Example: Perform a multi Gbps transfer between two remote shared folders

In this example, a user has access to a workspace where two shared folders are located on different sites, for example, different cloud regions.

First, set up the environment (skip if already done), see [AoC configuration: Using Wizard](#aoc-configuration-using-wizard):

```shell
<%=cmd%> config wizard @: url=https://sedemo.ibmaspera.com plugin=aoc preset=aoc_sedemo --username=someuser@example.com
```

This creates the option preset `aoc_sedemo` to allow seamless command line access and sets it as default for Aspera on Cloud.

Then, create two shared folders located in two regions, in your files home, in a workspace.

Then, transfer between those:

```shell
<%=cmd%> -Paoc_sedemo aoc files transfer push 'IBM Cloud SJ' --to-folder='AWS Singapore' 100GB.file --ts=@json:'{"target_rate_kbps":1000000,"multi_session":10,"multi_session_threshold":1}'
```

#### Example: Delete all registration keys

```shell
<%=cmd%> aoc admin client_registration_token list --fields=id --format=csv|<%=cmd%> aoc admin client_registration_token delete @lines:@stdin: --bulk=yes
```

```text
╭─────┬─────────╮
│ id  │ status  │
╞═════╪═════════╡
│ 99  │ deleted │
│ 100 │ deleted │
│ 101 │ deleted │
│ 102 │ deleted │
╰─────┴─────────╯
```

#### Example: Create a tethered Node

Follow these steps to configure a new HSTS and link it to your existing Aspera on Cloud (AoC) organization.

- Retrieve the Organization Public Key

  First, obtain the organization's public key.
  This key is used to verify bearer tokens generated by your organization.
  This key remains constant for the lifetime of your Organization.

```shell
<%=cmd%> aoc admin organization show --fields=oauth_token_verification_key --out.secrets=yes --out.file=mypubkey.pem
```

  It can also be retrieved from an existing node:

```shell
<%=cmd%> aoc admin node do %name:'<%=ph :node_name%>' v3 access_keys show self --fields=token_verification_key --out.secrets=yes --out.file=mypubkey.pem
```

- Create an Access Key on the Self-Managed HSTS

  Create the local credentials on your High-Speed Transfer Server (HSTS).

> [!TIP]
> In this command, "master node credentials" allowing access key creation are used.
> The `id` and `secret` parameters are optional.
> If you omit them, you must add `--out.secrets=yes` to the command.
> Record the generated secret immediately; it cannot be retrieved later, only reset.

```shell
<%=cmd%> node access_keys create @: id=<%=ph :access_key_id%> secret=<%=ph :secret%> storage.type=local storage.path=/data/aoc token_verification_key=@file:mypubkey.pem
```

- Register the Node in AoC

  Now, register the physical server as a node object within the Aspera on Cloud administration interface.

```shell
<%=cmd%> aoc admin node create @: url=https://aspera.example.com access_key=<%=ph :access_key_id%> name=testnode1
```

- Configure Access Key Permissions

  Assign the necessary permissions to the root file ID for your new access key.
  This ensures the system and node owner have the correct authorization.

> [!TIP]
> The following two commands are executed using access key credentials.
> If the node is configured for admin user, then add options: `--username=<%=ph :access_key_id%> --password=<%=ph :secret%>`.

```shell
<%=cmd%> node access_keys do self permission / create @: access_type=user access_id='F4 System'
```

```shell
<%=cmd%> node access_keys do self permission / create @: access_type=user access_id=NODE_OWNER
```

- Optional next steps

  To register an Aspera Event Journal (AEJ) as described in the HSTS manual, refer to:

  - [Create a registration key for a tethered node](#example-create-registration-key-to-register-a-tethered-node)

  - [The Aspera HSTS Operations GitHub repository](https://github.com/laurent-martin/aspera-hsts-operations/blob/main/README.md#create-a-node-registration-token).

#### Example: Create registration key to register a tethered node

The following command will create and display a secret token to register a self-managed Aspera Transfer Server:

```shell
<%=cmd%> aoc admin client_registration_token create @json:'{"data":{"name":"laurentnode","client_subject_scopes":["alee","aejd"],"client_subject_enabled":true}}' --fields=token --out.secrets=yes
```

#### Example: Create an ATS Node

AoC nodes are composed of two related entities:

- An access key created on the Transfer Server (HSTS/ATS)
- A `node` resource in the AoC application.

The web UI allows creation of both entities in one shot.
For more flexibility, <%=tool%> allows this in two separate steps.

> [!NOTE]
> When selecting **Use existing access key** in the web UI, this skips access key creation (first step).

So, for example, the creation of a node using ATS in IBM Cloud looks like (see other example in this manual):

- Create the access key on ATS

The creation options are the ones of ATS API, refer to the [section on ATS](#ats-access-key-creation-parameters) for more details and examples.

```shell
<%=cmd%> aoc admin ats access_key create @json:'{"storage":{"type":"ibm-s3","bucket":"mybucket","credentials":{"access_key_id":"<%=ph :access_key_id%>","secret_access_key":"<%=ph :secret%>"},"path":"/"}}' --cloud=softlayer --region=eu-de
```

Once executed, the access key `id` and `secret`, randomly generated by the Node API, are displayed.

> [!NOTE]
> Once returned by the API, the secret will not be available anymore, so store it securely.
> ATS secrets can only be reset by asking IBM support.

- Create the AoC node resource

First, retrieve the ATS node address:

```shell
<%=cmd%> aoc admin ats cluster show --cloud=softlayer --region=eu-de --fields=transfer_setup_url --format=csv
```

Then use the returned address for the `url` key to create the AoC Node resource:

```shell
<%=cmd%> aoc admin node create @json:'{"name":"myname","access_key":"<%=ph :access_key%>","ats_access_key":true,"ats_storage_type":"ibm-s3","url":"https://ats-sl-fra-all.aspera.io"}'
```

Creation of a node with a self-managed node is similar, but the command `aoc admin ats access_key create` is replaced with `node access_keys create` on the private node itself.

#### Example: Deactivate an application in a workspace

This is a two-step procedure:

1. Find the application ID in the workspace:

   ```shell
   <%=cmd%> aoc admin workspace show <%=ph :workspace_id%> --query.include_aspera_apps=true --fields=packages_app.id
   ```

   Or, alternatively:

   ```shell
   <%=cmd%> aoc admin application instance list --query.aspera_app_type=packages --query.workspace_id=<%=ph :workspace_id%> --fields=id --out.level=data
   ```

   This displays the <%=ph :app_id%>.

2. Deactivate the application:

   ```shell
   <%=cmd%> aoc admin application instance packages modify <%=ph :app_id%> @: enabled=false inherit_organization_app_settings=false
   ```

### List of files to transfer

Source files are provided as a list with the `sources` option.
By default, the list of files is provided on the command line.
See [File list](#list-of-files-for-transfers).

### Packages app

The Aspera on Cloud **Packages** app lets you assemble copies of any number of files and folders into a digital "package" and send the package to others, pretty much like a web-mail application.

> [!NOTE]
> All `aoc packages` commands operate in a workspace context. The workspace is inferred
> automatically when a default workspace is configured in the application. If no default is
> set, provide one explicitly with `--workspace=NAME`. List available workspaces with
> `<%=cmd%> aoc user workspaces list`.

#### Send a Package

General syntax:

```shell
<%=cmd%> aoc packages send <%=ph :package_extended_value%> <%=ph :options%> <%=ph :file_list%>
```

Package creation parameters are sent as a **Command Parameter**.
See the AoC package creation API, or display an existing package in JSON to list attributes.

List allowed shared inbox destinations with:

```shell
<%=cmd%> aoc packages shared_inboxes list
```

Use fields: `recipients` and/or `bcc_recipients` to provide the list of recipients: **user** or **shared inbox**:

- Provide either IDs as expected by API: `"recipients":[{"type":"dropbox","id":"<%=ph :shbox_id%>"}]`
- or names only: `"recipients":["The Dest"]`.

<%=cmd%> will resolve the list of email addresses and dropbox names to the expected type/ID list, based on case-insensitive partial match.

If a user recipient (email) is not already registered and the workspace allows external users, then the package is sent to an external user, and:

- If the option `new_user_option` is `--new-user-option.package_contact=true` (**default**), then a public link is sent and the external user does not need to create an account.
- If the option `new_user_option` is `@json:{}`, then external users are invited to join the workspace.

##### Example: Send a package with one file to two users, using their email

```shell
<%=cmd%> aoc packages send @json:'{"name":"<%=ph :title%>","note":"<%=ph :note%>","recipients":["someuser@example.com","other@example.com"]}' <%=ph :file_path%>
```

##### Example: Send a package to a shared inbox with metadata

```shell
<%=cmd%> aoc packages send --workspace="<%=ph :workspace_name%>" @json:'{"name":"<%=ph :title%>","recipients":["Shared Inbox With Meta"],"metadata":{"Project Id":"123","Type":"Opt2","CheckThose":["Check1","Check2"],"Optional Date":"2021-01-13T15:02:00.000Z"}}' ~/Documents/Samples/200KB.1
```

It is also possible to use identifiers and API parameters.
For example, sending to a shared inbox by ID with metadata:

```shell
<%=cmd%> aoc packages send --workspace="<%=ph :workspace_name%>" @json:'{"name":"<%=ph :title%>","recipients":[{"type":"dropbox","id":"12345"}],"metadata":[{"input_type":"single-text","name":"Project Id","values":["123"]},{"input_type":"single-dropdown","name":"Type","values":["Opt2"]},{"input_type":"multiple-checkbox","name":"CheckThose","values":["Check1","Check2"]},{"input_type":"date","name":"Optional Date","values":["2021-01-13T15:02:00.000Z"]}]}' ~/Documents/Samples/200KB.1
```

##### Example: Send a package with files from the Files app

Find files in Files app:

```shell
<%=cmd%> aoc files browse /src_folder
```

```text
╭──────────────┬──────┬────────────────┬──────────────┬──────────────────────┬──────────────╮
│ name         │ type │ recursive_size │ size         │ modified_time        │ access_level │
╞══════════════╪══════╪════════════════╪══════════════╪══════════════════════╪══════════════╡
│ sample_video │ link │                │              │ 2020-11-29T22:49:09Z │ edit         │
│ 100G         │ file │                │ 107374182400 │ 2021-04-21T18:19:25Z │ edit         │
│ 10M.dat      │ file │                │ 10485760     │ 2021-05-18T08:22:39Z │ edit         │
│ Test.pdf     │ file │                │ 1265103      │ 2022-06-16T12:49:55Z │ edit         │
╰──────────────┴──────┴────────────────┴──────────────┴──────────────────────┴──────────────╯
```

To send a package with the file `10M.dat` from subfolder /src_folder:

```shell
<%=cmd%> aoc files node_info /src_folder --format=json --out.level=data --out.secrets=yes | <%=cmd%> aoc packages send @json:'{"name":"test","recipients":["someuser@example.com"]}' 10M.dat --transfer=@json:@stdin: --transfer.agent=node
```

#### Receive packages

The command to receive one or multiple packages is:

```shell
<%=cmd%> aoc packages recv <%=ph :package_id%> [<%=ph :file%> ...]
```

Where `<%=ph :package_id%>` is the identifier of the package to receive or `ALL` to receive all packages matching the query.
Option `once_only` is supported, see below.

To download only some files from the package, add the path of the files on the command line: `[<%=ph :file%> ...]`, see option `sources`.
By default, all files in the package are downloaded, that is, `.` is used as the file list.

##### Option `package_folder`

The `package_folder` option (`Hash`) controls how downloaded packages are organized into subfolders under the path specified by `to_folder`.

- If `package_folder` is not specified or is an empty `Hash`, packages are downloaded directly into the folder defined by `to_folder`.
- If specified, packages are stored in dynamically generated subfolders.

**Supported Fields**:

<%=schema_to_table('aoc_opts:components.schemas.PackageFolderOptions')%>

**Examples**:

- `{"fld":["id"]}`
  - The subfolder name is the unique package ID.
  - Downloading the same package (same ID) multiple times places it in the same folder.
- `{"fld":["name"]}`
  - The subfolder name is the package name.
  - If multiple packages share the same name, their contents are downloaded into the same folder.
- `{"fld":["name","id"]}`
  - The subfolder name is `<%=ph :name%>.<%=ph :id%>`.
  - This guarantees uniqueness when package names are identical.
- `{"fld":["name","id"],"opt":true}`
  - The subfolder name is initially the package name.
  - If a folder with that name already exists, the name and ID (`<%=ph :name%>.<%=ph :id%>`) are used instead.
- `{"fld":["name"],"seq":true,"opt":true}`
  - The subfolder name is the package name if it does not already exist.
  - If it exists, a sequence number is appended (for example, `<%=ph :name%>.1`, `<%=ph :name%>.2`, and so on).
  - Downloading the same package multiple times results in different folders when a conflict occurs.

##### Example: Receive all packages from a given shared inbox

```shell
<%=cmd%> aoc packages recv ALL --workspace=_workspace_ --once-only=yes --lock-port=12345 --query=@json:'{"dropbox_name":"_shared_inbox_name_","archived":false,"received":true,"has_content":true,"exclude_dropbox_packages":false,"include_draft":false}' --ts=@json:'{"resume_policy":"sparse_csum","target_rate_kbps":50000}'
```

To list packages that would be downloaded, without downloading them, replace `recv ALL` with `list` (keep options `once_only` and `query`).

##### Receive new packages only (Cargo)

It is possible to automatically download new packages, like using Aspera Cargo:

```shell
<%=cmd%> aoc packages recv ALL --once-only=yes --lock-port=12345
```

- `ALL` (case-sensitive) will download all packages
- `--once-only=yes` keeps memory of any downloaded package in persistency files located in the configuration folder
- `--lock-port=12345` ensures that only one instance is started at the same time, to avoid running two downloads in parallel

Typically, one would execute this command on a regular basis, using the method of your choice: see [Scheduler](#scheduler).

##### Example: Content of a received Package

Some `node` operations are available for a package, such as `browse` and `find`.

To list the content of a package, use command `packages browse <%=ph :package_id%> <%=ph :folder%>`.
Example:

```shell
<%=cmd%> aoc packages browse xx5CnbeWng /
```

Use command `find` to list recursively.

For advanced users, it is also possible to pipe node information for the package and use node operations:

```shell
<%=cmd%> aoc packages node_info <%=ph :package_id%> / --format=json --out.secrets=yes --out.level=data | <%=cmd%> node -N --preset=@json:@stdin: access_keys do self browse /
```

#### List packages

By default, when using `aoc packages list` or `aoc packages receive ALL`, the following `query` is performed:

| Query parameter            | Value                                         |
|----------------------------|-----------------------------------------------|
| `archived`                 | `false` |
| `has_content`              | `true`  |
| `received`                 | `true`  |
| `completed`                | `true`  |
| `workspace_id`             | Set based on current workspace.               |
| `dropbox_id`               | Set according to `dropbox_name`, if provided. |
| `exclude_dropbox_packages` | `true` unless `dropbox_id` is provided.       |

Parameters provided using option `query` override this query.
To remove a parameter, set it to `null`.

##### Example: List packages in a given shared inbox

When user packages are listed, the following query is used:

```json
{"archived":false,"exclude_dropbox_packages":true,"has_content":true,"received":true}
```

To list packages in a shared inbox, the query has to be specified with the shared inbox by name or its identifier.
Additional parameters can be specified, as supported by the API (to find out available filters, consult the API definition, or use the web interface in developer mode).
The current workspace is added unless specified in the query.

> [!NOTE]
> By default, `exclude_dropbox_packages` is set to `true` for user packages, and to `false` for shared inbox packages.
> This can be overridden in the query.

Using shared inbox name:

```shell
<%=cmd%> aoc packages list --query=@json:'{"dropbox_name":"My Shared Inbox","archived":false,"received":true,"has_content":true,"exclude_dropbox_packages":false,"include_draft":false,"sort":"-received_at"}'
```

Using shared inbox identifier: first retrieve the ID of the shared inbox, and then list packages with the appropriate filter.

```shell
shared_box_id=$(<%=cmd%> aoc packages shared_inboxes show %name:'My Shared Inbox' --format=csv --out.level=data --fields=id)
```

```shell
<%=cmd%> aoc packages list --query=@json:'{"dropbox_id":"'$shared_box_id'","archived":false,"received":true,"has_content":true,"exclude_dropbox_packages":false,"include_draft":false,"sort":"-received_at"}'
```

### Files app

The Files application presents a **Home** folder to users in a given workspace.
Files located here are either user's files, or shared folders.

> [!NOTE]
> All `aoc files` commands operate in a workspace context. The workspace is inferred
> automatically when a default workspace is configured in the application. If no default is
> set, provide one explicitly with `--workspace=NAME`. List available workspaces with
> `<%=cmd%> aoc user workspaces list`.
> All commands under `files` are the same as under `access_keys do self` for plugin `node`, that is, **gen4/access key** operations.

#### Download Files

The general download command is:

```shell
<%=cmd%> aoc files download <%=ph :source_folder_path%> <%=ph :source_filename_1%> ...
```

That is, the first argument is the source folder, and the following arguments are the source file names in this folder.

If a single file or folder is to be downloaded, then a single argument can be provided.

```shell
<%=cmd%> aoc files download <%=ph :single_file_path%>
```

#### Shared folders

In Aspera on Cloud (AoC), Shared Folders allow users to collaborate on content via Private or Public links.

- **Private links**: Require the collaborator to log in to access the folder.
- **Public links**: Include a passcode that allows access without an account or login.

##### Management Scopes

Shared folders can be managed through two primary administrative scopes:

- User Shared Folders: Users share personal folders with others in the same workspace using `aoc files permission`.
- Admin Shared Folders: Administrators share folders from any node in a workspace using `aoc admin node do <%=ph :node_id%> permission`.

Technically, shared folders are managed as [permissions](https://developer.ibm.com/apis/catalog/aspera--aspera-node-api/Introduction) on a specific node.
When a permission is created, AoC generates a link in the recipient's home folder to that shared folder.

##### Permission Payloads

When creating a Shared Folder, <%=tool%> expects a `Hash` payload (typically passed via `@json:` or `@:`) similar to the one used at API level.

**API-level Payload Example**:

```json
{
  "file_id": "50",
  "access_levels": ["list","read","write","delete","mkdir","rename","preview"],
  "access_type": "user",
  "access_id": "john@example.com",
  "tags": {...}
}
```

**Field Mapping & Helper Fields**:

<%=tool%> automatically populates (Auto) several native fields and provides helper fields to simplify the process:

| Field           | Type     | Description                                                          |
|-----------------|----------|----------------------------------------------------------------------|
| `file_id`       | Native<%=br%>Auto     | The ID of the folder, automatically resolved from the path provided in the command. |
| `access_levels` | Native<%=br%>Optional | List of access levels to set for the shared folder.<%=br%>Defaults to full access. |
| `tags`          | Native<%=br%>Auto     | Set with expected values for AoC: username who creates, and workspace in which the shared folder is created. |
| `access_type`   | Native<%=br%>Required | Type of access, such as `user`, `group`, or `workspace`.<%=br%>Can be set with parameter `with`. |
| `access_id`     | Native<%=br%>Required | ID of the user, group, or workspace (see `with`) |
| `with`          | <%=tool%>           | Recipient of shared folder. Can be a username, a group name, or a workspace name.<%=br%><%=tool%> will resolve the name to the proper type and ID in fields `access_type` and `access_id`.<%=br%>If the value is the empty string, then it declares the shared folder in the workspace (first action to do, see below). |
| `link_name`     |  <%=tool%>          | Name of the link file created in the user's home folder for private links. |
| `as`            |  <%=tool%>          | Name of the link file created in the user's home folder for admin shared folders. |

To declare or create the shared folder in the workspace, a special value for `access_id` is used: `ASPERA_ACCESS_KEY_ADMIN_WS_[workspace ID]`, with an `access_type` of `user`.
This is conveniently set by <%=tool%> using an **empty string** for field `with`.
To share a folder with a different user, special tags are set, but this is conveniently done by <%=tool%> using the `as` field.

##### User Shared Folders

Personal shared folders, created by users in a workspace, follow the syntax:

```shell
<%=cmd%> aoc files permission --workspace=<%=ph :workspace_name%> <%=ph :path_to_folder%> ...
```

> [!NOTE]
> The workspace is identified by name, and folder by path, relative to the user's home.
> To use an identifier instead, one can use the [percent selector](#percent-selector), like `%id:<%=ph :ws_id%>`.

##### Admin Shared Folders

Admin shared folders, created by administrators in a workspace, follow the syntax:

```shell
<%=cmd%> aoc admin node do <%=ph :node_id%> permission --workspace=<%=ph :workspace_name%> <%=ph :path_to_folder%>
```

> [!TIP]
> The node is identified by identifier.
> To use a name instead, one can use the [percent selector](#percent-selector), like `%name:"<%=ph :node_name%>"`.
> The folder is identified by its path; a file ID can be specified instead, with `%id:123`.
> If the ID is left blank: `%id:`, then it means `*`, that is, "all".

##### Example: List permissions on a user shared folder

```shell
<%=cmd%> aoc files permission /shared_folder_test1 list
```

##### Example: Share a personal folder with other users

```shell
<%=cmd%> aoc files permission /shared_folder_test1 create @json:'{"with":"laurent"}'
```

##### Example: Revoke shared access

```shell
<%=cmd%> aoc files permission /shared_folder_test1 delete 6161
```

##### Example: Public and Private short links

They can be managed with commands:

```shell
<%=cmd%> aoc files short_link <%=ph :path_to_folder%> private create
<%=cmd%> aoc files short_link <%=ph :path_to_folder%> private list
<%=cmd%> aoc files short_link <%=ph :path_to_folder%> public create @json:'{...}'
<%=cmd%> aoc files short_link <%=ph :path_to_folder%> public list
<%=cmd%> aoc files short_link <%=ph :path_to_folder%> public delete <%=ph :id%>
<%=cmd%> aoc files short_link <%=ph :path_to_folder%> public modify <%=ph :id%> @json:'{...}'
```

Only `public` short links can be modified.
An optional payload can be provided at creation, for example to protect with a password, set an expiry date or set the access level.

A password can be provided on `create` and `modify` for `public` links:

```json
{"password":"<%=ph :password%>"}
```

To remove a password:

```json
{"password_enabled":false}
```

By default, access level is set to `edit`.
Change the default access level by providing the parameter: `access_levels` in payload.
`access_levels` can be:

- A single `String`: one of the shortcuts: `edit`, `preview`, `download`, `upload`.
- An Array: any custom combination of: `delete`, `list`, `mkdir`, `preview`, `read`, `rename`, `write`.

For example:

```json
{"access_levels":"upload"}
```

```json
{"access_levels":["list","rename"]}
```

An expiration date can be set with parameter `expires_at`, using [ISO 8601](https://en.wikipedia.org/wiki/ISO_8601) format.
For example, `2025-08-29T08:10:31.000Z`.
If only a date is provided, for example: `2025-08-29`, it will be set to midnight UTC of that date, that is, `2025-08-29T00:00:00.000Z`.

##### Example: Create a workspace admin shared folder

First, identify the node ID where the shared folder will be created.

To get the node ID of the default node for workspace `<%=ph :workspace_name%>`, use the command:

```shell
<%=cmd%> aoc admin workspace show %name:'<%=ph :workspace_name%>' --fields=node_id
```

> [!TIP]
> This syntax first lists workspaces using API selector `q`,
> and then performs an exact match on the specified field: `name`.

Alternatively:

```shell
<%=cmd%> aoc admin workspace list --select.name="<%=ph :workspace_name%>" --fields=node_id
```

> [!TIP]
> This syntax lists all workspaces,
> and then performs an exact match on the specified field: `name`.

Alternatively:

```shell
<%=cmd%> aoc admin workspace list --query.q="<%=ph :workspace_name%>" --fields=node_id
```

> [!TIP]
> This syntax first lists workspaces using API selector `q`.
> It may return several items as the query is case insensitive and made on several fields as substring.

Or select a node identifier manually from the list of nodes:

```shell
<%=cmd%> aoc admin node list --fields=id,name
```

In the following commands, replace:

- `<%=ph :node_id%>` with the node ID, or with `%name:<%=ph :node_name%>`.
- `<%=ph :workspace_name%>` with the workspace name, or with `%id:<%=ph :workspace_id%>`.
- `<%=ph :folder_path%>` with the path of the folder to share on the node (for example, `/my_folder` or `my_folder`). It can also be a folder deeper than level 1.

If the shared folder does not exist, then create it:

```shell
<%=cmd%> aoc admin node do <%=ph :node_id%> mkdir <%=ph :folder_path%>
```

Create the shared folder in workspace `<%=ph :workspace_name%>` (set `with` to empty string, or do not specify it).
**Optionally**, use `as` to set the name of the shared folder if different from the folder name on the node.
For other options, refer to the previous section on shared folders.

```shell
<%=cmd%> aoc admin node do <%=ph :node_id%> permission <%=ph :folder_path%> create @json:'{"with":"","as":"folder_for_users"}' --workspace="<%=ph :workspace_name%>"
```

> [!NOTE]
> The previous command only declares the shared folder in the workspace, but does not share it with anybody.

To share with a user, group, or workspace, use the `with` parameter with the name of a resource to share with (non-empty value).
The `"with"` parameter will perform a lookup, and set fields `access_type` and `access_id` accordingly.
The native fields `access_type` and `access_id` can also be used, instead of `with`.

```shell
<%=cmd%> aoc admin node do <%=ph :node_id%> permission <%=ph :folder_path%> create @json:'{"with":"john@example.com","as":"folder_for_one_user"}' --workspace="<%=ph :workspace_name%>"
```

```shell
<%=cmd%> aoc admin node do <%=ph :node_id%> permission <%=ph :folder_path%> create @json:'{"with":"group 1","as":"folder_for_a_group"}' --workspace="<%=ph :workspace_name%>"
```

```shell
<%=cmd%> aoc admin node do <%=ph :node_id%> permission <%=ph :folder_path%> create @json:'{"with":"<%=ph :workspace_name%>","as":"folder_for_all_workspace"}' --workspace="<%=ph :workspace_name%>"
```

> [!NOTE]
> In the previous commands, field `as` is optional.

##### Example: List all workspace admin shared folders in a workspace

```shell
<%=cmd%> aoc admin workspace shared_folder %name:'<%=ph :workspace_name%>' list
```

```text
╭───────┬───────────┬─────────┬─────────┬───────────┬──────────────────────────────────────╮
│ id    │ node_name │ node_id │ file_id │ file.path │ tags.aspera.files.workspace.share_as │
╞═══════╪═══════════╪═════════╪═════════╪═══════════╪══════════════════════════════════════╡
│ 198   │ eudemo    │ 8666    │ 2465    │ /project1 │                                      │
│ 785   │ eudemo    │ 8666    │ 9       │ /folder2  │ project2                             │
│ 4788  │ eudemo    │ 8666    │ 3691    │ /backup   │                                      │
╰───────┴───────────┴─────────┴─────────┴───────────┴──────────────────────────────────────╯
```

To list members:

```shell
<%=cmd%> aoc admin workspace shared_folder %name:'<%=ph :workspace_name%>' member 198 list
```

```text
╭─────────────┬──────────────────────────────────┬──────────────┬──────────────────────╮
│ access_type │ access_id                        │ access_level │ last_updated_at      │
╞═════════════╪══════════════════════════════════╪══════════════╪══════════════════════╡
│ user        │ ASPERA_ACCESS_KEY_ADMIN_WS_45071 │ edit         │ 2020-11-29T22:48:49Z │
│ group       │ 160270                           │ edit         │ 2024-05-13T15:58:02Z │
╰─────────────┴──────────────────────────────────┴──────────────┴──────────────────────╯
```

If you have the node ID of the shared folder, then it is equivalent to:

```shell
<%=cmd%> aoc admin node do 8666 permission /project1 list --query=@json:'{"tag":"aspera.files.workspace.id=<%=ph :workspace_id%>"}'
```

##### Example: List all workspace admin shared folders on a node

First get the workspace identifier:

```shell
<%=cmd%> aoc admin workspace list --select=@json:'{"name":"<%=ph :workspace_name%>"}' --fields=id
```

```text
<%=ph :workspace_id%>
```

Then, identify the node ID on which to list, see previous section.

Finally, list all shared folders, as permissions:

```shell
<%=cmd%> aoc admin node do <%=ph :node_id%> permission %id: list --query=@json:'{"access_type":"user","access_id":"ASPERA_ACCESS_KEY_ADMIN_WS_<%=ph :workspace_id%>"}'
```

> [!NOTE]
> See Node API: `GET /permissions` for all `query` options.
> The folder identifier is left empty `%id:`, to apply to all folders.

#### Cross Organization transfers

It is possible to transfer files directly between organizations without having to first download locally and then upload...

Although optional, the creation of [Option Preset](#option-preset) is recommended to avoid placing all parameters in the command line.

Procedure to send a file from org1 to org2:

- Get access to Organization 1 and create an [Option Preset](#option-preset), for example `org1` (for instance, using the [Wizard](#wizard))
- Check that access works and locate the source folder `<%=ph :source_folder%>` and the file `<%=ph :source_file%>` in it, for example, using command `files browse`
- Get access to Organization 2 and create an [Option Preset](#option-preset), for example `org2`
- Check that access works and locate the destination folder `<%=ph :dest_folder%>`
- Execute the following:

```shell
<%=cmd%> -Porg1 aoc files node_info <%=ph :source_folder%> --format=json --out.level=data --out.secrets=yes | <%=cmd%> -Porg2 aoc files upload <%=ph :source_file%> --to-folder=<%=ph :dest_folder%> --transfer=@json:@stdin: --transfer.agent=node
```

Explanation:

- <%=tool%> is the command executed by the shell
- `-Porg1` loads options for preset `org1` (URL and credentials)
- `aoc` uses the Aspera on Cloud plugin
- `files node_info <%=ph :source_folder%>` generates transfer information for the source folder: Node API URL, credentials and root file ID, suitable for the next command
- `--format=json` formats the output as JSON (instead of the default text table)
- `--out.level=data` displays only the result, removing other information such as workspace name
- `|` pipes the standard output of the first command into the second one
- `-Porg2 aoc` uses the Aspera on Cloud plugin and loads credentials for `org2`
- `files upload <%=ph :source_file%> --to-folder=<%=ph :dest_folder%>` uploads the file `<%=ph :source_file%>` (located in `<%=ph :source_folder%>` of `org1`) to `<%=ph :dest_folder%>` in `org2`
- `--transfer=@json:@stdin:` reads the Node API information from standard input (JSON) and uses it as parameters of the transfer agent
- `--transfer.agent=node` selects the `node` transfer agent: the source node of `org1` pushes the file to `org2`

#### Find Files

The command `aoc files find` allows searching for files in a given workspace.

It works also on `node` resource:

```shell
<%=cmd%> aoc admin node do %name:'<%=ph :node_name%>' find ...
```

For instructions, refer to section `find` for plugin `node`.

<%=include_commands_for_plugin(:aoc)%>

