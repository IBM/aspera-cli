## Description

<!-- What does this pull request change, and why? Link the related issue, if any. -->

## Checklist

See [CONTRIBUTING.md](../CONTRIBUTING.md#development-cycle-for-a-new-cli-command).

- [ ] Tests added or updated (`tests/tests.yml`, `spec/`)
- [ ] Documentation updated in `docs/README.erb.md` (not `docs/README.md`; the section of a bundle's plugin is in `lib/aspera/plugins/<name>/manual.erb.md`, included by `docs/README.erb.md`)
- [ ] `CHANGELOG.md` updated
- [ ] `bundle exec rake tools:rubocop` passes
- [ ] No secret in the changes
