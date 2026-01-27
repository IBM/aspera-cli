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
