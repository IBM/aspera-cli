# `<%= cmd %>` <%= version %>: single executable for `<%= platform %>`

`<%= cmd %>` is the command line interface for IBM Aspera products.

This archive contains:

- `<%= cmd %>`: the executable. It includes the Ruby runtime and the gems: no Ruby installation is needed.
- `<%= readme %>`: this file.

## Requirements

<%- if glibc -%>
- `glibc` <%= glibc %> or later.
  Otherwise, the executable fails with: ``version `GLIBC_2.xx' not found``.
  To check the version of the system:

  ```shell
  ldd --version | head -n1
  ```

<%- end -%>
- For transfers: `ascp`, from the Aspera Transfer SDK, which is not included (see below).

## Installation

Extract the executable and place it in a folder of the `PATH`, for example:

```shell
tar -xzf <%= archive %>
sudo install -m 755 <%= cmd %> /usr/local/bin/
<%= cmd %> -v
```

Install the Aspera Transfer SDK (`ascp`):

```shell
<%= cmd %> config transferd install
```

Optionally, activate shell completion (`bash`, `zsh` or `fish`):

```shell
eval "$(<%= cmd %> config completion bash)"
```

## Notes

- At each start, the executable extracts its content into a temporary folder, deleted on exit.
  This takes about one second or more, depending on the system.
  The folder is created in `$TMPDIR`, or `/tmp` by default: if it is mounted with `noexec`, set `TMPDIR` to another folder.
- The configuration is stored in `~/.aspera/<%= cmd %>`, like for other installation methods.
- If certificate validation fails (`certificate verify failed`), set env var `SSL_CERT_FILE` to the CA bundle of the system, for example: `/etc/ssl/certs/ca-certificates.crt` on Debian and Ubuntu.
  Since version 4.28, this is done automatically when the default locations of the bundled OpenSSL do not exist.
- Optional gems are not included, so features requiring them are not available.
  Refer to section *Installing optional gems* of the manual: to use those features, install the Ruby gem instead.

## Documentation

- Manual: <%= doc_url %> (section *Single file executable*)
- Releases: <%= src_url %>/releases
