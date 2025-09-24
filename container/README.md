# Container image build

The template: `Dockerfile.tmpl.erb` allows building the container image either using a local gem file or from <rubygems.org>.

## Default image build

Build the image:

```bash
make
```

This does the following:

- Install the gem version from local gem file or <rubygems.org>.
- Build the image for the local version number in the current repository or the remote one
- creates tags for both the version and `latest`

> [!NOTE]
> This target creates the `Dockerfile` from an `ERB` (embedded Ruby) template.
> A template is used as it allows some level of customization to tell where to take the gem from.

Then, to push to the image registry (both tags: version and `latest`):

```bash
make push
```

## Specific version image build

To build a specific version: override `make` macro `GEM_VERSION`:

```bash
make GEM_VERSION=4.11.0
make push GEM_VERSION=4.11.0
```

> [!NOTE]
> This does not use the locally generated gem file.
> Only the local build file and Makefile versions are used.
> The gem is installed from <rubygems.org>.
> This also sets the `latest` tag.

## Development version image build

To build/push a beta/development container:
it does not create the `latest` tag, it uses the gem file generated locally with a special version number.

```bash
make beta_build
make beta_test
make beta_push
```
