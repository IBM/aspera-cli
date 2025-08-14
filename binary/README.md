# Single executable `ascli`

Build the CLI tool as a compiled single executable.

## Tooling

See <https://www.tebako.org/>.
A container version is provided for [`tebako`](https://github.com/tamatebako/tebako).

## Usage: (non-Windows)

```bash
cd binary
v=4.23.0 
git checkout v$v
make GEM_VERSION=$v
```

## Legacy

Initially, `rubyc` (gem [`ruby-packer`](https://github.com/pmq20/ruby-packer) and [you54f's version](https://github.com/you54f/ruby-packer)) was used to build a single executable.
