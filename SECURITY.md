# Security Policy

## Supported Versions

Security fixes are released in a new version of `aspera-cli`.
They are not backported to older versions.

| Version        | Supported                        |
| -------------- | -------------------------------- |
| Latest release | ✅                               |
| Older releases | ❌ Upgrade to the latest release |

Supported Ruby versions are listed in the manual: [Ruby](docs/README.md#ruby).

## Reporting a Vulnerability

**Do not report a security vulnerability in a public GitHub issue, discussion or pull request.**

Report it privately on GitHub: [Report a vulnerability](https://github.com/IBM/aspera-cli/security/advisories/new).
For instructions, see [Privately reporting a security vulnerability](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability).

Alternatively, report it to the IBM Product Security Incident Response Team (PSIRT) using one of the methods on the [IBM Trust Center](https://www.ibm.com/trust/security-psirt).

Include in the report:

- The `aspera-cli` version: `ascli -v`
- The Ruby version: `ruby -v`
- The operating system name and version
- The steps to reproduce, or a proof of concept
- The expected impact

Remove secrets (passwords, tokens, private keys) from logs and configuration files before you send them.

## Scope

In scope: the Ruby gem `aspera-cli` (the `ascli` command), and how it interacts with IBM Aspera components.
See [Scope of Support](BUGS.md#scope-of-support).

Out of scope:

- Vulnerabilities in the IBM Aspera products themselves (`ascp`, Transfer SDK, High-Speed Transfer Server, Faspex, Shares, Console, Orchestrator, Aspera on Cloud) and in IBM Cloud Object Storage: report them to IBM PSIRT.
- A public CVE in a dependency gem that already has a fixed version: dependencies are updated with Renovate, and the update is included in the next release.

## Trust Model

Trusted: the user account that runs `ascli`, its environment variables, and its configuration file and presets.
`ascli` restricts access to its configuration file to the current user, and can store secrets in a vault: see [Secret Vault](docs/README.md#secret-vault).

Commands and options are trusted only at security level `low`, the default: see [Security Level](docs/README.md#security-level).

- At level `low`, `ascli` can do anything that the user is allowed to do: features that execute code or access local files (for example `@ruby:`, `@file:`, plugins) work as designed.
- At levels `medium` and `high`, commands and options can come from an untrusted client, for example an MCP client.

`ascli` is not intended to be a public-facing web server.
The web servers that some commands start listen on a loopback address by default, and refuse to listen on another address without their protection: see [Web service](docs/README.md#web-service).

In scope:

- At levels `medium` and `high`: a command or option that bypasses the restrictions of the level, for example to read a file outside `allowed_paths`, write a file outside `writable_paths`, execute code, or reveal a secret.
- At any level: an issue that a party other than the local user can exploit, for example through a server response, a file received in a transfer, or a position on the network path when TLS certificate verification is enabled.

Out of scope:

- A feature that works as designed at level `low`.
- An issue that requires the user to disable a protection, for example `--insecure=yes`.
- A web server of `ascli` exposed to users or networks that are not trusted, without the protection of its command, or with HTTP instead of HTTPS on a network.
