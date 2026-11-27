## Plugin: `preview`: Preview generator for AoC

The `preview` plugin is responsible for generating thumbnails (Office documents, images, videos) and video previews on storage, primarily for use within the Aspera on Cloud (AoC) application.
This plugin leverages the **Node API** of Aspera HSTS and requires:

- An Access Key
- The associated **storage root**

### Key Features and Options

You can configure several aspects of the preview generation process:

- File Detection Methods

  Define how new files requiring previews are identified.

- Video Preview Generation Methods
  
  Choose the approach for creating video previews (for example, transcoding options).

- Video Handling Parameters
  
  Fine-tune video processing, such as resolution, bitrate, and format.

Using <%=tool%> is an alternative to <https://github.com/IBM/aspera-on-cloud-file-previews>.

### Aspera Server configuration

Specify the previews folder as shown in:

<https://ibmaspera.com/help/admin/organization/installing_the_preview_maker>

By default, the `preview` plugin expects previews to be generated in a folder named `previews` located in the storage root.
On the transfer server execute:

```shell
PATH=/opt/aspera/bin:$PATH

asconfigurator -x "server;preview_dir,previews"
asnodeadmin --reload
```

> [!NOTE]
> The configuration `preview_dir` is **relative** to the storage root: no leading or trailing `/` is needed.
> Set the value to `previews`.

If another folder is configured on the HSTS, then specify it to <%=tool%> using the option `previews_folder`.

The HSTS Node API limits any preview file to a parameter: `max_request_file_create_size_kb` (1 KB is 1024 Bytes).
This size is internally capped to `1<<24` Bytes (16777216), that is, 16384 KB, that is, 16 MB.

To change this parameter in `aspera.conf`, use `asconfigurator`.
To display the value, use `asuserdata`:

```shell
asuserdata -a | grep max_request_file_create_size_kb
```

```text
  max_request_file_create_size_kb: "1024"
```

```shell
asconfigurator -x "server; max_request_file_create_size_kb,16384"
```

If you use a value different from `16777216`, then specify it using option `max_size`.

> [!NOTE]
> The HSTS parameter (`max_request_file_create_size_kb`) is in **kilo Bytes** while the generator parameter is in **Bytes** (factor of 1024).

### External tools: Linux

<%=tool%> requires the following external tools available in the `PATH`:

- **ImageMagick** v7+: `magick` (for tools: `convert` and `composite`)
- **OptiPNG** : `optipng`
- **FFmpeg** : `ffmpeg` `ffprobe`
- **LibreOffice** : `unoconv`

Installation is shown here for Red Hat/Rocky Linux.

Other OSes should work as well, but are not tested.

To check if all tools are found properly, execute:

```shell
<%=cmd%> preview check
```

#### Image: ImageMagick and `optipng`

```shell
dnf install -y ImageMagick optipng
```

You may also install `ghostscript` which adds fonts to ImageMagick.
Prefer ImageMagick version >=7.
More info on ImageMagick at <https://imagemagick.org/>
Available fonts, used to generate PNG for text, can be listed with:

```shell
magick identify -list font
```

If your OS has only ImageMagick v6, then you can create a script called `magick` and add it to your `PATH`:

```shell
#!/bin/bash
exec "$@"
```

Make it executable:

```shell
chmod a+x /usr/local/bin/magick
```

#### Video: FFmpeg

The installation of `ffmpeg` depends on the distribution of Linux.
On Rocky Linux, you can install `ffmpeg` with:

```shell
dnf install ffmpeg-free
```

Or check which package provides it with:

```shell
dnf provides ffmpeg
```

