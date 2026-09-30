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
bundle exec rake binary:build
```

To build a given version:

```bash
bundle exec rake binary:build'[4.23.0]'
```

## Ocran

Alternative build with [`ocran`](https://github.com/largo/ocran), `.tgz` output:

```bash
bundle exec rake binary:ocran'[4.27.3]'
```

On Linux, the executable bundles all shared libraries except `glibc`: it runs on systems with a `glibc` at least as recent as the build system's.
So, the archive name includes the `glibc` version of the build system, e.g. `aspera-cli-4.27.3-linux-x86_64-glibc2.28.tgz`.
The archive also contains a `README.ascli.md` for users, generated from [`README.ascli.erb.md`](README.ascli.erb.md).

The GitHub action [`packages.yml`](../../.github/workflows/packages.yml) builds it in a RHEL 8 container (`glibc` 2.28), and attaches it to the GitHub release.
It runs when a release is published, or manually with a version.

## History

Initially, `rubyc` (gem [`ruby-packer`](https://github.com/pmq20/ruby-packer) and [you54f's version](https://github.com/you54f/ruby-packer)) was used to build a single executable.
