# Chocolatey package

The package `aspera-cli` installs the Windows portable package of `ascli` (`rake windowszip:portable`), attached to the GitHub release:

- `tools/chocolateyInstall.ps1` downloads the zip of the release, checked with its SHA-256, and extracts it in the folder of the package.
- Only `ascli` is added to the `PATH` (`Install-BinFile` to `ascli.cmd`): the executables of the package (`ruby.exe`, `ascp.exe`, `transferd.exe`...) get a `.ignore` file, so that Chocolatey does not shim them.
- No dependency: Ruby, gems, the Transfer SDK and the Visual C++ runtime are in the zip.

Templates: `install.erb.ps1`, `uninstall.erb.ps1`, `package.erb.nuspec` (ERB).

## Build

```shell
rake chocolatey:build[<VERSION>]
rake chocolatey:build[<VERSION>,<ZIP_FILE>]
```

The zip is the one given, else the one in `pkg/` (built locally), else the one of the GitHub release (downloaded).
The package sources are in `tmp/build_chocolatey`, and the `.nupkg` in `pkg/` if `choco` is available (Windows).

## Release

Workflow `Release Packages` (`.github/workflows/packages.yml`), job `chocolatey`, after the Windows portable package is attached to the release:

1. Builds the package.
2. Installs it from the local `.nupkg`, checks `ascli --version`, `ascli config ascp info`, and that no other executable is on the `PATH`, then uninstalls it.
3. Pushes it to the Chocolatey community repository, for a final version, if the repository secret `CHOCOLATEY_API_KEY` is set.

For an existing release, run the workflow manually with only `chocolatey` selected: the zip already attached to the release is used, and not built again.

The community repository moderates each version before it is public (automated checks, then a human review for new packages or after changes).

## API key

- Sign in to the [Chocolatey Community Repository](https://community.chocolatey.org/).
- Account > API Keys: copy the API key.
- In GitHub: repository Settings > Secrets and variables > Actions: add secret `CHOCOLATEY_API_KEY`.
