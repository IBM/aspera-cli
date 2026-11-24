## Plugin: `server`: IBM Aspera High Speed Transfer Server (SSH)

The `server` plugin is used for operations on Aspera HSTS using SSH authentication.

It is the original way of accessing an Aspera Server, often used for **server to server** transfers.
An SSH session is established, authenticated with either a password or an SSH private key.
Then, commands `ascp` (for transfers) and `ascmd` (for file operations) are executed.

> [!IMPORTANT]
> If you have Node API credentials, or Access Key/Secret, use the plugin: `node`.
> This plugin is exclusively using SSH credentials.

The URL to be provided with option `url` shall be like `ssh://<%=ph :server_address%>:33001`, then option `username` is used to specify the transfer user, and finally either option `password` or `ssh_keys` (with one or several paths) for the authentication.

Typically:

```shell
<%=cmd%> server --url=ssh://hsts.example.com:33001 --username=john --password=<%=ph :password%> ...
```

```shell
<%=cmd%> server --url=ssh://hsts.example.com:33001 --username=john --ssh-keys=~/.ssh/id_rsa ...
```

<%=include_commands_for_plugin(:server)%>

### Authentication on Server with SSH session

If SSH is the session protocol (by default, that is, not WSS), then the following session authentication methods are supported:

- `password`: SSH password
- `ssh_keys`: SSH keys (Multiple SSH key paths can be provided.)

If `username` is not provided then the default transfer user `xfer` is used.

If neither SSH password nor key is provided and a transfer token is provided in transfer spec (option `ts`), then the standard SSH bypass keys are used.

Example:

```shell
<%=cmd%> server --url=ssh://<%=ph :server_address%>:33001 ... --ts=@json:'{"token":"Basic <%=ph :token%>"}'
```

> [!NOTE]
> If you need to use the Aspera public keys, then specify an empty token:
> `--ts=@json:'{"token":""}'` : Aspera public SSH keys will be used, but the protocol will ignore the empty token.

The value of the `ssh_keys` option can be a single value or an `Array`.
Each value is a **path** to a private key and is expanded (`~` is replaced with the user's home folder).

Examples:

```shell
<%=cmd%> server --ssh-keys=~/.ssh/id_rsa
<%=cmd%> server --ssh-keys=@list:,~/.ssh/id_rsa
<%=cmd%> server --ssh-keys=@json:'["~/.ssh/id_rsa"]'
```

For file operation commands (browse, delete), the Ruby SSH client library `Net::SSH` is used and provides several options settable using option `ssh_options` (additive option like `ts`).

For a list of SSH client options, refer to the Ruby documentation of [Net::SSH](http://net-ssh.github.io/net-ssh/Net/SSH.html#method-c-start).

Among the 50 available SSH options:

<%=schema_to_table('server_opts:components.schemas.SshOptions')%>

By default, the SSH library will check if a local `ssh-agent` is running.

On Linux, if you get an error message such as:

```text
ERROR -- net.ssh.authentication.agent: could not connect to ssh-agent: Agent not configured
```

Or on Windows:

```text
ERROR -- net.ssh.authentication.agent: could not connect to ssh-agent: pageant process not running
```

This means that your environment suggests using an agent, but no SSH agent is running. In that case:

- Check env var: `SSH_AUTH_SOCK`
- Check your file: `$HOME/.ssh/config`
- Check if the SSH key is protected with a passphrase (then, use the `passphrase` SSH option)
- [Check the Ruby SSH options in start method](https://github.com/net-ssh/net-ssh/blob/master/lib/net/ssh.rb)
- To disable the use of `ssh-agent`, use the option `ssh_options` like this:

```shell
<%=cmd%> server --ssh-options=@json:'{"use_agent": false}' ...
```

> [!TIP]
> This can also be set using a preset.

If one of the SSH private keys is passphrase-protected, then option `passphrase` can be used.
It is equivalent to setting both options `ssh_options.passphrase` and `ts.ssh_private_key_passphrase`.

### Analyze `ascp` logs of the server

Command `logs` analyzes the `ascp` log files of the server (`ascp` 4.0 and later), instead of those of the local machine: the files are read over the SSH connection of the plugin (same `url`, `username`, `password` or `ssh_keys`, and `ssh_options`), then analyzed like with [`config ascp logs`](#agent-direct-transfer). It has the same sub-commands (`summary`, `sessions`, `diagnostics`, `health`, `records`, ...) and the same option `ascp_logs`.
Paths of the files on the server are mandatory: there is no default location, as it depends on the installation (e.g. a syslog file such as `/var/log/aspera.log` or `/var/log/messages`, or a file of the folder given with `ascp -L`).
Files compressed with gzip (rotations) are supported. A folder is not read, give its files.

```shell
<%=cmd%> server --url=ssh://<%=ph :server_address%>:33001 --username=root --ssh-keys=~/.ssh/id_rsa logs summary /var/log/aspera.log
<%=cmd%> server ... logs sessions /var/log/aspera.log /var/log/aspera.log-20261101.gz --select=@json:'{"status":"failed"}'
```

The user must be allowed to read the files (log files are often readable by `root` only), and the server shall provide a shell with `head` (and `stat`).
The files are copied to a temporary folder, removed after the analysis.
The size of the files is limited (total of 256 MB by default), to avoid reading huge logs in memory: the limit is the key `remote_max_size` (in bytes) of option `ascp_logs`, e.g. `--ascp-logs.remote_max_size=1000000000`.
The modification date of each file is kept, as the year of syslog lines is deduced from it.
Not available with `--url=local:` and `https`.

### Other session channels for `server`

URL schemes `local` and `https` are also supported (mainly for testing purposes).
(`--url=local:`, `--url=https://...`)

- `local` will execute `ascmd` locally, instead of using an SSH connection.
- `https` will use Web Socket Session:
  This requires the use of a transfer token.
  For example, a `Basic` token can be used.

As SSH is used most of the time, if an `http` scheme is provided without a token, the plugin falls back to SSH and port 33001.

### Examples: `server`

One can test the `server` application using the well-known demo server:

```shell
<%=cmd%> config initdemo
<%=cmd%> server browse /aspera-test-dir-large
<%=cmd%> server download /aspera-test-dir-large/200MB
```

`initdemo` creates an [Option Preset](#option-preset) `demoserver` and sets it as default for plugin `server`.

If an SSH private key is used for authentication with a passphrase, the passphrase needs to be provided to both options: `ssh_options` (for browsing) and `ts` (for transfers):

```shell
<%=cmd%> server --url=ssh://<%=ph :server_address%>:33001 --username=<%=ph :username%> --ssh-keys=<%=ph :private_key_path%> --passphrase=<%=ph :passphrase%>
```

