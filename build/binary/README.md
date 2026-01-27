# Single executable `ascli`

Build the CLI tool as a compiled single executable.

## Tooling

See <https://www.tebako.org/>.
A container version is provided for [`tebako`](https://github.com/tamatebako/tebako).

## Usage: (non-Windows)

To build a given version using the build tools of that version:

```bash
git checkout v4.23.0
```

Else, it would use the build tools in the current folder.

To build the version specified in the local folder with gem from rubygems.org:

```bash
rake binary:build
```

To build a given version:

```bash
rake binary:build'[4.23.0]'
```

## History

Initially, `rubyc` (gem [`ruby-packer`](https://github.com/pmq20/ruby-packer) and [you54f's version](https://github.com/you54f/ruby-packer)) was used to build a single executable.
