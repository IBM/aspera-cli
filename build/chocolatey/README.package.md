# aspera-cli (Chocolatey Package)

This package installs the **Aspera CLI (`ascli`) Ruby gem** via Chocolatey, making it easy to install and use on Windows systems.

## 📦 What this package does

- Installs Ruby (via Chocolatey dependency, if not already present)
- Installs the `aspera-cli` Ruby gem
- Makes the `ascli` command available in your terminal

## 🚀 Installation

### System-wide (default)

Requires Administrator rights:

```powershell
choco install aspera-cli
```

- Installs for **all users**  
- Package location: `C:\ProgramData\chocolatey\lib\aspera-cli`  
- Executable shims: `C:\ProgramData\chocolatey\bin`

### Per-user (no admin required)

Installs only for the current user:

```powershell
choco install aspera-cli --user
```

- Package location: `C:\Users\<username>\chocolatey\lib\aspera-cli`  
- Executable shims: `C:\Users\<username>\chocolatey\bin`  
- Only the current user can run `ascli` from the command line

## ✅ Usage

After installation, run:

```powershell
ascli --help
```

## 🔄 Upgrading

System-wide:

```powershell
choco upgrade aspera-cli
```

Per-user:

```powershell
choco upgrade aspera-cli --user
```

## 🗑️ Uninstall

System-wide:

```powershell
choco uninstall aspera-cli
```

Per-user:

```powershell
choco uninstall aspera-cli --user
```

## ⚙️ Requirements

- Windows OS  
- Chocolatey  
- Ruby (installed automatically via dependency if missing)

## 🧱 How it works

This package is a thin wrapper around the Ruby gem:

```powershell
gem install aspera-cli --no-document
```

Ruby is installed via Chocolatey if not already available.

## 🐞 Troubleshooting

### `ascli` not found after install

- Restart your terminal  
- Ensure Ruby’s `bin` directory is in your PATH

### Ruby issues

Reinstall Ruby if necessary:

```powershell
choco install ruby
```

## 📚 Project links

- Source: <https://github.com/you/aspera-cli>  
- RubyGem: <https://rubygems.org/gems/aspera-cli>

## 📄 License

This package follows the same license as the upstream project.

## 🙌 Maintainer

Maintained by the Aspera CLI authors and contributors.
