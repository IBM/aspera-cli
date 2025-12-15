# Single executable `ascli`

Build the CLI tool as a compiled single executable.

## Tooling

See <https://www.tebako.org/>.
A container version is provided for [`tebako`](https://github.com/tamatebako/tebako).

## Usage: (non-Windows)

To build a given version using the current Rakefile:

```bash
cd package/binary
rake GEM_VERSION=4.23.0
```

To build a given version using the Rakefile of that version:

```bash
git checkout v4.23.0
cd package/binary
rake
```

## History

Initially, `rubyc` (gem [`ruby-packer`](https://github.com/pmq20/ruby-packer) and [you54f's version](https://github.com/you54f/ruby-packer)) was used to build a single executable.