Another method is to download and install the latest released version of `ffmpeg` with static libraries from [https://johnvansickle.com/ffmpeg/](https://johnvansickle.com/ffmpeg/)

```shell
curl -s https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz|(mkdir -p /opt && cd /opt && rm -f ffmpeg /usr/bin/{ffmpeg,ffprobe} && rm -fr ffmpeg-*-amd64-static && tar xJvf - && ln -s ffmpeg-* ffmpeg && ln -s /opt/ffmpeg/{ffmpeg,ffprobe} /usr/bin)
```

To uninstall above manual installation:

```shell
rm -rf /opt/ffmpeg* /usr/bin/{ffmpeg,ffprobe}
```

#### Office: `unoconv` and LibreOffice

To skip office document preview generation, use option: `--skip-types=office`

The generation of previews is based on LibreOffice's `unoconv`.

- RHEL 8/Rocky Linux 8+

```shell
dnf install unoconv
```

- Amazon Linux

```shell
amazon-linux-extras enable libreoffice
yum clean metadata
yum install libreoffice-core libreoffice-calc libreoffice-opensymbol-fonts libreoffice-ure libreoffice-writer libreoffice-pyuno libreoffice-impress
wget https://raw.githubusercontent.com/unoconv/unoconv/master/unoconv
mv unoconv /usr/bin
chmod a+x /usr/bin/unoconv
```

### Configuration

The preview generator should be executed as a non-root user.
When using object storage, any user can be used, but when using local storage it is usually better to use the user `xfer`, as uploaded files are under this identity: this ensures proper access rights.
The following procedure uses `xfer` as the running user.

Like any <%=tool%> commands, options can be passed on command line or using a configuration [Option Preset](#option-preset).
The configuration file must be created by the same user that runs the generator, so that it is used at runtime.

The `xfer` user has a special protected shell: `aspshell`, so to update the configuration and when changing identity, specify an alternate shell.
For example:

```shell
su -s /bin/bash - xfer

<%=cmd%> config preset set <%=ph :preview_preset_name%> @: url=https://localhost:9092 username=<%=ph :access_key%> password=<%=ph :secret%> skip_types=office lock_port=12346

<%=cmd%> config preset set default preview <%=ph :preview_preset_name%>
```

This example assumes that Office file generation is disabled. Remove `--skip-types=office` if needed.
`lock_port` prevents concurrent execution of generation when using a scheduler.

One can check if the access key is well configured using:

```shell
<%=cmd%> -P<%=ph :preview_preset_name%> node browse /
```

This shall list the contents of the storage root of the access key.

### Options for generated files

When generating preview files, the following options can be modified on command line (or in a preset):

<%=schema_to_table('preview')%>

For video preview with method `reencode`, the whole set of `ffmpeg` options can be overridden with option `reencode_ffmpeg`: it is a `Hash` with two keys: `in` and `out`, each is an `Array` with the native options to `ffmpeg`.

### Execution

<%=tool%> intentionally supports only a **one shot** mode (no infinite loop) in order to avoid having a hanging process or using too many resources (calling REST API too quickly during the scan or event method).
It needs to be run on a regular basis to create or update preview files.
For that use your best reliable scheduler, see [Scheduler](#scheduler).

Typically, for **Access key** access, the system/transfer user is `xfer`.
To be consistent and generate the appropriate access rights, run the generation process as user `xfer`.

To run a one-shot test using the configuration previously created:

```shell
su -s /bin/bash - xfer
```

Or:

```shell
sudo -u xfer /bin/bash
```

Then:

```shell
<%=cmd%> preview scan --overwrite=always
```

When the preview generator is first executed, it creates a file `.aspera_access_key` in the previews folder, which contains the access key used.
On subsequent runs, it reads this file and checks that previews are generated for the same access key, else it fails.
This is to prevent clash of different access keys using the same root.

### Configuration for Execution in scheduler

Details are provided in section [Scheduler](#scheduler).

Shorter commands can be specified if a configuration preset was created as shown previously.

For example, the timeout value can be differentiated depending on the command: event versus scan:

```shell
case "$*" in *trev*) tmout=10m ;; *) tmout=30m ;; esac
```

### Candidate detection for creation or update (or deletion)

<%=tool%> generates preview files using those commands:

- `trevents` : only recently uploaded files will be tested (transfer events)
- `events` : only recently uploaded files will be tested (file events: not working)
- `scan [path]` : generate previews for a file or recursively scan a folder. The default path is the access key&apos;s **storage root**. A file or folder can also be selected with `%id:<file_id>`.
- `test` : test using a local file

Use `--filter` with `scan`, `events`, or `trevents` to select files by name. It accepts a glob string, a regular expression using `@re:`, or a Proc using `@ruby:`. For example:

```shell
<%=cmd%> preview scan /videos --filter='*.mp4'
<%=cmd%> preview scan %id:<file_id>
<%=cmd%> preview scan /videos --filter='@ruby:->(f){f["name"].end_with?(".mp4")}'
```

Once candidates are selected, a preview is always generated if it does not already exist; if a preview already exists, generation depends on the value of option `overwrite`:

- `always` : preview is always generated, even if it already exists and is newer than original
- `never` : preview is generated only if it does not exist already
- `mtime` : preview is generated only if the original file is newer than the existing

Deletion of preview for deleted source files: not implemented yet (TODO).

If the `scan` or `events` detection method is used, then option `skip_folders` can be used to skip some folders.
It expects a list of paths relative to the storage root (docroot), starting with a slash, for example:

```shell
<%=cmd%> preview scan --skip-folders=@json:'["/not_here"]'
```

The option `folder_reset_cache` forces the node service to refresh folder contents using various methods.

See the following section for details.

### Preview File types

Two types of preview can be generated:

- `png`: thumbnail
- `mp4`: video preview (only for video)

Use option `skip_format` to skip generation of a format.

### Supported input Files types

The preview generator supports rendering of those file categories:

- `image`
- `pdf`
- `plaintext`
- `office`
- `video`

To avoid generation for some categories, specify a list using option `skip_types`, for example, `--skip-types=office` or `--skip-types=@list:,office,video`.

Each category has a specific rendering method to produce the PNG thumbnail.

The mp4 video preview file is only for category `video`.

By default, the Mime type used for conversion is the one returned by the Node API, based on file name extension.

It is also possible to detect the MIME type using option `detect_mime`.
To use it, set option `detect_mime` to `yes`: `--detect-mime=yes`.

In this case the `preview` command will first analyze the file content using gem `marcel`, and if no match, will try by extension.

### Generation: Read source files and write preview

Thumbnails and video previews are generated using standard open source tools and stored together in the storage root under the folder specified by option `previews_folder`.
Those tools require that original files are accessible in the local file system and also write generated files on the local file system.
Nevertheless, <%=tool%> may or may not have direct file system access to the access key storage root.

<%=tool%> provides 2 ways to read and write files with the option: `root_url`:

- Using direct access to the local file system.
- Using Aspera to transfer files between the storage and the <%=tool%> server.

| `root_url`    | Description |
|---------------|-------------------------------------------------------------------------------|
| `<empty>`     | (Default) If the access key storage type is `local`, then the storage root is used as the main folder.<%=br%>This assumes that <%=tool%> runs on the same system as HSTS, or has access through a common "mount".<%=br%>Else, remote access is assumed. |
| `aspera:`     | Source files are **downloaded** to a temporary directory, and preview files are **uploaded** to the storage.<%=br%>Two transfers are performed using Aspera: one download transfer for source files, one upload transfer for preview files. |
| `file:///<path>` | Files are accessed from the specified path locally. |

<%=include_commands_for_plugin(:preview)%>

