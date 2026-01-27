# Container image build

The `Dockerfile.tmpl.erb` template enables building the container image using either a local `.gem` file or by fetching the gem from <rubygems.org>.

> [!NOTE]
> An `ERB` (embedded Ruby) template is used as it allows some level of customization to tell where to take the gem from.

Available tasks:

```bash
bundle exec rake -T ^container
```

The repository can be displayed with:

```shell
bundle exec rake container:repo
```

## Image build

To build the image for a released version:

Check out that version using the version tag:

```shell
git checkout v4.23.0
```

Prepare the Ruby environment:

```shell
bundle config set without optional:special
bundle config set disable_shared_gems true
bundle install
```

Check the version:

```shell
bundle exec rake tools:version
```

Build the container image:

```shell
bundle exec rake container:build
```

This command performs the following steps:

- Uses the version specified in the current repository.
- Builds the container image using this version of the gem retrieved from <rubygems.org>. This creates the `Dockerfile` from the template.
- Tags the image with both the specific version and `latest`.

Push to the image registry (both tags: version and `latest`):

```shell
bundle exec rake container:push
```

## Image build using current branch

The task `container:build` takes two optional arguments:

- `source`: `local` (use local gem file) or `remote` (download from <rubygems.org>)
- `version`: Version number

Example: Build using local version and sources

```shell
bundle exec rake container:build'[local]'
```

Example: Build using another remote version

```shell
bundle exec rake container:build'[remote,4.24.2]'
```

> [!NOTE]
> When using a version argument, other tasks will use the same version. (memory).

To push a version built previously:

```shell
bundle exec rake container:push
```
