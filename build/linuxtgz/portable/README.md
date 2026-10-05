# Aspera CLI for Linux (portable)

This folder contains everything needed to run `ascli`, no installation is required:

- `ruby`: Ruby runtime, with the shared libraries it needs (e.g. OpenSSL), except `glibc`
- `gems`: `aspera-cli` and its dependencies
- `sdk`: IBM Aspera Transfer SDK (`ascp`, `transferd`)

No root access is needed.

## Requirements

A `glibc` at least as recent as the version in the archive name, e.g. `glibc2.28`, check with: `ldd --version | head -n1`.

## Usage

Extract the archive anywhere, e.g. in `~/.local/share`, then in the extracted folder:

```shell
./ascli -v
```

To use `ascli` from any folder, place a symbolic link to the launcher in a folder of the `PATH`, e.g.:

```shell
ln -s "$PWD/ascli" ~/.local/bin/ascli
ascli -v
```

## Configuration

Configuration files are stored in `~/.aspera/ascli`, like with a regular installation.

The launcher sets the SDK folder to `sdk` in this folder, unless environment variable `ASCLI_SDK_FOLDER` is already set.
So, `ascli config transferd install` is not needed.

## Uninstall

Delete this folder, and the symbolic link if it was created.
