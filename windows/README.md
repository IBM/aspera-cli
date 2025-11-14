# Aspera CLI installation on Windows

## Overview

It will install all the necessary components:

- Ruby
- Gems
- MS C++ libraries
- `ascp`
- add to PATH

## Installation using the `powershell` script

To execute the installer in a `cmd` window:

```batch
powershell -ExecutionPolicy Bypass -File "install.ps1"
```

To execute the installer in a `powershell` window:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## Installation using the `cmd` script

Edit the installation script: `install.bat` to change the target installation folder if required.

Then execute it:

```bat
CD aspera-cli-installer
install.bat
```

Then add the path to bin to your PATH to find `ascli`.
