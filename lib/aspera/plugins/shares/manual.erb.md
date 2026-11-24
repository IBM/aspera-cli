## Plugin: `shares`: IBM Aspera Shares v1

Aspera Shares supports the **Node API** for the file transfer part.

Supported commands are listed in the Shares API documentation:

<https://developer.ibm.com/apis/catalog/aspera--aspera-shares-api/Introduction>

The payload for creation is the same as for the API: parameters are provided as a positional `Hash`.

Example: Create a Node: Attributes are like API:

| Attribute    | Required | Default |
|--------------|----------|---------|
| `name`       | Yes      |         |
| `host`       | Yes      |         |
| `api_username` | Yes    |         |
| `api_password` | Yes    |         |
| `port`       |          | `9092`  |
| `ssl`        |          | `true`  |
| `verify_ssl` |          | `false` |
| `timeout`    |          | `30s`   |
| `open_timeout` |        | `10s`   |

Example: Create a share, grant access to a user and list user permissions on it.

```shell
<%=cmd%> shares admin share create @json:'{"node_id":1,"name":"test1","directory":"test1","create_directory":true}'

user_id=$(<%=cmd%> shares admin user all show %username:john@example.com --fields=id --out.level=data)

<%=cmd%> shares admin share user_permissions %name:test1 create @json:'{"user_id":'$user_id',"browse_permission":true,"download_permission":true,"upload_permission":true}'

<%=cmd%> shares admin share user_permissions %name:test1 list
```

Share permissions are granted, modified and revoked on the share, with `share user_permissions` and `share group_permissions` (`create`, `list`, `show`, `modify`, `delete`).
They are identified by the user or group identifier: e.g. `show %username:john@example.com`.
Permissions not specified on creation take their default value.
Available permissions: `browse_permission`, `download_permission`, `upload_permission`, `mkdir_permission`, `delete_permission`, `rename_permission`, `content_availability_permission`, `manage_permission`.

> [!NOTE]
> The permissions of a user or group on all shares are listed with `user all share_permissions` and `group all share_permissions`.
> These are read-only (`list` and `show`): to change them, use `share user_permissions` and `share group_permissions`.

Example: Give a user (`jane@example.com`) the same share permissions as another user (`john@example.com`), using `jq`.

```shell
new_user_id=$(<%=cmd%> shares admin user all show %username:jane@example.com --fields=id --out.level=data)
<%=cmd%> shares admin user all share_permissions %username:john@example.com list --format=json --out.level=data |
  jq -c '.[]' | while read -r permission; do
    <%=cmd%> shares admin share user_permissions "$(jq .share_id <<< "$permission")" create @json:"$(jq -c --argjson id "$new_user_id" '{user_id: $id} + with_entries(select(.key | endswith("_permission")))' <<< "$permission")"
  done
```

### Authentication of SAML users

By default, `shares` authenticates with `username` and `password`.
A user that has only a SAML identity (no local password) can authenticate with a web browser: `--auth=web`.

```shell
<%=cmd%> shares --url=https://shares.example.com --auth=web files browse /
```

Option `ui.web_auth` selects how the result of the login is received (see [Web login flow](#web-login-flow)):

- `port` (default): automatic when the browser runs on the same system as <%=tool%>.
  <%=tool%> listens on a local port (`--redirect-uri`, default: `http://localhost:12345`), opens the SAML login page of Shares (`/auth/saml`) in the browser with this URL in `RelayState`, and receives the OAuth tokens there.
  The host of `redirect_uri` shall be loopback: `localhost`, an address of `127.0.0.0/8`, or `[::1]`.
- `paste`: the browser may run on another system than <%=tool%> (for example, <%=tool%> runs on a server accessed with SSH), without tunnel.
  No local port is opened and `--redirect-uri` is not used.
  <%=tool%> generates a random `state` and opens the SAML login page with `RelayState` `aspera://device-code?state=<state>`.
  After login, Shares displays a code (a long text of letters, digits, `-` and `_`), and tells how long the code and the session token are valid. The user copies the code and pastes it in the prompt of <%=tool%> ([hidden](#hidden-input), as the code contains a token).
  The mark of the prompt becomes `✓` if the code is valid, else `✗`. A code that is not valid is asked again.
  If standard input is not a terminal, the code is read from it.
  <%=tool%> checks that the `state` of the code is the one it generated.
  The code is valid for **15 to 30 minutes** after its display: it is encrypted with a key derived from the `state` and from the current time in slots of 15 minutes (the previous and the next slot are also accepted).
  So the clocks of the Shares server and of the system that runs <%=tool%> shall be correct (less than 15 minutes apart), and the code shall be pasted soon after the login, otherwise <%=tool%> reports an expired code or a wrong clock, and the login shall be done again.
  The code is also protected against typing errors and modification.

The token is saved, and renewed with its refresh token: the browser is opened again only if this fails.
Shares gives a token and a refresh token that both expire after 24 hours: then a new login is needed, unless the token is refreshed before (see `token_refresh_max_age` in [HTTP socket parameters](#http-socket-parameters)).
Option `username` is optional: with it, the token is saved for this user.

> [!IMPORTANT]
> Shares does not have the OAuth authorization code grant: both ways require a specific patch of Shares, which returns the tokens when `RelayState` is a loopback URL (`port`) or `aspera://device-code?state=<state>` (`paste`).
> The patch is the file [`docs/shares/zz_saml_cli_relay_state.rb`](shares/zz_saml_cli_relay_state.rb) of the GitHub repository.
> It is temporary code, provided until an equivalent function is officially released in Shares.
> It modifies no file of Shares: to install it, copy it to `<shares_rails_root>/config/initializers/` on the Shares server and restart Shares; to remove it, delete the file and restart Shares.
> With a Shares without the patch, <%=tool%> reports that no token was received.
> This feature works only with this patch: it is not a standard function of Shares, and it has not been validated on a released version of Shares yet.
> It may change with the final implementation in Shares: the `RelayState` values, the format of the code (and so its validity and its encryption) and the returned fields can differ, and <%=tool%> will then be adapted. Do not rely on the current format outside of <%=tool%>.
> The tokens given by Shares go through the browser (in the URL, or in the code): <%=tool%> immediately exchanges the refresh token for a new token, so that the tokens that were visible are not valid any more.

<%=include_commands_for_plugin(:shares)%>

