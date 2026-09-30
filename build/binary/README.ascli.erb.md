# `<%= cmd %>` <%= version %>: single executable for `<%= platform %>`

`<%= cmd %>` is the command line interface for IBM Aspera products.

This archive contains:

- `<%= cmd %>`: the executable. It includes the Ruby runtime and the gems: no Ruby installation is needed.
- `<%= readme %>`: this file.

## Requirements

- Platform: `<%= platform %>`<%= ", with `glibc` #{glibc} or later, check with: `ldd --version | head -n1`" if glibc %>.
- A temporary folder on a file system that allows execution (see [Troubleshooting](#troubleshooting)).
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
  The folder is created in `$TMPDIR`, or `/tmp` by default.
- The configuration is stored in `~/.aspera/<%= cmd %>`, like for other installation methods.
- Optional gems are not included, so features requiring them are not available.
  Refer to section *Installing optional gems* of the manual: to use those features, install the Ruby gem instead.

## Troubleshooting

### `Permission denied` at start

```text
FATAL: CreateAndWaitForProcess: execv("/tmp/ocranXXXXXX/bin/ruby") failed: Permission denied
```

The temporary folder is on a file system mounted with `noexec` (frequent on hardened systems), so the extracted Ruby cannot be executed.
Check the mount options of the temporary folder:

```shell
findmnt -no OPTIONS --target "${TMPDIR:-/tmp}"
```

If `noexec` is listed, set `TMPDIR` to a folder on a file system that allows execution, for example in `~/.bashrc`:

```shell
mkdir -p ~/.cache/<%= cmd %>-tmp
export TMPDIR=~/.cache/<%= cmd %>-tmp
```

Then, check that `noexec` is not listed for that folder, with the `findmnt` command above.
<%- if glibc -%>

### `GLIBC_2.xx` not found

```text
<%= cmd %>: /lib64/libc.so.6: version `GLIBC_<%= glibc %>' not found (required by <%= cmd %>)
```

The `glibc` of the system is older than the one required: <%= glibc %>.
Check the version of the system with `ldd --version | head -n1`.
On this system, install the Ruby gem instead.
<%- end -%>

### `certificate verify failed`

The bundled OpenSSL looks for CA certificates in the locations of the build system, which may not exist on this system.
Set env var `SSL_CERT_FILE` to the CA bundle of the system, for example: `/etc/ssl/certs/ca-certificates.crt` on Debian and Ubuntu.
Since version 4.28, this is done automatically when the default locations do not exist.

## Documentation

- Manual: <%= doc_url %> (section *Single file executable*)
- Releases: <%= src_url %>/releases
