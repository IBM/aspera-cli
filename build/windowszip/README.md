# Aspera CLI installation on Windows

## Overview

A ZIP file that installs all the necessary components for `ascli`:

- Ruby
- Gems
- MS C++ libraries
- `ascp`
- add to PATH

## Build

```bash
rake windowszip:build'[x.y.z]'
```

Version is optional.
If not provided, use the version specified in the current folder.

`README.user.md` is packaged in the zip.

## Ruby version

The version of Ruby packaged in the zip is the one specified by `WINDOWS_RUBY_INSTALLER_VERSION` in `Aspera::Cli::Info` of the packaged gem version (if not present, the one of the current folder is used).
Review it periodically from the [RubyInstaller releases](https://github.com/oneclick/rubyinstaller2/releases): value is the release tag without the `RubyInstaller-` prefix, e.g. `4.0.7-1`.

## Aspera SDK version

The version of the Aspera Transfer SDK is the one specified by `SDK_VERSION` in `Aspera::Cli::Info` of the packaged gem version.
