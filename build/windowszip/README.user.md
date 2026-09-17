# Aspera CLI installation on Windows

## Overview

A ZIP file that installs all the necessary components for `ascli`:

- Ruby
- Gems
- MS C++ libraries
- `ascp`
- Add to PATH

## Requirements

- Windows with PowerShell 5.1 or later (built-in since Windows 10)
- Administrator rights (optional, required for system-wide installation only)

## Installation

### Current user (no admin required)

Double-click `setup.cmd`, or from a command prompt:

```bat
setup.cmd
```

Files are installed under `%LOCALAPPDATA%\Aspera\cli` and PATH is updated for the current user only.

### System-wide (all users)

Run `setup.cmd` from an **elevated** command prompt (Run as Administrator):

```bat
setup.cmd -AllUsers
```

Files are installed under `%ProgramFiles%\Aspera\cli` and PATH is updated system-wide.

If `setup.cmd` is launched with administrator rights but without `-AllUsers`, the installer will prompt:

```text
Install for (A)ll users (system-wide) or (C)urrent user? [A/C]
```

## Installation paths

| Mode | Installation folder | PATH scope |
| --- | --- | --- |
| Current user | `%LOCALAPPDATA%\Aspera\cli` | User |
| All users | `%ProgramFiles%\Aspera\cli` | Machine |
