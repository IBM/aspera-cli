# Aspera CLI portable package for Linux

A `.tgz` archive with everything already installed: extract and run, no installation step, no root access.
It is the Linux equivalent of the [Windows portable package](../windowszip/README.md).

Compared to the [single executable](../binary/README.md) (built with Ocran), nothing is extracted at each start, and it contains the complete Ruby standard library and gems, like a regular installation.

## Build

```bash
rake linuxtgz:portable'[x.y.z]'
```

Version is optional.
If not provided, use the version specified in the current folder.
The gem `pkg/aspera-cli-<version>.gem` is used if present (e.g. during release, before it is published), else it is downloaded from rubygems.org.

Built on Linux, for the architecture of the build system.
Ruby is built from source, so the build system needs: `gcc`, `make`, [`patchelf`](https://github.com/NixOS/patchelf), and development files of `openssl`, `libyaml`, `zlib` and `libffi`.

The package runs on systems with a `glibc` at least as recent as the one of the build system: its version is in the archive name, e.g. `aspera-cli-4.28.0-linux-x86_64-glibc2.28-portable.tgz`.

The GitHub action [`packages.yml`](../../.github/workflows/packages.yml) builds it in a RHEL 8 container (`glibc` 2.28), tests it on RHEL 8 and a recent Ubuntu, and attaches it to the GitHub release.
It runs when a release is published, or manually with a version.

Package content, in a folder named after the archive:

- `ruby`: Ruby built from source with `--enable-load-relative`, so that it runs from any folder, and static `libruby`. Without documentation, C headers and gem cache.
- `ruby/lib`: shared libraries needed by Ruby, its extensions and gems (e.g. `libssl`, `libyaml`, `libffi`, `libz`), except those of `glibc`, copied from the build system. The run path of each binary is set (`patchelf`) to find them relative to its own location (`$ORIGIN`): `LD_LIBRARY_PATH` is not used, so processes started by `ascli` (e.g. `ascp`, a browser) use the libraries of the system. Binaries are stripped.
- `gems`: gems installed at build time by the Ruby of the package, with `--install-dir`, so native extensions are built for it.
- `sdk`: Transfer SDK runtime files extracted, see the [Windows portable package](../windowszip/README.md).

Files in folder `portable` (launcher `ascli`, `README.md`) are copied to the root of the package.
The launcher sets `GEM_HOME` and `GEM_PATH` to folder `gems` and clears the settings of other Ruby installations (`RUBYLIB`, `RUBYOPT`, Bundler).

## Ruby version

Same as the Windows package: the version of `WINDOWS_RUBY_INSTALLER_VERSION` in `Aspera::Cli::Info` of the packaged gem version, without the package number, e.g. `4.0.7` for `4.0.7-1`.

## Aspera SDK version

The version of the Aspera Transfer SDK is the one specified by `SDK_VERSION` in `Aspera::Cli::Info` of the packaged gem version.
