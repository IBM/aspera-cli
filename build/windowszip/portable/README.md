# Aspera CLI for Windows (portable)

This folder contains everything needed to run `ascli`, no installation is required:

- `ruby`: Ruby runtime
- `gems`: `aspera-cli` and its dependencies
- `sdk`: IBM Aspera Transfer SDK (`ascp`, `transferd`)

No administrator rights are needed.

## Usage

Extract the zip anywhere, e.g. in `%LOCALAPPDATA%`, then from a command prompt, in this folder:

```bat
ascli.cmd -v
```

To use `ascli` from any folder, add this folder to the user `PATH` by double-clicking `add_to_path.cmd`, then open a new terminal:

```bat
ascli -v
```

## PowerShell completion

To complete commands of `ascli` when `Tab` is pressed in PowerShell, add this line to the PowerShell profile (edit with `notepad $PROFILE`), once this folder is in the `PATH`:

```powershell
ascli config completion powershell | Out-String | Invoke-Expression
```

This executes `ascli` at each start of PowerShell: to avoid it, save the completion script in a file, see section *Shell Completion* of the manual.

## Configuration

Configuration files are stored in `%USERPROFILE%\.aspera\ascli`, like with a regular installation.

The launcher sets the SDK folder to `sdk` in this folder, unless environment variable `ASCLI_SDK_FOLDER` is already set.

## Uninstall

Delete this folder, and remove it from the user `PATH` if it was added.
