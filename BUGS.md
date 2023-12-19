# Reporting bugs and security vulnerabilities

Report bug, including vulnerability issues following this:

Please, make sure to include the following information:

* `aspera-cli` version number.
* Operating system name/version (`uname -a` if Unix)
* relevant section of output of error with option `--log-level=debug`
* `ascp` log files (if transfer-related)
* Any other relevant information.

IMPORTANT: Remove any confidential information from the logs before posting them.

[Use Github (Public Issue Reporting)](https://github.com/IBM/aspera-cli/issues)

## Scope of Support

Architecture of `ascli` :
![architecture](docs/architecture.png)

The scope is exclusively the Ruby gem `aspera-cli` (green) and its **_interactions_** with IBM components:

* `ascp`
* transfer SDK
* Aspera Enterprise components
* Aspera on Cloud
* IBM COS
* ...

I.e. the scope is not the IBM components themselves (blue).

I.e. anything that can be fixed or enhanced by modification if code in `aspera-cli`.

For example, if `ascp` fails to transfer a file, there are two possibilities:

* `ascp` cannot transfer due to a configuration on the server side, in which case the bug should be reported to IBM
* `ascli` is not using it correctly (missing or wrong parameter provided to `ascp`), in which case the bug should be reported to this project

## Security Policy

| Version | Supported          |
| ------- | ------------------ |
| >= 4.0  | :white_check_mark: |
| < 4.0   | :x:                |
