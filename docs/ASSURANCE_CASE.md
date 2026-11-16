# Security Assurance Case

This document gives the reasons to believe that `ascli` meets its security requirements.
The security policy, the trust model, and the scope of vulnerability reports are in [SECURITY.md](../SECURITY.md).
The structure of the code is in [ARCHITECTURE.md](ARCHITECTURE.md).

## Security Requirements

`ascli` is a command line tool, run by a user, that calls the APIs of IBM Aspera products and transfers files.

1. Credentials (passwords, tokens, private keys) used by `ascli` are not revealed to other parties.
2. Communications with servers are protected against interception and modification.
3. A party other than the local user cannot execute code, or read or write local files, through `ascli`.
4. A client that is not fully trusted (for example an AI client of the MCP server) can only use the features that the security level allows.

## Threat Model

| Actor | Trust | Examples of threats |
| ----- | ----- | ------------------- |
| Local user who runs `ascli` | Trusted | Out of scope: the user can do anything that the account allows. |
| Other local users | Not trusted | Read the configuration file, the secrets, or temporary files. |
| Network attacker | Not trusted | Intercept or change requests and responses (man in the middle). |
| Aspera server, and other servers | Trusted for their own data | Malicious response or file that leads to code execution, or to a write outside the destination folder. |
| MCP client, or a program that passes commands (security level `medium` or `high`) | Partially trusted | Read local files, execute code, reveal secrets, write files where a later use executes them. |
| Web browser of the user (OAuth login, local web servers) | Trusted, but other local or remote clients are not | Forged authorization responses (CSRF), access to a local web server from the network. |

## Trust Boundaries

- **Process boundary**: the user account, its environment variables, and its configuration folder are trusted. Everything that comes from outside the process is input.
- **Network boundary**: all API calls use HTTPS, with verification of the server certificate.
- **Client boundary**: at security levels `medium` and `high`, commands and options come from a client that is not fully trusted.
- **Local web servers**: web servers started by some commands (OAuth redirect, MCP over HTTP, Faspex post-processing) listen on the loopback address by default.

## Secure Design Principles

| Principle | How it is applied |
| --------- | ----------------- |
| Least privilege | The [security level](README.md#security-level) restricts file access and code execution. The MCP server uses level `high` by default, and the level cannot be changed by the client. |
| Fail-safe defaults | TLS certificate verification is enabled by default and is disabled only with `--insecure=yes`. Local web servers listen on loopback. Files are written at levels `medium` and `high` only in `writable_paths`, which is empty by default. |
| Complete mediation | The restriction of an option applies whatever the way it is set: command line, preset, dot notation, or `Hash`. The real path of a file is checked: `..` and symbolic links that lead outside the allowed paths are refused. |
| Separation of privilege | Secrets can be stored in a [secret vault](README.md#secret-vault), separate from the configuration. |
| Economy of mechanism | Cryptography is not implemented by `ascli`: it uses Ruby `openssl` (system OpenSSL) and the Aspera transfer engine. |
| Open design | The source code, the security levels, and the trust model are public. |
| Input validation | Options are validated against a schema (types and allowed values). YAML is loaded with `safe_load`, which does not create arbitrary objects. |

## Common Weaknesses Countered

| Weakness | Countermeasure |
| -------- | -------------- |
| [CWE-78](https://cwe.mitre.org/data/definitions/78.html) OS command injection | External commands are executed with an array of arguments, without a shell (`Environment.secure_execute`). Features that execute code are available only at level `low`. |
| [CWE-22](https://cwe.mitre.org/data/definitions/22.html) Path traversal | At levels `medium` and `high`, the real path is checked against `allowed_paths` and `writable_paths`. |
| [CWE-502](https://cwe.mitre.org/data/definitions/502.html) Deserialization of untrusted data | YAML is loaded with `YAML.safe_load` and a short list of permitted classes. JSON is parsed without object creation. |
| [CWE-94](https://cwe.mitre.org/data/definitions/94.html) Code injection | `@ruby:`, ERB templates, proxy auto configuration, and plugins are refused at levels `medium` and `high`. |
| [CWE-295](https://cwe.mitre.org/data/definitions/295.html) Improper certificate validation | Ruby `Net::HTTP` verifies the certificate (`VERIFY_PEER`) before any HTTP header is sent. See [SSL CA certificate bundle](README.md#configuring-the-ssl-ca-certificate-bundle). |
| [CWE-532](https://cwe.mitre.org/data/definitions/532.html) Secrets in logs | Secret values are registered and hidden in logs, results, and error messages. |
| [CWE-276](https://cwe.mitre.org/data/definitions/276.html) Incorrect default permissions | The configuration folder and files are restricted to the current user. Temporary files are created with mode `0600` and exclusive creation. |
| [CWE-352](https://cwe.mitre.org/data/definitions/352.html) Cross-site request forgery (OAuth) | The OAuth web flow sends a random `state` and checks it in the response. PKCE (`S256`) is used when enabled, for example for Faspex 5. |
| [CWE-1104](https://cwe.mitre.org/data/definitions/1104.html) Unmaintained third-party components | Dependencies are gems, updated with Renovate. |

## Evidence

- Static analysis: CodeQL (`.github/workflows/codeql-analysis.yml`) and RuboCop, in CI.
- Tests: integration tests (`tests/tests.yml`) and unit tests (`spec/`), including tests of the security levels. Statement coverage is shown in the [README](../README.md) badge.
- Signed gem releases: see [Verifying gem installation signature](README.md#verifying-gem-installation-signature).
- Vulnerability reports are handled as described in [SECURITY.md](../SECURITY.md).
