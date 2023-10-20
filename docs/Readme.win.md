# Aspera CLI installation on Windows

Edit the installation script: `install.bat` to change the target installation folder if required.

Then execute it:

```bat
CD aspera-cli-installer
install.bat
```

It will install all the necessary components:

- Ruby
- Gems
- MS C++ libs
- ascp

Then add the path to bin to your PATH to find ascli.
