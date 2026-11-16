# Governance

`aspera-cli` is an open source project of IBM, hosted in the [IBM GitHub organization](https://github.com/IBM), under the [Apache License 2.0](LICENSE).

## Roles

| Role | Who | Responsibilities |
| ---- | --- | ---------------- |
| **Maintainer** | Listed in [`.github/CODEOWNERS`](.github/CODEOWNERS) | Decides the direction of the project (see [TODO.md](TODO.md)), reviews and merges pull requests, triages issues, handles vulnerability reports (see [SECURITY.md](SECURITY.md)), and publishes releases. |
| **Repository administrator** | IBM staff with the administrator role on the repository | Manages access to the repository and its secrets, and appoints maintainers. Ensures the continuity of the project (see below). |
| **Contributor** | Anyone | Reports issues, proposes changes with pull requests, following [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md). |

## Decisions

- Proposals and questions are discussed publicly in [GitHub issues](https://github.com/IBM/aspera-cli/issues) and pull requests.
- The maintainer decides, after the discussion, and gives the reason for the decision in the issue or pull request.
- A change is accepted when it meets the [code review requirements](CONTRIBUTING.md#code-review).
- Security issues are discussed privately, as described in [SECURITY.md](SECURITY.md).

## Continuity

The project can continue if a maintainer is no longer available:

- Several repository administrators (IBM staff) can manage issues, accept pull requests, and appoint a new maintainer.
- Releases are built, signed, and published by GitHub Actions workflows (see [Release](CONTRIBUTING.md#release)), with secrets stored in the repository settings, not by a single person.
- The build, test, and release procedures are documented in [CONTRIBUTING.md](CONTRIBUTING.md).

## Changes to this document

Changes to the governance are proposed with a pull request, and approved by a repository administrator.
