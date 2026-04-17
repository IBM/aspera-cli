# AppImage Build

This directory contains the source files for building an AppImage package of Aspera CLI.

## Files

- `AppRun` - The main entry point script for the AppImage
- `ascli.desktop` - Desktop entry file for the AppImage
- `build.sh` - Container build script that runs inside the container

## Building

To build the AppImage package:

```bash
rake appimage:build
```

## Testing

To test the built AppImage:

```bash
rake appimage:test
```

## Release

To upload the AppImage to a GitHub release:

```bash
rake appimage:release
```

## Requirements

- `podman` or `docker`
- Internet connection (for downloading Ruby source and dependencies)

## Architecture

The build process uses a containerized environment (Ubuntu 20.04) to ensure consistency and portability.
The AppImage includes:

- Ruby 3.2.2 compiled from source
- `aspera-cli` gem and all dependencies
- Required system libraries (OpenSSL, `libyaml`, etc.)
