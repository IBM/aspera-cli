# Container image build

The `Dockerfile.tmpl.erb` template enables building the container image using either a local `.gem` file or by fetching the gem from <rubygems.org>.

> [!NOTE]
> An `ERB` (embedded Ruby) template is used as it allows some level of customization to tell where to take the gem from.

The repository can be displayed with:

```shell
make repo
```

## Image build

To build the image for a released version:

- Check that version out using the version tag:

  ```shell
  git checkout v4.23.0
  ```

- Check the version:

  ```shell
  make version
  ```

- Build the container image:

  ```shell
  make
  ```

  This command performs the following steps:

  - Uses the version specified in the current repository.
  - Builds the container image using this version of the gem retrieved from <rubygems.org>. This creates the `Dockerfile` from the template.
  - Tags the image with both the specific version and `latest`.

- Push to the image registry (both tags: version and `latest`):

  ```shell
  make push
  ```

## Image build using current branch

To build a specific version outside that version branch:
Override `make` macro `GEM_VERSION`:

```shell
v=4.23.0
cd container
make GEM_VERSION=$v
make push GEM_VERSION=$v
```

> [!NOTE]
> This does not use the locally generated gem file.
> Only the local build file and Makefile versions are used.
> The gem is installed from <rubygems.org>.
> This also sets the `latest` tag.

## Image build for development version

To build/push a beta/development container:

```shell
cd container
make beta_build
make beta_test
make beta_push
```

> [!NOTE]
> It does not create the `latest` tag, it uses the gem file generated locally with a special version number.
