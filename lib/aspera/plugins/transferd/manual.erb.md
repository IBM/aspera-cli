## Plugin: `transferd`: Transfer Daemon

Plugin `transferd` installs the IBM Aspera Transfer Daemon (`transferd`, which includes `ascp`) and runs it as a system service.
See [Installing `ascp` through `transferd`](#installing-ascp-through-transferd) and [Transfer Daemon as a system service](#transfer-daemon-as-a-system-service).

The plugin also has client commands for a running daemon (for example one installed with `transferd service install`):

| Command                         | Action                                                              |
|---------------------------------|---------------------------------------------------------------------|
| `info`                          | Version of the API and information on the instance of the daemon.   |
| `transfers show <transfer_id>`  | Status of a transfer: the daemon keeps it for some time after its end. |
| `transfers cancel <transfer_id>`| Stop a transfer.                                                    |

They use the options `url` (mandatory, endpoint of the daemon, e.g. `127.0.0.1:55002`), `api_key` (if the daemon enables `authentication`) and `ca_file` (if the daemon enables `tls`).
If a key is not given, it is taken from the same key of the option `--transfer`, when its agent is `transferd` (e.g. a preset used for transfers).
The options of the plugin have priority.
The daemon has no call to list the transfers.
These commands require the gem `grpc`: it is loaded only when one of them runs, so that the other commands do not need it.
If it is missing: `gem install grpc`.

```bash
<%=cmd%> transferd info --url=127.0.0.1:55002 --api-key=@vault:transferd.api_key
```

> [!NOTE]
> Commands `config transferd ...` and `config ascp install` are deprecated aliases of `transferd ...` and `transferd install`.

<%=include_commands_for_plugin(:transferd)%>

