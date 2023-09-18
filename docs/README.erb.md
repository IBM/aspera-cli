# Command Line Interface for IBM Aspera products
<!-- markdownlint-disable MD033 MD003 MD053 -->
<!-- cSpell:ignore devkit zcvf zxvf noded secondfile filesize sedemo eudemo webmail csum eascp loglevel cronfile magick keepalive inotify eastus bluemix trev sshfp struct genkey passout ibmaspera unpermitted schtasks taskschd -->

[comment1]: # (Do not edit this README.md, edit docs/README.erb.md, for details, read docs/README.md)

##

Version : <%=gemspec.version.to_s%>

Laurent/2016-<%=Time.new.year%>

This gem provides the <%=tool%> Command Line Interface to IBM Aspera software.

<%=tool%> is a also great tool to learn Aspera APIs.

Ruby Gem: [<%=gemspec.metadata['rubygems_uri']%>](<%=gemspec.metadata['rubygems_uri']%>)

Ruby Doc: [<%=gemspec.metadata['documentation_uri']%>](<%=gemspec.metadata['documentation_uri']%>)

Minimum required Ruby <%=ruby_version%>.

[Aspera APIs on IBM developer](https://developer.ibm.com/?size=30&q=aspera&DWContentType[0]=APIs&sort=title_asc)
[Link 2](https://developer.ibm.com/apis/catalog/?search=aspera)

Release notes: see [CHANGELOG.md](CHANGELOG.md)

[![CII Best Practices](https://bestpractices.coreinfrastructure.org/projects/5861/badge)](https://bestpractices.coreinfrastructure.org/projects/5861)

## BUGS, FEATURES, CONTRIBUTION

Refer to [BUGS.md](BUGS.md) and [CONTRIBUTING.md](CONTRIBUTING.md).

One can also [create one's own plugin](#createownplugin).

## <a id="when_to_use"></a>When to use and when not to use

<%=tool%> is designed to be used as a command line tool to:

- Execute commands remotely on Aspera products
- Transfer to/from Aspera products

So it is designed for:

- Interactive operations on a text terminal (typically, VT100 compatible), e.g. for maintenance
- Scripting, e.g. batch operations in (shell) scripts (e.g. cron job)

<%=tool%> can be seen as a command line tool integrating:

- A configuration file (config.yaml)
- Advanced command line options
- cURL (for REST calls)
- Aspera transfer (`ascp`)

If the need is to perform operations programmatically in languages such as: C, Go, Python, nodejs, ... then it is better to directly use [Aspera APIs](https://ibm.biz/aspera_api)

- Product APIs (REST) : e.g. AoC, Faspex, node
- Transfer SDK : with gRPC interface and language stubs (C, C++, Python, .NET/C#, java, Ruby, etc...)

Using APIs (application REST API and transfer SDK) will prove to be easier to develop and maintain.

For scripting and ad'hoc command line operations, <%=tool%> is perfect.

## Notations, Shell, Examples

Command line operations examples are shown using a shell such: `bash` or `zsh`.

Command line parameters in examples beginning with `my_`, like `my_param_value` are user-provided value and not fixed value commands.

<%=tool%> is an API **Client** toward the remote Aspera application **Server** (Faspex, HSTS, etc...)

Some commands will start an Aspera-based transfer (e.g. `upload`).
The transfer is not directly implemented in <%=tool%>, rather <%=tool%> uses an external Aspera Client called **[Transfer Agents](#agents)**.

> **Note:** The transfer agent is a client for the remote Transfer Server (HSTS).
The transfer agent may be local or remote...
For example a remote Aspera Server may be used as a transfer agent (using node API).
i.e. using option `--transfer=node`

## Quick Start

This section guides you from installation, first use and advanced use.

First, follow the section: [Installation](#installation) (Ruby, Gem, FASP) to start using <%=tool%>.

Once the gem is installed, <%=tool%> shall be accessible:

```bash
<%=cmd%> --version
```

```bash
<%=gemspec.version.to_s%>
```

### First use

Once installation is completed, you can proceed to the first use with a demo server:

If you want to test with Aspera on Cloud, jump to section: [Wizard](#aocwizard)

To test with Aspera demo transfer server, setup the environment and then test:

```bash
<%=cmd%> config initdemo
```

```bash
<%=cmd%> server browse /
```

```output
+------------+-----------+-----------+-------+---------------------------+-----------------------+
| zmode      | zuid      | zgid      | size  | mtime                     | name                  |
+------------+-----------+-----------+-------+---------------------------+-----------------------+
| drwxr-xr-x | asperaweb | asperaweb | 90112 | 2023-04-05 15:31:21 +0200 | Upload                |
| dr-xr-xr-x | asperaweb | asperaweb | 4096  | 2022-10-27 16:08:16 +0200 | aspera-test-dir-large |
| dr-xr-xr-x | asperaweb | asperaweb | 4096  | 2022-10-27 16:08:17 +0200 | aspera-test-dir-small |
| dr-xr-xr-x | asperaweb | asperaweb | 4096  | 2022-10-27 16:08:17 +0200 | aspera-test-dir-tiny  |
+------------+-----------+-----------+-------+---------------------------+-----------------------+
```

If you want to use <%=tool%> with another server, and in order to make further calls more convenient, it is advised to define a <%=prst%> for the server's authentication options. The following example will:

- create a <%=prst%>
- define it as default for `server` plugin
- list files in a folder
- download a file

```bash
<%=cmd%> config preset update myserver --url=ssh://demo.asperasoft.com:33001 --username=asperaweb --password=my_password_here
```

```output
updated: myserver
```

```bash
<%=cmd%> config preset set default server myserver
```

```output
updated: default &rarr; server to myserver
```

```bash
<%=cmd%> server browse /aspera-test-dir-large
```

```output
+------------+-----------+-----------+--------------+---------------------------+-------+
| zmode      | zuid      | zgid      | size         | mtime                     | name  |
+------------+-----------+-----------+--------------+---------------------------+-------+
| -r-xr-x--- | asperaweb | asperaweb | 104857600    | 2022-10-27 16:06:38 +0200 | 100MB |
| -r-xr-x--- | asperaweb | asperaweb | 10737418240  | 2022-10-27 16:08:12 +0200 | 10GB  |
| -r-xr-x--- | asperaweb | asperaweb | 500000000000 | 2022-10-27 16:06:26 +0200 | 500GB |
| -r-xr-x--- | asperaweb | asperaweb | 524288000    | 2022-10-27 14:53:00 +0200 | 500MB |
| -r-xr-x--- | asperaweb | asperaweb | 1048576000   | 2022-10-27 16:06:37 +0200 | 1GB   |
| -r-xr-x--- | asperaweb | asperaweb | 5368709120   | 2022-10-27 14:53:47 +0200 | 5GB   |
| -r-xr-x--- | asperaweb | asperaweb | 209715200    | 2022-10-27 14:52:56 +0200 | 200MB |
+------------+-----------+-----------+--------------+---------------------------+-------+
```

```bash
<%=cmd%> server download /aspera-test-dir-large/200MB
```

```output
Time: 00:00:02 =========================================================== 100% 100 Mbps Time: 00:00:00
complete
```

### Going further

Get familiar with configuration, options, commands : [Command Line Interface](#cli).

Then, follow the section relative to the product you want to interact with ( Aspera on Cloud, Faspex, ...) : [Application Plugins](plugins)

## <a id="installation"></a>Installation

It is possible to install **either** directly on the host operating system (Linux, macOS, Windows) or as a container (`docker`).

The direct installation is recommended and consists in installing:

- [Ruby](#ruby)
- [<%=gemspec.name%>](#the_gem)
- [Aspera SDK (`ascp`)](#fasp_prot)

Ruby <%=ruby_version%>.

The following sections provide information on the various installation methods.

An internet connection is required for the installation. If you don't have internet for the installation, refer to section [Installation without internet access](#offline_install).

### Docker container

The image is: [<%=containerimage%>](https://hub.docker.com/r/<%=containerimage%>).
The container contains: Ruby, <%=tool%> and the Aspera Transfer SDK.
To use the container, ensure that you have `podman` (or `docker`) installed.

```bash
podman --version
```

#### Container quick start

**Wanna start quickly ?** With an interactive shell ? Execute this:

```bash
podman run --tty --interactive --entrypoint bash <%=containerimage%>:latest
```

Then, execute individual <%=tool%> commands such as:

```bash
<%=cmd%> conf init
<%=cmd%> conf preset overview
<%=cmd%> conf ascp info
<%=cmd%> server ls /
```

That is simple, but there are limitations:

- Everything happens in the container
- Any generated file in the container will be lost on container (shell) exit. Including configuration files and downloaded files.
- No possibility to upload files located on the host system

#### Details on the container

The container image is built from this [Dockerfile](Dockerfile): the entry point is <%=tool%> and the default command is `help`.

If you want to run the image with a shell, execute with option: `--entrypoint bash`, and give argument `-l` (bash login to override the `help` default argument)

The container can also be execute for individual commands like this: (add <%=tool%> commands and options at the end of the command line, e.g. `-v` to display the version)

```bash
podman run --rm --tty --interactive <%=containerimage%>:latest
```

For more convenience, you may define a shell alias:

```bash
alias <%=cmd%>='podman run --rm --tty --interactive <%=containerimage%>:latest'
```

Then, you can execute the container like a local command:

```bash
<%=cmd%> -v
```

```text
<%=gemspec.version.to_s%>
```

In order to keep persistency of configuration on the host,
you should mount your user's config folder to the container.
To enable write access, a possibility is to run as `root` in the container (and set the default configuration folder to `/home/cliuser/.aspera/<%=cmd%>`).
Add options:

```bash
--user root --env <%=evp%>HOME=/home/cliuser/.aspera/<%=cmd%> --volume $HOME/.aspera/<%=cmd%>:/home/cliuser/.aspera/<%=cmd%>
```

> **Note:** if you are using a `podman machine`, e.g. on macOS , make sure that the folder is also shared between the VM and the host, so that sharing is: container &rarr; VM &rarr; Host: `podman machine init ... --volume="/Users:/Users"`

As shown in the quick start, if you prefer to keep a running container with a shell and <%=tool%> available,
you can change the entry point, add option:

```bash
--entrypoint bash
```

You may also probably want that files downloaded in the container are in fact placed on the host.
In this case you need also to mount the shared transfer folder:

```bash
--volume $HOME/xferdir:/xferfiles
```

> **Note:** <%=cmd%> is run inside the container, so transfers are also executed inside the container and do not have access to host storage by default.

And if you want all the above, simply use all the options:

```bash
alias <%=cmd%>sh="podman run --rm --tty --interactive --user root --env <%=evp%>HOME=/home/cliuser/.aspera/<%=cmd%> --volume $HOME/.aspera/<%=cmd%>:/home/cliuser/.aspera/<%=cmd%> --volume $HOME/xferdir:/xferfiles --entrypoint bash <%=containerimage%>:latest"
```

```bash
export xferdir=$HOME/xferdir
mkdir -p $xferdir
chmod -R 777 $xferdir
mkdir -p $HOME/.aspera/<%=cmd%>
<%=cmd%>sh
```

#### Sample container script

A convenience sample script is also provided: download the script [`d<%=cmd%>`](../examples/d<%=cmd%>) from [the GIT repo](https://raw.githubusercontent.com/IBM/aspera-cli/main/examples/d<%=cmd%>) :

> **Note:** If you have installed <%=tool%>, the script `d<%=cmd%>` can also be found: `cp $(<%=cmd%> conf gem path)/../examples/d<%=cmd%> <%=cmd%>`

Some environment variables can be set for this script to adapt its behavior:

| env var      | description                        | default                  | example                  |
|--------------|------------------------------------|--------------------------|--------------------------|
| <%=evp%>HOME | configuration folder (persistency) | `$HOME/.aspera/<%=cmd%>` | `$HOME/.<%=cmd%>config`     |
| docker_args  | additional options to `podman`     | &lt;empty&gt;            | `--volume /Users:/Users` |
| image        | container image name               | <%=containerimage%>      |                          |
| version      | container image version            | latest                   | `4.8.0.pre`              |

The wrapping script maps the folder `$<%=evp%>HOME` on host to `/home/cliuser/.aspera/<%=cmd%>` in the container.
(value expected in the container).
This allows having persistent configuration on the host.

To add local storage as a volume, you can use the env var `docker_args`:

Example of use:

```bash
curl -o <%=cmd%> https://raw.githubusercontent.com/IBM/aspera-cli/main/examples/d<%=cmd%>
chmod a+x <%=cmd%>
export xferdir=$HOME/xferdir
mkdir -p $xferdir
chmod -R 777 $xferdir
export docker_args="--volume $xferdir:/xferfiles"

./<%=cmd%> conf init

echo 'Local file to transfer' > $xferdir/samplefile.txt
./<%=cmd%> server upload /xferfiles/samplefile.txt --to-folder=/Upload
```

> **Note:** The local file (`samplefile.txt`) is specified relative to storage view from container (`/xferfiles`) mapped to the host folder `$HOME/xferdir`
>
> **Note:** Do not use too many volumes, as the AUFS limits the number.

#### Offline installation of the container

- First create the image archive:

```bash
podman pull <%=containerimage%>
podman save <%=containerimage%>|gzip><%=cmd%>_image_latest.tar.gz
```

- Then, on air-gapped system:

```bash
podman load -i <%=cmd%>_image_latest.tar.gz
```

#### Container: `aspera.conf`

`ascp`'s configuration file `aspera.conf` is located in the container at: `/home/cliuser/.aspera/sdk/aspera.conf` (see Dockerfile).
As the container is immutable, it is not possible to modify this file.
If one wants to change the content, it is possible to tell `ascp` to use another file using `ascp` option `-f`, e.g. by locating it on the host folder `$HOME/.aspera/ascli` mapped to the container folder `/home/cliuser/.aspera/ascli`:

```bash
echo '<CONF/>' > $HOME/.aspera/ascli/aspera.conf
```

Then, tell `ascp` to use that other conf file:

```bash
--transfer-info=@json:'{"ascp_args":["-f","/home/cliuser/.aspera/ascli/aspera.conf"]}'
```

### <a id="ruby"></a>Ruby

Use this method to install on the native host.

A Ruby interpreter is required to run the tool or to use the gem and tool.

Required Ruby <%=ruby_version%>.

*Ruby can be installed using any method* : rpm, yum, dnf, rvm, brew, windows installer, ... .

In priority, refer to the official Ruby documentation:

- [Download Ruby](https://www.ruby-lang.org/en/downloads/)
- [Installation Guide](https://www.ruby-lang.org/en/documentation/installation/)

Else, refer to the following sections for a proposed method for specific operating systems.

The recommended installation method is `rvm` for Unix-like systems (Linux, AIX, macOS, Windows with cygwin, etc...).
If the generic install is not suitable (e.g. Windows, no cygwin), you can use one of OS-specific install method.
If you have a simpler better way to install Ruby : use it !

#### Generic: RVM: single user installation (not root)

Use this method which provides more flexibility.

Install `rvm`: follow [https://rvm.io/](https://rvm.io/) :

Execute the shell/curl command. As regular user, it install in the user's home: `~/.rvm` .

```bash
\curl -sSL https://get.rvm.io | bash -s stable
```

Follow on-screen instructions to install keys, and then re-execute the command.

If you keep the same terminal (not needed if re-login):

```bash
source ~/.rvm/scripts/rvm
```

It is advised to get one of the pre-compiled Ruby version, you can list with:

```bash
rvm list --remote
```

Install the chosen pre-compiled Ruby version:

```bash
rvm install 3.2.2
```

Ruby is now installed for the user, go to [Gem installation](#the_gem).

#### Generic: RVM: global installation (as root)

Follow the same method as single user install, but execute as "root".

As root, it installs by default in /usr/local/rvm for all users and creates `/etc/profile.d/rvm.sh`.
One can install in another location with :

```bash
curl -sSL https://get.rvm.io | bash -s -- --path /usr/local
```

As root, make sure this will not collide with other application using Ruby (e.g. Faspex).
If so, one can rename the login script: `mv /etc/profile.d/rvm.sh /etc/profile.d/rvm.sh.ok`.
To activate Ruby (and <%=cmd%>) later, source it:

```bash
source /etc/profile.d/rvm.sh.ok
```

```bash
rvm version
```

#### Windows: Installer

Install Latest stable Ruby:

- Navigate to [https://rubyinstaller.org/](https://rubyinstaller.org/) &rarr; **Downloads**.
- Download the latest Ruby installer **with devkit**. (Msys2 is needed to install some native extensions, such as `grpc`)
- Execute the installer which installs by default in: `C:\RubyVV-x64` (VV is the version number)
- At the end of the installation procedure, the Msys2 installer is automatically executed, select option 3 (msys and mingw)

#### macOS: pre-installed or `brew`

macOS 10.13+ (High Sierra) comes with a recent Ruby. So you can use it directly. You will need to install <%=gemspec.name%> using `sudo` :

```bash
sudo gem install <%=gemspec.name%><%=geminstadd%>
```

Alternatively, if you use [Homebrew](https://brew.sh/) already you can install Ruby with it:

```bash
brew install ruby
```

#### Linux: package

If your Linux distribution provides a standard Ruby package, you can use it provided that the version supported.

**Example:** RHEL 8+, Rocky Linux 8+, Centos 8 Stream: with extensions to compile native gems

- Check available ruby versions:

  ```bash
  dnf module list ruby
  ```

- If ruby was already installed with an older version, remove it:

  ```bash
  dnf module -y reset ruby
  ```

- Install packages needed to build native gems:
  
    ```bash
    dnf install -y make automake gcc gcc-c++ kernel-devel
    ```

- Enable the Ruby version you want:

  ```bash
  dnf module -y enable ruby:3.1
  dnf install -y ruby-devel
  ```

**Other examples:**

```bash
yum install -y ruby ruby-devel rubygems ruby-json
```

```bash
apt install -y ruby ruby-dev rubygems ruby-json
```

One can cleanup the whole yum-installed Ruby environment like this to uninstall:

```bash
gem uninstall $(ls $(gem env gemdir)/gems/|sed -e 's/-[^-]*$//'|sort -u)
```

#### Other Unixes (AIX)

Ruby is sometimes made available as installable package through third party providers.
For example for AIX, one can look at:

<https://www.ibm.com/support/pages/aix-toolbox-open-source-software-downloads-alpha#R>

If your Unix does not provide a pre-built Ruby, you can get it using one of those
[methods](https://www.ruby-lang.org/en/documentation/installation/).

For instance to build from source, and install in `/opt/ruby` :

```bash
wget https://cache.ruby-lang.org/pub/ruby/2.7/ruby-2.7.2.tar.gz

gzip -d ruby-2.7.2.tar.gz

tar xvf ruby-2.7.2.tar

cd ruby-2.7.2

./configure --prefix=/opt/ruby

make ruby.imp

make

make install
```

If you already have a Java JVM on your system (`java`), it is possible to use `jruby`:

<https://www.jruby.org/download>

> **Note:** Using jruby the startup time is longer than the native Ruby, but the transfer speed is not impacted (executed by `ascp` binary).

### <a id="the_gem"></a>`<%=gemspec.name%>` gem

Once you have Ruby and rights to install gems: Install the gem and its dependencies:

```bash
gem install <%=gemspec.name%><%=geminstadd%>
```

To upgrade to the latest version:

```bash
gem update <%=gemspec.name%>
```

<%=tool%> checks every week if a new version is available and notify the user in a WARN log.
To de-activate this feature, globally set the option `version_check_days` to `0`, or specify a different period in days.

To check if a new version is available (independently of `version_check_days`):

```bash
<%=cmd%> conf check_update
```

### <a id="fasp_prot"></a>FASP Protocol

Most file transfers will be done using the FASP protocol, using `ascp`.
Only two additional files are required to perform an Aspera Transfer, which are part of Aspera SDK:

- `ascp`
- aspera-license (in same folder, or ../etc)

This can be installed either be installing an Aspera transfer software, or using an embedded command:

```bash
<%=cmd%> conf ascp install
```

If a local SDK installation is preferred instead of fetching from internet: one can specify the location of the SDK file:

```bash
curl -Lso SDK.zip https://ibm.biz/aspera_sdk
```

```bash
<%=cmd%> conf ascp install --sdk-url=file:///SDK.zip
```

The format is: `file:///<path>`, where `<path>` can be either a relative path (not starting with `/`), or an absolute path.

If the embedded method is not used, the following packages are also suitable:

- IBM Aspera Connect Client (Free)
- IBM Aspera Desktop Client (Free)
- IBM Aspera High Speed Transfer Server (Licensed)
- IBM Aspera High Speed Transfer EndPoint (Licensed)

For instance, Aspera Connect Client can be installed
by visiting the page: [https://www.ibm.com/aspera/connect/](https://www.ibm.com/aspera/connect/).

<%=tool%> will detect most of Aspera transfer products in standard locations and use the first one found.
Refer to section [FASP](#client) for details on how to select a client or set path to the FASP protocol.

Several methods are provided to start a transfer.
Use of a local client ([`direct`](#agt_direct) transfer agent) is one of them, but other methods are available. Refer to section: [Transfer Agents](#agents)

### <a id="offline_install"></a>Installation in air gapped environment

> **Note:** no pre-packaged version is provided.

A method to build one is provided here:

The procedure:

- Follow the non-root installation procedure with RVM, including gem
- Archive (zip, tar) the main RVM folder (includes <%=cmd%>):

```bash
cd $HOME && tar zcvf rvm-<%=cmd%>.tgz .rvm
```

- Get the Aspera SDK.

```bash
<%=cmd%> conf --show-config --fields=sdk_url
```

- Download the SDK archive from that URL.

```bash
curl -Lso SDK.zip https://ibm.biz/aspera_sdk
```

- Transfer those 2 files to the target system

- On target system

```bash
cd $HOME

tar zxvf rvm-<%=cmd%>.tgz

source ~/.rvm/scripts/rvm

<%=cmd%> conf ascp install --sdk-url=file:///SDK.zip
```

- Add those lines to shell init (`.profile`)

```bash
source ~/.rvm/scripts/rvm
```

## <a id="cli"></a>Command Line Interface: <%=tool%>

The `<%=gemspec.name%>` Gem provides a command line interface (CLI) which interacts with Aspera Products (mostly using REST APIs):

- IBM Aspera High Speed Transfer Server (FASP and Node)
- IBM Aspera on Cloud (including ATS)
- IBM Aspera Faspex
- IBM Aspera Shares
- IBM Aspera Console
- IBM Aspera Orchestrator
- and more...

<%=tool%> provides the following features:

- Supports most Aspera server products (on-premise and SaaS)
- Any command line options (products URL, credentials or any option) can be provided on command line, in configuration file, in env var, in files
- Supports Commands, Option values and Parameters shortcuts
- FASP [Transfer Agents](#agents) can be: local `ascp`, or Connect Client, or any transfer node
- Transfer parameters can be altered by modification of <%=trspec%>, this includes requiring multi-session
- Allows transfers from products to products, essentially at node level (using the node transfer agent)
- Supports FaspStream creation (using Node API)
- Supports Watchfolder creation (using Node API)
- Additional command plugins can be written by the user
- Supports download of faspex and Aspera on Cloud "external" links
- Supports "legacy" ssh based FASP transfers and remote commands (ascmd)

Basic usage is displayed by executing:

```bash
<%=cmd%> -h
```

Refer to sections: [Usage](#usage).

Not all <%=tool%> features are fully documented here, the user may explore commands on the command line.

### `ascp` command line

If you want to use `ascp` directly as a command line, refer to IBM Aspera documentation of either [Desktop Client](https://www.ibm.com/docs/en/asdc), [Endpoint](https://www.ibm.com/docs/en/ahte) or [Transfer Server](https://www.ibm.com/docs/en/ahts) where [a section on `ascp` can be found](https://www.ibm.com/docs/en/ahts/4.4?topic=linux-ascp-transferring-from-command-line).

Using <%=tool%> with plugin `server` for command line gives advantages over `ascp`:

- automatic resume on error
- configuration file
- choice of transfer agents
- integrated support of multi-session

Moreover all `ascp` options are supported either through transfer spec parameters and with the possibility to provide `ascp` arguments directly when the `direct` agent is used (`ascp_args`).

### <a id="parsing"></a>Command line parsing, Special Characters

<%=tool%> is typically executed in a shell, either interactively or in a script.
<%=tool%> receives its arguments from this shell (through Operating System).

#### Shell parsing for Unix-like systems: Linux, macOS, AIX

On Unix-like environments, this is typically a POSIX shell (bash, zsh, ksh, sh).
In this environment the shell parses the command line, possibly replacing variables, etc...
see [bash shell operation](https://www.gnu.org/software/bash/manual/bash.html#Shell-Operation).
Then it builds a list of arguments and then <%=tool%> (Ruby) is executed.
Ruby receives a list parameters from shell and gives it to <%=tool%>.
So special character handling (quotes, spaces, env vars, ...) is first done in the shell.

#### Shell parsing for Windows

On Windows, `cmd.exe` is typically used.
Windows process creation does not receive the list of arguments but just the whole line.
It's up to the program to parse arguments. Ruby follows the Microsoft C/C++ parameter parsing rules.

- [Windows: How Command Line Parameters Are Parsed](https://daviddeley.com/autohotkey/parameters/parameters.htm#RUBY)
- [Understand Quoting and Escaping of Windows Command Line Arguments](http://www.windowsinspired.com/understanding-the-command-line-string-and-arguments-received-by-a-windows-program/)

#### Extended Values (JSON, Ruby, ...)

Some of the <%=tool%> parameters are expected to be [Extended Values](#extended), i.e. not a simple strings, but a complex structure (Hash, Array).
Typically, the `@json:` modifier is used, it expects a JSON string. JSON itself has some special syntax: for example `"` is used to denote strings.

#### Testing Extended Values

In case of doubt of argument values after parsing, one can test using command `config echo`. `config echo` takes exactly **one** argument which can use the [Extended Value](#extended) syntax. Unprocessed command line arguments are shown in the error message.

Example: The shell parses three arguments (as strings: `1`, `2` and `3`), so the additional two arguments are not processed by the `echo` command.

```bash
<%=cmd%> conf echo 1 2 3
```

```bash
"1"
ERROR: Argument: unprocessed values: ["2", "3"]
```

`config echo` displays the value of the **first** argument using Ruby syntax: it surrounds a string with `"` and add `\` before special characters.

> **Note:** It gets its value after shell command line parsing and <%=tool%> extended value parsing.

In the following examples (using a POSIX shell, such as `bash`), several sample commands are provided when equivalent.
For all example, most of special character handling is not specific to <%=tool%>: It depends on the underlying syntax: shell , JSON, etc...
Depending on the case, a different `format` is used to display the actual value.

For example, in the simple string `Hello World`, the space character is special for the shell, so it must be escaped so that a single value is represented.

Double quotes are processed by the shell to create a single string argument.
For POSIX shells, single quotes can also be used in this case, or protect the special character ` ` (space) with a backslash. <!-- markdownlint-disable-line -->

```bash
<%=cmd%> conf echo "Hello World" --format=text
<%=cmd%> conf echo 'Hello World' --format=text
<%=cmd%> conf echo Hello\ World --format=text
```

```output
Hello World
```

#### Using a shell variable, parsed by shell, in an extended value

To be evaluated by shell, the shell variable must not be in single quotes.
Even if the variable contains spaces it makes only one argument to <%=tool%> because word parsing is made before variable expansion by shell.

> **Note:** we use a shell variable here: the variable is not necessarily an environment variable (`export`).

```bash
MYVAR="Hello World"
<%=cmd%> conf echo @json:'{"title":"'$MYVAR'"}' --format=json
<%=cmd%> conf echo @json:{\"title\":\"$MYVAR\"} --format=json
```

```json
{"title":"Hello World"}
```

#### Double quote in strings in command line

Double quote is a shell special character.
Like any shell special character, it can be protected either by preceding with a backslash or by enclosing in a single quote.

```bash
<%=cmd%> conf echo \"
<%=cmd%> conf echo '"'
```

```output
"
```

Double quote in JSON is a little tricky because `"` is special both for the shell and JSON. Both shell and JSON syntax allow to protect `"`, but only the shell allows protection using single quote.

```bash
<%=cmd%> conf echo @json:'"\""' --format=text
<%=cmd%> conf echo @json:\"\\\"\" --format=text
<%=cmd%> conf echo @ruby:\'\"\' --format=text
```

```output
"
```

Here a single quote or a backslash protects the double quote to avoid shell processing, and then an additional `\` is added to protect the `"` for JSON. But as `\` is also shell special, then it is protected by another `\`.
  
#### Shell and JSON or Ruby special characters in extended value

Construction of values with special characters is done like this:

- First select a syntax to represent the extended value, e.g. JSON or Ruby

- Write the expression using this syntax, for example, using JSON:

```json
{"title":"Test \" ' & \\"}
```

or using Ruby:

```ruby
{"title"=>"Test \" ' & \\"}
{'title'=>%q{Test " ' & \\}}
```

Both `"` and `\` are special characters for JSON and Ruby and can be protected with `\` (unless Ruby's extended single quote notation `%q` is used).
  
- Then, since the value will be evaluated by shell, any shell special characters must be protected, either using preceding `\` for each character to protect, or by enclosing in single quote:

```bash
<%=cmd%> conf echo @json:{\"title\":\"Test\ \\\"\ \'\ \&\ \\\\\"} --format=json
<%=cmd%> conf echo @json:'{"title":"Test \" '\'' & \\"}' --format=json
<%=cmd%> conf echo @ruby:"{'title'=>%q{Test \" ' & \\\\}}" --format=json
```

```json
{"title":"Test \" ' & \\"}
```

#### Reading special characters interactively

If <%=tool%> is used interactively (a user typing on terminal), it is easy to require the user to type values:

```bash
<%=cmd%> conf echo @ruby:"{'title'=>gets.chomp}" --format=json
```

`gets` is Ruby's method of terminal input (terminated by `\n`), and `chomp` removes the trailing `\n`.

#### Command line arguments from a file

If you need to provide a list of command line argument from lines that are in a file, on Linux you can use the `xargs` command:

```bash
xargs -a lines.txt -d \\n <%=cmd%> conf echo
```

This is equivalent to execution of:

```bash
<%=cmd%> conf echo [line1] [line2] [line3] ...
```

If there are spaces in the lines, those are not taken as separator, as we provide option `-d \\n` to `xargs`.

#### Extended value using special characters read from environmental variables or files

Using a text editor or shell: create a file `title.txt` (and env var) that contains exactly the text required: `Test " ' & \` :

```bash
export MYTITLE='Test " '\'' & \'
echo -n $MYTITLE > title.txt
```

Using those values will not require any escaping of characters since values do not go through shell or JSON parsing.

If the value is to be assigned directly to an option of <%=cmd%>, then you can directly use the content of the file or env var using the `@file:` or `@env:` readers:

```bash
<%=cmd%> conf echo @file:title.txt --format=text
<%=cmd%> conf echo @env:MYTITLE --format=text
```

```output
Test " ' & \
```

If the value to be used is in a more complex structure, then the `@ruby:` modifier can be used: it allows any Ruby code in expression, including reading from file or env var. In those cases, there is no character to protect because values are not parsed by the shell, or JSON or even Ruby.

```bash
<%=cmd%> conf echo @ruby:"{'title'=>File.read('title.txt')}" --format=json
<%=cmd%> conf echo @ruby:"{'title'=>ENV['MYTITLE']}" --format=json
```

```json
{"title":"Test \" ' & \\"}
```

### Commands, Options, Positional Values

Command line arguments are the units of command line, as parsed by the shell, typically separated by spaces (and called "argv").

<%=tool%> considers three types of command line arguments:

- Commands
- Options
- Positional Values

```bash
<%=cmd%> command subcommand --option-name=VAL1 VAL2
```

- executes *command*: `command subcommand`
- with one *option*: `option_name`and its *value*: `VAL1`
- the command has one additional mandatory *argument*: `VAL2`

When the value of a command, option or argument is constrained by a fixed list of values.
It is possible to use the first letters of the value only, provided that it uniquely identifies a value.
For example `<%=cmd%> conf ov` is the same as `<%=cmd%> config overview`.

The value of options and arguments is evaluated with the [Extended Value Syntax](#extended).

#### Commands

Commands are typically entity types or verbs to act on those entities.

Example:

```bash
<%=cmd%> conf ascp info
```

- <%=tool%> is the executable executed by the shell
- `conf` is the first level command, and is also the name f the plugin to be used
- `ascp` is the second level command, and is also the name of the component (singleton)
- `info` is the third level command, and is also the action to be performed

Typically, commands are located at the beginning of the command line.
Order is significant.
The provided command must match one of the supported commands in the given context.
If a wrong , or no command is provided when expected, an error message is displayed and the list of supported commands is displayed.

#### Options

All options, e.g. `--log-level=debug`, are command line arguments that:

- start with `--`
- have a name, in lowercase, using `-` as word separator in name  (e.g. `--log-level=debug`)
- have a value, separated from name with a `=`
- can be used by prefix, provided that it is unique. E.g. `--log-l=debug` is the same as `--log-level=debug` (avoid)

Exceptions:

- some options accept a short form, e.g. `-Ptoto` is equivalent to `--preset=toto`, refer to the manual or `-h`.
- some options (flags) don't take a value, e.g. `-r`
- the special option `--` stops option processing and is ignored, following command line arguments are taken as arguments, including the ones starting with a `-`. Example:

  ```bash
  <%=cmd%> config echo -- --sample
  ```

  ```bash
  "--sample"
  ```

> **Note:** Here, `--sample` is taken as an argument, and not as an option, due to `--`.

Options may have an (hardcoded) default value.

Options can be placed anywhere on command line and evaluated in order.

Options are typically either:

- optional : typically to change the default behavior
- mandatory : typically, connection information are options that are mandatory (so they can be placed in a config file)

The value for *any* options can come from the following locations (in this order, last value evaluated overrides previous value):

- [Configuration file](#configfile).
- Environment variable
- Command line

Environment variable starting with prefix: <%=evp%> are taken as option values, e.g. `<%=evp%>OPTION_NAME` is for `--option-name`.

Options values can be displayed for a given command by providing the `--show-config` option: `<%=cmd%> node --show-config`

#### Positional Values

Positional Values are typically mandatory values for a command, such as entity creation data.

If a Positional Values begins with `-`, then either use the `@val:` syntax (see [Extended Values](#extended)), or use the `--` separator (see above).

The advantages of using a positional value instead of an option for the same are that the command line is shorter(no option name, just the position) and the value is clearly mandatory.

The disadvantage is that it is not possible to define a default value in a config file or environment variable like for options.
Nevertheless, [Extended Values](#extended) syntax is supported, so it is possible to retrieve a value from the config file or environment variable.

### Interactive Input

Some options and parameters are mandatory and other optional. By default, the tool will ask for missing mandatory options or parameters for interactive execution.

The behavior can be controlled with:

- --interactive=&lt;yes|no&gt; (default=yes if STDIN is a terminal, else no)
  - yes : missing mandatory parameters/options are asked to the user
  - no : missing mandatory parameters/options raise an error message
- --ask-options=&lt;yes|no&gt; (default=no)
  - optional parameters/options are asked to user

### Output

Command execution will result in output (terminal, stdout/stderr).
The information displayed depends on the action.

#### Types of output data

Depending on action, the output will contain:

- `single_object` : displayed as a 2 dimensional table: one line per attribute, first column is attribute name, and second is attribute value. Nested hashes are collapsed.
- `object_list` : displayed as a 2 dimensional table: one line per item, one column per attribute.
- `value_list` : a table with one column.
- `empty` : nothing
- `status` : a message
- `other_struct` : a complex structure that cannot be displayed as an array

#### Format of output

By default, result of type single_object and object_list are displayed using format `table`.
The table style can be customized with parameter: `table_style` (horizontal, vertical and intersection characters) and is `:.:` by default.

In a table format, when displaying "objects" (single, or list), by default, sub object are
flattened (option `flat_hash`). So, object {"user":{"id":1,"name":"toto"}} will have attributes: user.id and user.name.
Setting `flat_hash` to `false` will only display one field: "user" and value is the sub hash table.
When in flatten mode, it is possible to filter fields by "dotted" field name.

Object lists are displayed one per line, with attributes as columns. Single objects are transposed: one attribute per line.
If transposition of single object is not desired, use option: `transpose_single` set to `no`.

The style of output can be set using the `format` parameter, supporting:

- `text` : Value as String
- `table` : Text table
- `ruby` : Ruby code
- `json` : JSON code
- `jsonpp` : JSON pretty printed
- `yaml` : YAML
- `csv` : Comma Separated Values

#### <a id="option_select"></a>Option: `select`: Filter on columns values for `object_list`

Table output can be filtered using the `select` parameter. Example:

```bash
<%=cmd%> aoc admin res user list --fields=name,email,ats_admin --query=@json:'{"sort":"name"}' --select=@json:'{"ats_admin":true}'
```

```output
+-------------------------------+----------------------------------+-----------+
|             name              |              email               | ats_admin |
+-------------------------------+----------------------------------+-----------+
| John Curtis                   | john@example.com                 | true      |
| Laurent Martin                | laurent@example.com              | true      |
+-------------------------------+----------------------------------+-----------+
```

> **Note:** `select` filters selected elements from the result of API calls, while the `query` parameters gives filtering parameters to the API when listing elements.

#### entity identifier

When a command is executed on a single entity, the entity is identified by a unique identifier that follows the command: e.g. `<%=cmd%> aoc admin res user show 1234` where `1234` is the user identifier.

> **Note:** The legacy option `id` is deprecated: `--id=1234` as it does not provide the possibility to have sub-entities.

Only some commands provide the following capability: If the entity can also be uniquely identified by a name, then the name can be used instead of the identifier, using the **percent selector**: `<%=cmd%> aoc admin res user show %name:john` where `john` is the user name.

Syntax: `%<field>:<value>`

#### Verbosity of output

Output messages are categorized in 3 types:

- `info` output contain additional information, such as number of elements in a table
- `data` output contain the actual output of the command (object, or list of objects)
- `error`output contain error messages

The option `display` controls the level of output:

- `info` displays all messages: `info`, `data`, and `error`
- `data` display `data` and `error` messages
- `error` display only error messages.

By default, secrets are removed from output: option `show_secrets` defaults to `no`, unless `display` is `data`, to allows piping results.
To hide secrets from output, set option `show_secrets` to `no`.

#### Selection of output object properties

By default, a table output will display one line per entry, and columns for each entries. Depending on the command, columns may include by default all properties, or only some selected properties. It is possible to define specific columns to be displayed, by setting the `fields` option to one of the following value:

- DEF : default display of columns (that's the default, when not set)
- ALL : all columns available
- a,b,c : the list of attributes specified by the comma separated list
- Array extended value: for instance, @json:'["a","b","c"]' same as above
- +a,b,c : add selected properties to the default selection.
- -a,b,c : remove selected properties from the default selection.

### <a id="extended"></a>Extended Value Syntax

Some options and arguments are specified by a simple string.
But sometime it is convenient to read a value from a file, or decode it, or have a value more complex than a string (e.g. Hash table).

The extended value syntax is:

```bash
<0 or more decoders><nothing or some text value>
```

Decoders act like a function of value on right hand side.
Decoders are recognized by the prefix: `@` and suffix `:`

The following decoders are supported:

| decoder | parameter | returns | description |
|---------|-----------|---------|-------------|
| base64  | String    | String  | decode a base64 encoded string
| csvt    | String    | Array   | decode a titled CSV value
| env     | String    | String  | read from a named env var name, e.g.--password=@env:MYPASSVAR
| file    | String    | String  | read value from specified file (prefix `~/` is replaced with the users home folder), e.g. `--key=@file:~/.ssh/mykey` |
| incps   | Hash      | Hash    | include values of presets specified by key `incps` in input hash
| json    | String    | any     | decode JSON values (convenient to provide complex structures)
| lines   | String    | Array   | split a string in multiple lines and return an array
| list    | String    | Array   | split a string in multiple items taking first character as separator and return an array
| path    | String    | String  | performs path expansion on specified path (prefix `~/` is replaced with the users home folder), e.g. `--config-file=@path:~/sample_config.yml` |
| preset  | String    | Hash    | get whole <%=opprst%> value by name. Sub-values can also be used using `.` as separator. e.g. `foo.bar` is `conf[foo][bar]`
| ruby    | String    | any     | execute specified Ruby code
| secret  | None      | String  | Ask password interactively (hides input)
| stdin   | None      | String  | read from stdin (no value on right)
| uri     | String    | String  | read value from specified URL, e.g. `--fpac=@uri:http://serv/f.pac` |
| val     | String    | String  | prevent decoders on the right to be decoded. e.g. `--key=@val:@file:foo` sets the option `key` to value `@file:foo`. |
| zlib    | String    | String  | un-compress data

To display the result of an extended value, use the `config echo` command.

Example: read the content of the specified file, then, base64 decode, then unzip:

```bash
<%=cmd%> config echo @zlib:@base64:@file:myfile.dat
```

Example: Create a value as a hash, with one key and the value is read from a file:

```bash
<%=cmd%> config echo @ruby:'{"token_verification_key"=>File.read("mykey.txt")}'
```

Example: read a csv file and create a list of hash for bulk provisioning:

```bash
cat test.csv
```

```bash
name,email
lolo,laurent@example.com
toto,titi@tutu.tata
```

```bash
<%=cmd%> config echo @csvt:@file:test.csv
```

```output
+------+---------------------+
| name |        email        |
+------+---------------------+
| lolo | laurent@example.com |
| toto | titi@tutu.tata      |
+------+---------------------+
```

Example: create a hash and include values from preset named "config" of config file in this hash

```bash
<%=cmd%> config echo @incps:@json:'{"hello":true,"incps":["config"]}'
```

```bash
{"version"=>"0.9", "hello"=>true}
```

> **Note:** `@incps:@json:'{"incps":["config"]}'` or `@incps:@ruby:'{"incps"=>["config"]}'` are equivalent to: `@preset:config`

### <a id="native"></a>Structured Value

Some options and parameters expect a [Extended Value](#extended), i.e. a value more complex than a simple string. This is usually a Hash table or an Array, which could also contain sub structures.

For instance, a <%=trspec%> is expected to be a [Extended Value](#extended).

Structured values shall be described using the [Extended Value Syntax](#extended).
A convenient way to specify a [Extended Value](#extended) is to use the `@json:` decoder, and describe the value in JSON format. The `@ruby:` decoder can also be used. For an array of hash tables, the `@csvt:` decoder can be used.

It is also possible to provide a [Extended Value](#extended) in a file using `@json:@file:<path>`

### <a id="conffolder"></a>Configuration and Persistency Folder

<%=tool%> configuration and other runtime files (token cache, file lists, persistency files, SDK) are stored `[config folder]`: `[User's home folder]/.aspera/<%=cmd%>`.

Note: `[User's home folder]` is found using Ruby's `Dir.home` (`rb_w32_home_dir`).
It uses the `HOME` env var primarily, and on MS Windows it also looks at `%HOMEDRIVE%%HOMEPATH%` and `%USERPROFILE%`. <%=tool%> sets the env var `%HOME%` to the value of `%USERPROFILE%` if set and exists. So, on Windows `%USERPROFILE%` is used as it is more reliable than `%HOMEDRIVE%%HOMEPATH%`.

The [config folder] can be displayed using :

```bash
<%=cmd%> config folder
```

```bash
/Users/kenji/.aspera/<%=cmd%>
```

It can be overridden using the environment variable `<%=evp%>HOME`.

Example (Windows):

```output
set <%=evp%>HOME=C:\Users\Kenji\.aspera\<%=cmd%>

<%=cmd%> config folder

C:\Users\Kenji\.aspera\<%=cmd%>
```

When OAuth is used (AoC, Faspex4 api v4, Faspex5) <%=tool%> keeps a cache of generated bearer tokens in `[config folder]/persist_store` by default.
Option `cache_tokens` (**yes**/no) allows to control if Oauth tokens are cached on file system, or generated for each request.
The command `config flush_tokens` deletes all existing tokens.
Tokens are kept on disk for a maximum of 30 minutes (`TOKEN_CACHE_EXPIRY_SEC`) and garbage collected after that.
Tokens that can be refreshed are refreshed. Else tokens are re-generated if expired.

### <a id="configfile"></a>Configuration file

On the first execution of <%=tool%>, an empty configuration file is created in the configuration folder.
Nevertheless, there is no mandatory information required in this file, the use of it is optional as any option can be provided on the command line.

Although the file is a standard YAML file, <%=tool%> provides commands to read and modify it using the `config` command.

All options for <%=tool%> can be set on command line, or by env vars, or using <%=prsts%> in the configuration file.

A configuration file provides a way to define default values, especially for authentication parameters, thus avoiding to always having to specify those parameters on the command line.

The default configuration file is: `$HOME/.aspera/<%=cmd%>/config.yaml` (this can be overridden with option `--config-file=path` or equivalent env var).

The configuration file is simply a catalog of pre-defined lists of options, called: <%=prsts%>. Then, instead of specifying some common options on the command line (e.g. address, credentials), it is possible to invoke the ones of a <%=prst%> (e.g. `mypreset`) using the option: `-Pmypreset` or `--preset=mypreset`.

#### <a id="lprt"></a><%=prstt%>

A <%=prst%> is simply a collection of parameters and their associated values in a named section in the configuration file.

A named <%=prst%> can be modified directly using <%=tool%>, which will update the configuration file :

```bash
<%=cmd%> config preset set|delete|show|initialize|update <<%=opprst%>>
```

The command `update` allows the easy creation of <%=prst%> by simply providing the options in their command line format, e.g. :

```bash
<%=cmd%> config preset update demo_server --url=ssh://demo.asperasoft.com:33001 --username=asperaweb --password=my_password_here --ts=@json:'{"precalculate_job_size":true}'
```

- This creates a <%=prst%> `demo_server` with all provided options.

The command `set` allows setting individual options in a <%=prst%>.

```bash
<%=cmd%> config preset set demo_server password my_password_here
```

The command `initialize`, like `update` allows to set several parameters at once, but it deletes an existing configuration instead of updating it, and expects a [*Structured Value*](#native).

```bash
<%=cmd%> config preset initialize demo_server @json:'{"url":"ssh://demo.asperasoft.com:33001","username":"asperaweb","password":"my_pass_here","ts":{"precalculate_job_size":true}}'
```

A full terminal based overview of the configuration can be displayed using:

```bash
<%=cmd%> config preset over
```

A list of <%=prst%> can be displayed using:

```bash
<%=cmd%> config preset list
```

A good practice is to not manually edit the configuration file and use modification commands instead.
If necessary, the configuration file can opened in a text editor with:

```bash
<%=cmd%> config open
```

> **Note:** this starts the editor specified by env var `EDITOR` if defined.

Older format for commands are still supported:

```bash
<%=cmd%> config preset set|delete|show|initialize|update <name>
<%=cmd%> config preset over
<%=cmd%> config preset list
```

#### <a id="lprtconf"></a>Special <%=prstt%>: config

This preset name is reserved and contains a single key: `version`. This is the version of <%=tool%> which created the file.

#### <a id="lprtdef"></a>Special <%=prstt%>: default

This preset name is reserved and contains an array of key-value , where the key is the name of a plugin, and the value is the name of another preset.

When a plugin is invoked, the preset associated with the name of the plugin is loaded, unless the option --no-default (or -N) is used.

> **Note:** Special plugin name: `config` can be associated with a preset that is loaded initially, typically used for default values.

Operations on this preset are done using regular `config` operations:

```bash
<%=cmd%> config preset set default _plugin_name_ _default_preset_for_plugin_
```

```bash
<%=cmd%> config preset get default _plugin_name_
```

```json
"_default_preset_for_plugin_"
```

#### <a id="config"></a>Plugin: `config`: Configuration

Plugin `config` provides general commands for <%=tool%>:

- <%=prstt%>, config file operations
- wizard
- vault
- ascp

The default configuration for `config` is read for any plugin invocation, this allows setting global options, such as `--log-level` or `--interactive`.
When <%=tool%> starts, it looks for the `default` <%=prstt%> and checks the value for `config`.
If set, it loads the option values for any plugin used.

> **Note:** If no global default is set by the user, the tool will use `global_common_defaults` when setting global parameters (e.g. `conf ascp use`)

Show current default (global) <%=prstt%> (`config` plugin):

```console
$ ascli conf preset get default config
global_common_defaults
```

```bash
ascli conf preset set global_common_defaults version_check_days 0
```

If the default global <%=prstt%> is not set:

```bash
ascli conf preset set default config global_common_defaults
```

#### Config sample commands

```bash
<%=include_commands_for_plugin('config')%>
```

#### Format of file

The configuration file is a hash in a YAML file. Example:

```yaml
config:
  version: 0.3.7
default:
  config: cli_default
  server: demo_server
cli_default:
  interactive: no
demo_server:
  url: ssh://demo.asperasoft.com:33001
  username: asperaweb
  password: my_password_here
```

We can see here:

- The configuration was created with <%=tool%> version 0.3.7
- the default <%=prst%> to load for `server` plugin is : `demo_server`
- the <%=prst%> `demo_server` defines some parameters: the URL and credentials
- the default <%=prst%> to load in any case is : `cli_default`

Two <%=prsts%> are reserved:

- `config` contains a single value: `version` showing the version used to create the configuration file.
  It is used to check compatibility.
- `default` is reserved to define the default <%=prst%> name used for known plugins.

The user may create as many <%=prsts%> as needed. For instance, a particular <%=prst%> can be created for a particular application instance and contain URL and credentials.

Values in the configuration also follow the [Extended Value Syntax](#extended).

Note: if the user wants to use the [Extended Value Syntax](#extended) inside the configuration file, using the `config preset update` command, the user shall use the `@val:` prefix. Example:

```bash
<%=cmd%> config preset set my_aoc_org private_key @val:@file:"$HOME/.aspera/<%=cmd%>/my_private_key"
```

This creates the <%=prst%>:

```yaml
...
my_aoc_org:
  private_key: @file:"/Users/laurent/.aspera/<%=cmd%>/my_private_key"
...
```

So, the key file will be read only at execution time, but not be embedded in the configuration file.

#### Options evaluation order

Some options are global, some options are available only for some plugins. (the plugin is the first level command).

Options are loaded using this algorithm:

- If option `--no-default` (or `-N`) is specified, then no default value is loaded for the plugin
- else it looks for the name of the plugin as key in section `default`, the value is the name of the default <%=prst%> for it, and loads it.
- If option `--preset=<name or extended value hash>` is specified (or `-Pxxxx`), this reads the <%=prst%> specified from the configuration file, or of the value is a Hash, it uses it as options values.
- Environment variables are evaluated
- Command line options are evaluated

Parameters are evaluated in the order of command line.

To avoid loading the default <%=prst%> for a plugin, use: `-N`

On command line, words in parameter names are separated by a dash, in configuration file, separator
is an underscore. E.g. --xxx-yyy  on command line gives xxx_yyy in configuration file.

The main plugin name is `config`, so it is possible to define a default <%=prst%> for the main plugin with:

```bash
<%=cmd%> config preset set cli_default interactive no
```

```bash
<%=cmd%> config preset set default config cli_default
```

A <%=prst%> value can be removed with `unset`:

```bash
<%=cmd%> config preset unset cli_default interactive
```

Example: Define options using command line:

```bash
<%=cmd%> -N --url=_url_here_ --password=my_password_here --username=_name_here_ node --show-config
```

Example: Define options using a hash:

```bash
<%=cmd%> -N --preset=@json:'{"url":"_url_here_","password":"my_password_here","username":"_name_here_"}' node --show-config
```

#### Shares Examples

For Faspex, Shares, Node (including ATS, Aspera Transfer Service), Console,
only username/password and url are required (either on command line, or from config file).
Those can usually be provided on the command line:

```bash
<%=cmd%> shares repo browse / --url=https://10.25.0.6 --username=john --password=my_password_here
```

This can also be provisioned in a config file:

- Build <%=prst%>

```bash
<%=cmd%> config preset set shares06 url https://10.25.0.6
<%=cmd%> config preset set shares06 username john
<%=cmd%> config preset set shares06 password my_password_here
```

This can also be done with one single command:

```bash
<%=cmd%> config preset init shares06 @json:'{"url":"https://10.25.0.6","username":"john","password":"my_password_here"}'
```

or

```bash
<%=cmd%> config preset update shares06 --url=https://10.25.0.6 --username=john --password=my_password_here
```

- Define this <%=prst%> as the default <%=prst%> for the specified plugin (`shares`)

```bash
<%=cmd%> config preset set default shares shares06
```

- Display the content of configuration file in table format

```bash
<%=cmd%> config preset overview
```

- Execute a command on the shares application using default parameters

```bash
<%=cmd%> shares repo browse /
```

### <a id="vault"></a>Secret Vault

Password and secrets are command options.
They can be provided on command line, env vars, files etc.
A more secure option is to retrieve values from a secret vault.

The vault is used with options `vault` and `vault_password`.

`vault` defines the vault to be used and shall be a Hash, example:

```json
{"type":"system","name":"<%=cmd%>"}
```

`vault_password` specifies the password for the vault.
Although it can be specified on command line, for security reason you can hide the value.
For example it can be securely specified on command line like this:

```bash
export <%=evp%>VAULT_PASSWORD
read -s <%=evp%>VAULT_PASSWORD
```

#### Vault: System key chain

> **Note:** **macOS only**

It is possible to manage secrets in macOS key chain (only read supported currently).

```bash
--vault=@json:'{"type":"system","name":"<%=cmd%>"}'
```

#### Vault: Encrypted file

It is possible to store and use secrets encrypted in a file.

```bash
--vault=@json:'{"type":"file","name":"vault.bin"}'
```

`name` is the file path, absolute or relative to the config folder `<%=evp%>HOME`.

#### Vault: Operations

For this use the `config vault` command.

Then secrets can be manipulated using commands:

- `create`
- `show`
- `list`
- `delete`

```bash
<%=cmd%> conf vault create mylabel @json:'{"password":"my_password_here","description":"for this account"}'
```

#### <a id="config_finder"></a>Configuration Finder

When a secret is needed by a sub command, the command can search for existing configurations in the config file.

The lookup is done by comparing the service URL and username (or access key).

#### Securing passwords and secrets

A passwords can be saved in clear in a <%=prst%> together with other account information (URL, username, etc...).
Example:

```bash
<%=tool%> conf preset update myconf --url=... --username=... --password=...
```

For a more secure storage one can do:

```bash
<%=tool%> conf preset update myconf --url=... --username=... --password=@val:@vault:myconf.password
<%=tool%> conf vault create myconf @json:'{"password":"my_password_here"}'
```

> **Note:** use `@val:` in front of `@vault:` so that the extended value is not evaluated.

### <a id="private_key"></a>Private Key

Some applications allow the user to be authenticated using a private key (Server, AoC, Faspex5, ...).
It consists in using a pair of keys: the private key and its associated public key.
The same key can be used for multiple applications.
Technically, a private key contains the public key, which can be extracted from it.
The file containing the private key can optionally be protected by a passphrase.
If the key is protected by a passphrase, then it will be prompted when used.
(some plugins support option `passphrase`)

The following commands use the shell variable `PRIVKEYFILE`.
Set it to the desired safe location of the private key.
Typically, located in folder `$HOME/.ssh` or `$HOME/.aspera/<%=cmd%>`:

```bash
PRIVKEYFILE=~/.aspera/<%=cmd%>/my_private_key
```

Several methods can be used to generate a key pair.

The format expected for private keys is [PEM](https://en.wikipedia.org/wiki/Privacy-Enhanced_Mail).

#### <%=tool%> for key generation

The generated key is of type RSA, by default: 4096 bit.
For convenience, the public key is also extracted with extension `.pub`.
The key is not passphrase protected.

```bash
<%=cmd%> config genkey ${PRIVKEYFILE} 4096
```

#### `ssh-keygen`

Both private and public keys are generated, option `-N` is for passphrase.

```bash
ssh-keygen -t rsa -b 4096 -m PEM -N '' -f ${PRIVKEYFILE}
```

#### `openssl`

To generate a private key pair with a passphrase the following can be used on any system:

```bash
openssl genrsa -passout pass:_passphrase_here_ -out ${PRIVKEYFILE} 4096
openssl rsa -pubout -in ${PRIVKEYFILE} -out ${PRIVKEYFILE}.pub
```

`openssl` is sometimes compiled to support option `-nodes` (no DES, i.e. no passphrase, e.g. on macOS).
In that case, add option `-nodes` instead of `-passout pass:_passphrase_here_` to generate a key without passphrase.

If option `-nodes` is not available, the passphrase can be removed using this method:

```bash
openssl rsa -passin pass:_passphrase_here_ -in ${PRIVKEYFILE} -out ${PRIVKEYFILE}.no_des
mv ${PRIVKEYFILE}.no_des ${PRIVKEYFILE}
```

To change (or add) the passphrase for a key do:

```bash
openssl rsa -des3 -in ${PRIVKEYFILE} -out ${PRIVKEYFILE}.with_des
mv ${PRIVKEYFILE}.with_des ${PRIVKEYFILE}
```

### <a id="certificates"></a>SSL CA certificate bundle

<%=tool%> uses the Ruby `openssl` gem, which uses the `openssl` library.
Certificates are checked against the [Ruby default certificate store](https://ruby-doc.org/stdlib-3.0.3/libdoc/openssl/rdoc/OpenSSL/X509/Store.html) `OpenSSL::X509::DEFAULT_CERT_FILE` and `OpenSSL::X509::DEFAULT_CERT_DIR`, which are typically the ones of `openssl` on Unix-like systems (Linux, macOS, etc..).

To display the current root certificate store locations:

```bash
<%=cmd%> conf echo @ruby:'[OpenSSL::X509::DEFAULT_CERT_FILE,OpenSSL::X509::DEFAULT_CERT_DIR]'
```

Ruby's default values can be overridden by env vars: `SSL_CERT_FILE` and `SSL_CERT_DIR`.

`ascp` also needs to validate certificates when using **WSS**.
By default, `ascp` uses primarily certificates from hard-coded path (e.g. on macOS: `/Library/Aspera/ssl`) for WSS.
<%=tool%> overrides and sets the default Ruby certificate path as well for `ascp` using `-i` switch.

To update <%=tool%> trusted root certificates, just update your system's root certificates or use env vars specified here above.

### Plugins

<%=tool%> uses a plugin mechanism.
The first level command (just after <%=tool%> on the command line) is the name of the concerned plugin which will execute the command.
Each plugin usually represents commands sent to a specific application.
For instance, the plugin `faspex` allows operations on the application "Aspera Faspex".

Available plugins can be found using command:

```bash
<%=cmd%> conf plugin list
```

```output
+--------------+--------------------------------------------------------+
| plugin       | path                                                   |
+--------------+--------------------------------------------------------+
| shares       | ..../aspera-cli/lib/aspera/cli/plugins/shares.rb       |
| node         | ..../aspera-cli/lib/aspera/cli/plugins/node.rb         |
...
+--------------+--------------------------------------------------------+
```

#### <a id="createownplugin"></a>Create your own plugin

By default plugins are looked-up in folders specified by (multi-value) option `plugin_folder`:

```bash
<%=cmd%> --show-config --select=@json:'{"key":"plugin_folder"}'
```

You can create the skeleton of a new plugin like this:

```bash
<%=cmd%> conf plugin create foo .
```

```output
Created ./foo.rb
```

```bash
<%=cmd%> --plugin-folder=. foo
```

#### <a id="plugins"></a>Plugins: Application URL and Authentication

<%=tool%> comes with several Aspera application plugins.

REST APIs of Aspera legacy applications (Aspera Node, Faspex, Shares, Console, Orchestrator, Server) use simple username/password authentication: HTTP Basic Authentication.

Those are using options:

- url
- username
- password

Those can be provided using command line, parameter set, env var, see section above.

Aspera on Cloud relies on Oauth, refer to the [Aspera on Cloud](#aoc) section.

### Logging, Debugging

The gem is equipped with traces, mainly for debugging and learning APIs.
By default logging level is `warn` and the output channel is `stderr`.
To increase debug level, use parameter `log_level` (e.g. using command line `--log-level=xx`, env var `<%=evp%>LOG_LEVEL`, or a parameter in the configuration file).

It is also possible to activate traces before log facility initialization using env var `<%=evp%>LOG_LEVEL`.

By default passwords and secrets are removed from logs.
Use option `log_secrets` set to `yes` to reveal secrets in logs.

Available loggers: `stdout`, `stderr`, `syslog`.

Available levels: `debug`, `info`, `warn`, `error`.

> **Note:** When using the `direct` agent (`ascp`), additional transfer logs can be activated using `ascp` options and `ascp_args`, see [`direct`](#agt_direct).

Examples:

- display debugging log on `stdout`:

```bash
<%=cmd%> conf pre over --log-level=debug --logger=stdout
```

- log errors to `syslog`:

```bash
<%=cmd%> conf pre over --log-level=error --logger=syslog
```

When <%=tool%> is used interactively in a shell, the shell itself will usually log executed commands in the history file.

### Learning Aspera Product APIs (REST)

<%=tool%> uses mainly Aspera applications REST APIs.
To display HTTP calls, use argument `-r` or `--rest-debug`, this is useful to display exact content of HTTP requests and responses.

In order to get traces of execution, use argument : `--log-level=debug`

### <a id="http_options"></a>HTTP socket parameters

If the server does not provide a valid certificate, use option: `--insecure=yes`.

HTTP socket parameters can be adjusted using option `http_options`:

| parameter            | default |
|----------------------|---------|
| `read_timeout`       | 60      |
| `write_timeout`      | 60      |
| `open_timeout`       | 60      |
| `keep_alive_timeout` | 2       |

Values are in set *seconds* and can be of type either integer or float.
Default values are the ones of Ruby:
refer to the Ruby library: [`Net::HTTP`](https://ruby-doc.org/stdlib/libdoc/net/http/rdoc/Net/HTTP.html).

Like any other option, those can be set either on command line, or in config file, either in a global preset or server-specific one.

Example:

```bash
<%=cmd%> aoc admin res package list --http-options=@json:'{"read_timeout":10.0}'
```

### <a id="graphical"></a>Graphical Interactions: Browser and Text Editor

Some actions may require the use of a graphical tool:

- a browser for Aspera on Cloud authentication (web auth method)
- a text editor for configuration file edition

By default <%=tool%> assumes that a graphical environment is available on windows, and on other systems, rely on the presence of the `DISPLAY` environment variable.
It is also possible to force the graphical mode with option --ui :

- `--ui=graphical` forces a graphical environment, a browser will be opened for URLs or a text editor for file edition.
- `--ui=text` forces a text environment, the URL or file path to open is displayed on terminal.

### Proxy

There are several types of network connections, each of them use a different mechanism to define a (forward) **proxy**:

- Ruby HTTP: REST and HTTPGW client
- Legacy Aspera HTTP/S Fallback
- Aspera FASP

Refer to the following sections.

### Proxy for REST and HTTPGW

There are two possibilities to define an HTTP proxy to be used when Ruby HTTP is used.

The `http_proxy` environment variable (**lower case**, preferred) can be set to the URL of the proxy, e.g. `http://myproxy.org.net:3128`.
Refer to [Ruby find proxy](https://rubyapi.org/3.0/o/uri/generic#method-i-find_proxy).

> **Note:** Ruby expects a URL and `myproxy.org.net:3128` alone is **not** accepted.

```bash
export http_proxy=http://proxy.example.com:3128
```

The `fpac` option (function for proxy auto config) can be set to a [Proxy Auto Configuration (PAC)](https://en.wikipedia.org/wiki/Proxy_auto-config) javascript value.
To read the script from a URL (`http:`, `https:` and `file:`), use prefix: `@uri:`.
A minimal script can be specified to define the use of a local proxy:

```bash
<%=cmd%> --fpac='function FindProxyForURL(url, host){return "PROXY localhost:3128"}' ...
```

The result of a PAC file can be tested with command: `config proxy_check`.
Example, using command line option:

```bash
<%=cmd%> conf proxy_check --fpac='function FindProxyForURL(url, host) {return "PROXY proxy.example.com:3128;DIRECT";}' http://example.com
```

```text
PROXY proxy.example.com:1234;DIRECT
```

```bash
<%=cmd%> config proxy_check --fpac=@file:./proxy.pac http://www.example.com
```

```text
PROXY proxy.example.com:8080
```

```bash
<%=cmd%> config proxy_check --fpac=@uri:http://server/proxy.pac http://www.example.com
```

```text
PROXY proxy.example.com:8080
```

If the proxy requires credentials, then use option `proxy_credentials` with username and password provided as an `Array`:

```bash
<%=cmd%> --proxy-credentials=@json:'["__username_here__","__password_here__"]' ...
```

```bash
<%=cmd%> --proxy-credentials=@list::__username_here__:__password_here__ ...
```

### Proxy for Legacy Aspera HTTP/S Fallback

Only supported with the `direct` agent: To specify a proxy for legacy HTTP fallback, use `ascp` native option `-x` and `ascp_args`: `--transfer-info=@json:'{"ascp_args":["-x","url_here"]}'`. Alternatively, set the <%=trspec%> parameter: `EX_http_proxy_url`.

### FASP proxy (forward) for transfers

To specify a FASP proxy (forward), set the <%=trspec%> parameter: `proxy` (only supported with the `direct` agent).

### <a id="client"></a>FASP configuration

The `config` plugin also allows specification for the use of a local FASP **client**.
It provides the following commands for `ascp` subcommand:

- `show` : shows the path of `ascp` used
- `use` : list,download connect client versions available on internet
- `products` : list Aspera transfer products available locally
- `connect` : list,download connect client versions available on internet

#### Show path of currently used `ascp`

```bash
<%=cmd%> config ascp show
```

```output
/Users/laurent/.aspera/<%=cmd%>/sdk/ascp
```

```bash
<%=cmd%> config ascp info
```

```output
+--------------------+-----------------------------------------------------------+
| key                | value                                                     |
+--------------------+-----------------------------------------------------------+
| ascp               | /Users/laurent/.aspera/<%=cmd%>/sdk/ascp                     |
...
```

#### Selection of `ascp` location for [`direct`](#agt_direct) agent

By default, <%=tool%> uses any found local product with `ascp`, including SDK.

To temporarily use an alternate `ascp` path use option `ascp_path` (`--ascp-path=`)

For a permanent change, the command `config ascp use` sets the same parameter for the global default.

Using a POSIX shell:

```bash
<%=cmd%> config ascp use @path:'~/Applications/Aspera CLI/bin/ascp'
```

```output
ascp version: 4.0.0.182279
Updated: global_common_defaults: ascp_path <- /Users/laurent/Applications/Aspera CLI/bin/ascp
Saved to default global preset global_common_defaults
```

Windows:

```text
<%=cmd%> config ascp use C:\Users\admin\.aspera\<%=cmd%>\sdk\ascp.exe
```

```output
ascp version: 4.0.0.182279
Updated: global_common_defaults: ascp_path <- C:\Users\admin\.aspera\<%=cmd%>\sdk\ascp.exe
Saved to default global preset global_common_defaults
```

If the path has spaces, read section: [Shell and Command line parsing](#parsing).

#### List locally installed Aspera Transfer products

Locally installed Aspera products can be listed with:

```bash
<%=cmd%> config ascp products list
```

```output
+---------------------------------------+----------------------------------------+
| name                                  | app_root                               |
+---------------------------------------+----------------------------------------+
| IBM Aspera SDK                        | /Users/laurent/.aspera/<%=cmd%>/sdk       |
| Aspera Connect                        | /Applications/Aspera Connect.app       |
| IBM Aspera CLI                        | /Users/laurent/Applications/Aspera CLI |
| IBM Aspera High-Speed Transfer Server | /Library/Aspera                        |
+---------------------------------------+----------------------------------------+
```

#### Selection of local client for `ascp` for [`direct`](#agt_direct) agent

If no `ascp` is selected, this is equivalent to using option: `--use-product=FIRST`.

Using the option use_product finds the `ascp` binary of the selected product.

To permanently use the `ascp` of a product:

```bash
<%=cmd%> config ascp products use 'Aspera Connect'
saved to default global preset /Users/laurent/Applications/Aspera Connect.app/Contents/Resources/ascp
```

#### Installation of Connect Client on command line

```bash
<%=cmd%> config ascp connect list
```

```output
+-----------------------------------------------+--------------------------------------+-----------+
| id                                            | title                                | version   |
+-----------------------------------------------+--------------------------------------+-----------+
| urn:uuid:589F9EE5-0489-4F73-9982-A612FAC70C4E | Aspera Connect for Windows           | 3.11.2.63 |
| urn:uuid:A3820D20-083E-11E2-892E-0800200C9A66 | Aspera Connect for Windows 64-bit    | 3.11.2.63 |
| urn:uuid:589F9EE5-0489-4F73-9982-A612FAC70C4E | Aspera Connect for Windows XP        | 3.11.2.63 |
| urn:uuid:55425020-083E-11E2-892E-0800200C9A66 | Aspera Connect for Windows XP 64-bit | 3.11.2.63 |
| urn:uuid:D8629AD2-6898-4811-A46F-2AF386531BFF | Aspera Connect for Mac Intel         | 3.11.2.63 |
| urn:uuid:97F94DF0-22B1-11E2-81C1-0800200C9A66 | Aspera Connect for Linux 64          | 3.11.2.63 |
+-----------------------------------------------+--------------------------------------+-----------+
```

```bash
<%=cmd%> config ascp connect version 'Aspera Connect for Mac Intel' list
```

```output
+-------------------------------------------+--------------------------+-----------------------------------------------------------------------------------------+----------+---------------------+
| title                                     | type                     | href                                                                                    | hreflang | rel                 |
+-------------------------------------------+--------------------------+-----------------------------------------------------------------------------------------+----------+---------------------+
| Mac Intel Installer                       | application/octet-stream | bin/IBMAsperaConnectInstaller-3.11.2.63.dmg                                             | en       | enclosure           |
| Mac Intel Installer                       | application/octet-stream | bin/IBMAsperaConnectInstallerOneClick-3.11.2.63.dmg                                     | en       | enclosure-one-click |
| Aspera Connect for Mac HTML Documentation | text/html                | https://www.ibm.com/docs/en/aspera-connect/3.11?topic=aspera-connect-user-guide-macos   | en       | documentation       |
| Aspera Connect for Mac Release Notes      | text/html                | https://www.ibm.com/docs/en/aspera-connect/3.11?topic=notes-release-aspera-connect-3112 | en       | release-notes       |
+-------------------------------------------+--------------------------+-----------------------------------------------------------------------------------------+----------+---------------------+
```

```bash
<%=cmd%> config ascp connect version 'Aspera Connect for Mac Intel' download enclosure --to-folder=.
```

```output
Time: 00:00:02 =========================================================== 100% 27766 KB/sec Time: 00:00:02
Downloaded: IBMAsperaConnectInstaller-3.11.2.63.dmg
```

### <a id="agents"></a>Transfer Clients: Agents

Some of the actions on Aspera Applications lead to file transfers (upload and download) using the FASP protocol (`ascp`).

When a transfer needs to be started, a <%=trspec%> has been internally prepared.
This <%=trspec%> will be executed by a transfer client, here called **Transfer Agent**.

There are currently 3 agents, set with option `transfer`:

- [`direct`](#agt_direct) : a local execution of `ascp`
- [`connect`](#agt_connect) : use of a local Connect Client
- [`node`](#agt_node) : use of an Aspera Transfer Node (potentially *remote*).
- [`httpgw`](#agt_httpgw) : use of an Aspera HTTP Gateway
- [`trsdk`](#agt_trsdk) : use of Aspera Transfer SDK

> **Note:** All transfer operations are seen from the point of view of the agent.
For example, a node agent executing an "upload", or "package send" operation
will effectively push files to the related server from the agent node.

<%=tool%> standardizes on the use of a <%=trspec%> instead of *native* `ascp` options to provide parameters for a transfer session, as a common method for those three Transfer Agents.

Specific options for agents are provided with option `transfer_info`, cumulatively.

#### <a id="agt_direct"></a>Direct

The `direct` agent directly executes a local `ascp`.
This is the default agent for <%=tool%>.
This is equivalent to option `--transfer=direct`.
<%=tool%> will detect locally installed Aspera products, including SDK, and use `ascp` from that component.
Refer to section [FASP](#client).

The `transfer_info` option accepts the following optional parameters to control multi-session, Web Socket Session and Resume policy:

| Name                 | Type  | Description |
|----------------------|-------|-------------|
| wss                  | Bool  | Web Socket Session<br/>Enable use of web socket session in case it is available<br/>Default: true |
| ascp_args            | Array | Array of strings with native ascp arguments<br/>Use this instead of deprecated `EX_ascp_args`.<br/>Default: [] |
| spawn_timeout_sec    | Float | Multi session<br/>Verification time that `ascp` is running<br/>Default: 3 |
| spawn_delay_sec      | Float | Multi session<br/>Delay between startup of sessions<br/>Default: 2 |
| multi_incr_udp       | Bool  | Multi Session<br/>Increment UDP port on multi-session<br/>If true, each session will have a different UDP port starting at `fasp_port` (or default 33001)<br/>Else, each session will use `fasp_port` (or `ascp` default)<br/>Default: true |
| resume               | Hash  | Resume<br/>parameters<br/>See below |
| resume.iter_max      | int   | Resume<br/>Max number of retry on error<br/>Default: 7 |
| resume.sleep_initial | int   | Resume<br/>First Sleep before retry<br/>Default: 2 |
| resume.sleep_factor  | int   | Resume<br/>Multiplier of sleep period between attempts<br/>Default: 2 |
| resume.sleep_max     | int   | Resume<br/>Default: 60 |

In case of transfer interruption, the agent will **resume** a transfer up to `iter_max` time.
Sleep between iterations is:

```bash
max( sleep_max , sleep_initial * sleep_factor ^ (iter_index-1) )
```

Some transfer errors are considered "retryable" (e.g. timeout) and some other not (e.g. wrong password).
The list of known protocol errors and retry level can be listed:

```bash
<%=cmd%> config ascp errors
```

Examples:

```bash
<%=cmd%> ... --transfer-info=@json:'{"wss":true,"resume":{"iter_max":20}}'
<%=cmd%> ... --transfer-info=@json:'{"spawn_delay_sec":2.5,"multi_incr_udp":false}'
```

> **Note:** The `direct` agent supports additional `transfer_spec` parameters starting with `EX_` (extended).
But it is preferred to use the option `transfer_info` with parameter `ascp_args`.

This can be useful to activate logging using option `-L` of `ascp`.
For example the option `--transfer-info=@json:'{"ascp_args":["-DDL-"]}'` will activate debug level 2 for `ascp` (`DD`), and display those logs on the terminal (`-`).
This is useful if the transfer fails.
To store `ascp` logs in file `aspera-scp-transfer.log` in a folder, use `--transfer-info=@json:'{"ascp_args":["-L","/path/to/folder"]}'`.

> **Note:** When transfer agent [`direct`](#agt_direct) is used, the list of files to transfer is provided to `ascp` using either `--file-list` or `--file-pair-list` and a file list (or pair) file generated in a temporary folder. (unless `--file-list` or `--file-pair-list` is provided using `transfer_info` parameter `ascp_args`).

In addition to standard methods described in section [File List](#file_list), it is possible to specify the list of file using those additional methods:

- Using the pseudo <%=trspec%> parameter `EX_file_list`

```bash
--sources=@ts --ts=@json:'{"EX_file_list":"file_list.txt"}'
```

- Using option `transfer_info` parameter `ascp_args`

```bash
--sources=@ts --transfer-info=@json:'{"ascp_args":["--file-list","myfilelist"]}'
```

> **Note:** File lists is shown here, there are also similar options for file pair lists.
>
> **Note:** Those 2 additional methods avoid the creation of a copy of the file list: if the standard options `--sources=@lines:@file:... --src-type=...` are used, then the file is list read and parsed, and a new file list is created in a temporary folder.
>
> **Note:** Those methods have limitations: they apply **only** to the [`direct`](#agt_direct) transfer agent (i.e. local `ascp`) and not for Aspera on Cloud.

This agent supports a local configuration file: `aspera.conf` where Virtual links can be configured:

On a server (HSTS), the following commands can be used to set a global virtual link:

```bash
asconfigurator -x 'set_trunk_data;id,1;trunk_name,in;trunk_capacity,45000;trunk_on,true'
asconfigurator -x 'set_trunk_data;id,2;trunk_name,out;trunk_capacity,45000;trunk_on,true'
asconfigurator -x 'set_node_data;transfer_in_bandwidth_aggregate_trunk_id,1'
asconfigurator -x 'set_node_data;transfer_out_bandwidth_aggregate_trunk_id,2'
```

But this command is not available on clients, so edit the file `aspera.conf`, you can find the location with: `<%=cmd%> conf ascp info --fields=aspera_conf` and modify the sections `default` and `trunks` like this for a global 100 Mbps virtual link:

```xml
<?xml version='1.0' encoding='UTF-8'?>
<CONF version="2">
    <default>
        <transfer>
            <in>
                <bandwidth>
                    <aggregate>
                        <trunk_id>1</trunk_id>
                    </aggregate>
                </bandwidth>
            </in>
            <out>
                <bandwidth>
                    <aggregate>
                        <trunk_id>2</trunk_id>
                    </aggregate>
                </bandwidth>
            </out>
        </transfer>
    </default>
    <trunks>
        <trunk>
            <id>1</id>
            <name>in</name>
            <on>true</on>
            <capacity>
                <schedule format="ranges">1000000</schedule>
            </capacity>
        </trunk>
        <trunk>
            <id>2</id>
            <name>out</name>
            <capacity>
                <schedule format="ranges">1000000</schedule>
            </capacity>
            <on>true</on>
        </trunk>
    </trunks>
</CONF>
```

It is also possible to set a schedule with different time and days, for example for the value of `schedule`:

```text
start=08 end=19 days=mon,tue,wed,thu capacity=900000;1000000
```

#### <a id="agt_connect"></a>IBM Aspera Connect Client GUI

By specifying option: `--transfer=connect`, <%=tool%> will start transfers using the locally installed Aspera Connect Client. There are no option for `transfer_info`.

#### <a id="agt_node"></a>Aspera Node API : Node to node transfers

By specifying option: `--transfer=node`, <%=tool%> starts transfers in an Aspera Transfer Server using the Node API, either on a local or remote node.
Parameters provided in option `transfer_info` are:

| Name     | Type   | Description |
|----------|--------|-------------|
| url      | string | URL of the node API</br>Mandatory |
| username | string | node api user or access key</br>Mandatory |
| password | string | password, secret or bearer token</br>Mandatory |
| root_id  | string | password or secret</br>Mandatory only for bearer token |

Like any other option, `transfer_info` can get its value from a pre-configured <%=prst%> :
`--transfer-info=@preset:_name_here_` or be specified using the extended value syntax :
`--transfer-info=@json:'{"url":"https://...","username":"_user_here_","password":"my_password_here"}'`

If `transfer_info` is not specified and a default node has been configured (name in `node` for section `default`) then this node is used by default.

If the `password` value begins with `Bearer` then the `username` is expected to be an access key and the parameter `root_id` is mandatory and specifies the root file id on the node. It can be either the access key's root file id, or any authorized file id underneath it.

#### <a id="agt_httpgw"></a>HTTP Gateway

If it possible to send using a HTTP gateway, in case FASP is not allowed.

Parameters provided in option `transfer_info` are:

| Name                   | Type   | Description                           |
|------------------------|--------|---------------------------------------|
| url                    | string | URL of the HTTP GW</br>Mandatory      |
| upload_bar_refresh_sec | float  | Refresh rate for upload progress bar  |
| upload_chunk_size      | int    | Size in bytes of chunks for upload    |
| api_version            | string | v1 or v2, for force use of version    |
| synchronous            | bool   | wait for each message acknowledgment  |

Example:

```bash
<%=cmd%> faspex package recv 323 --transfer=httpgw --transfer-info=@json:'{"url":"https://asperagw.example.com:9443/aspera/http-gwy"}'
```

> **Note:** The gateway only supports transfers authorized with a token.

#### <a id="agt_trsdk"></a>Transfer SDK

Another possibility is to use the Transfer SDK daemon (`asperatransferd`).

By default it will listen on local port `55002` on `127.0.0.1`.

The gem `grpc` was removed from dependencies, as it requires compilation of a native part.
So, to use the Transfer SDK you should install this gem:

```bash
gem install grpc
```

On Windows the compilation may fail for various reasons (3.1.1):
<!-- spellchecker: disable -->
- `cannot find -lx64-ucrt-ruby310`
   &rarr; copy the file `[Ruby main dir]\lib\libx64-ucrt-ruby310.dll.a` to `[Ruby main dir]\lib\libx64-ucrt-ruby310.a` (remove the dll extension)
- `conflicting types for 'gettimeofday'`
  &rarr; edit the file `[Ruby main dir]/include/ruby-[version]/ruby/win32.h` and change the signature of `gettimeofday` to `gettimeofday(struct timeval *, void *)` ,i.e. change `struct timezone` to `void`
<!-- spellchecker: enable -->

### <a id="transferspec"></a>Transfer Specification

Some commands lead to file transfer (upload/download).
All parameters necessary for this transfer are described in a <%=trspec%> (Transfer Specification), such as:

- server address
- transfer user name
- credentials
- file list
- etc...

<%=tool%> builds the <%=trspec%> internally, so it is not necessary to provide additional parameters on the command line for this transfer.

The <%=trspec%> is a Hash (dictionary), so it is described on the command line with the [Extended Value Syntax](#extended).

It is possible to modify or add any of the supported <%=trspec%> parameter using the `ts` option.
The `ts` option accepts a [Structured Value](#native) containing one or several <%=trspec%> parameters in a `Hash`.
Multiple `ts` options on command line are cumulative, and Hash is deeply merged.
To remove a (deep) key from transfer spec, set the value to `null`.

> **Note:** Default transfer spec values can be displayed with command: `config ascp info --flat-hash=no` under field `ts`.

It is possible to specify `ascp` options when the `transfer` option is set to [`direct`](#agt_direct) using `transfer_info` option parameter: `ascp_args`.
Example: `--transfer-info=@json:'{"ascp_args":["-l","100m"]}'`.
This is especially useful for `ascp` command line parameters not supported in the transfer spec.

The use of a <%=trspec%> instead of `ascp` parameters has the advantage of:

- common to all [Transfer Agent](#agents)
- not dependent on command line limitations (special characters...)

### <a id="transferparams"></a>Transfer Parameters

All standard <%=trspec%> parameters can be specified.
<%=trspec%> can also be saved/overridden in the config file.

References:

- [Aspera Node API Documentation](https://developer.ibm.com/apis/catalog?search=%22aspera%20node%20api%22) &rarr; /opt/transfers
- [Aspera Transfer SDK Documentation](https://developer.ibm.com/apis/catalog?search=%22aspera%20transfer%20sdk%22) &rarr; Guides &rarr; API Ref &rarr; Transfer Spec V1
- [Aspera Connect SDK](https://d3gcli72yxqn2z.cloudfront.net/connect/v4/asperaweb-4.js) &rarr; search `The parameters for starting a transfer.`

Parameters can be displayed with commands:

```bash
<%=cmd%> config ascp spec
<%=cmd%> config ascp spec --select=@json:'{"d":"Y"}' --fields=-d,n,c
```

Columns:

- D=Direct (local `ascp` execution)
- N=Node API
- C=Connect Client

`ascp` argument or environment variable is provided in description.

Fields with EX_ prefix are extensions to transfer agent [`direct`](#agt_direct). (only in <%=tool%>).

<%=spec_table%>

#### Destination folder for transfers

The destination folder is set by <%=tool%> by default to:

- `.` for downloads
- `/` for uploads

It is specified by the <%=trspec%> parameter `destination_root`.
As such, it can be modified with option: `--ts=@json:'{"destination_root":"<path>"}'`.
The option `to_folder` provides an equivalent and convenient way to change this parameter:
`--to-folder=<path>` .

#### <a id="file_list"></a>List of files for transfers

When uploading, downloading or sending files, the user must specify the list of files to transfer.

By default the list of files to transfer is simply provided on the command line.

The list of (source) files to transfer is specified by (extended value) option `sources` (default: `@args`).
The list is either simply the list of source files, or a combined source/destination list (see below) depending on value of option `src_type` (default: `list`).

In <%=tool%>, all transfer parameters, including file list, are provided to the transfer agent in a <%=trspec%> so that execution of a transfer is independent of the transfer agent (direct, connect, node, transfer sdk...).
So, eventually, the list of files to transfer is provided to the transfer agent using the <%=trspec%> field: `"paths"` which is a list (array) of pairs of `"source"` (mandatory) and `"destination"` (optional).
The `sources` and `src_type` options provide convenient ways to populate the transfer spec with the source file list.

Possible values for option `sources` are:

- `@args` : (default) the list of files (or file pair) is directly provided on the command line (after commands): unused arguments (not starting with `-`) are considered as source files.
So, by default, the list of files to transfer will be simply specified on the command line. Example:

  ```bash
  <%=cmd%> server upload ~/first.file secondfile
  ```

  This is the same as (with default values):

  ```bash
  <%=cmd%> server upload --sources=@args --src-type=list ~/mysample.file secondfile
  ```

- an [Extended Value](#extended) with type **Array of String**

  > **Note:** extended values can be tested with the command `conf echo`

  Examples:

  - Using extended value

    Create the file list:

    ```bash
    echo ~/mysample.file > myfilelist.txt
    echo secondfile >> myfilelist.txt
    ```

    Use the file list: one path per line:

    ```ruby
    --sources=@lines:@file:myfilelist.txt
    ```

  - Using JSON array

    ```bash
    --sources=@json:'["file1","file2"]'
    ```

  - Using STDIN, one path per line

    ```bash
    --sources=@lines:@stdin:
    ```

  - Using Ruby code (one path per line in file)

    ```ruby
    --sources=@ruby:'File.read("myfilelist.txt").split("\n")'
    ```

- `@ts` : the user provides the list of files directly in the `paths` field of transfer spec (option `ts`).
Examples:

  - Using transfer spec

  ```bash
  --sources=@ts --ts=@json:'{"paths":[{"source":"file1"},{"source":"file2"}]}'
  ```

The option `src_type` allows specifying if the list specified in option `sources` is a simple file list or if it is a file pair list.

> **Note:** Option `src_type` is not used if option `sources` is set to `@ts`

Supported values for `src_type` are:

- `list` : (default) the path of destination is the same as source and each entry is a source file path
- `pair` : the first element is the first source, the second element is the first destination, and so on.

Example: Source file `200KB.1` is renamed `sample1` on destination:

```bash
<%=cmd%> server upload --src-type=pair ~/Documents/Samples/200KB.1 /Upload/sample1
```

> **Note:** There are some specific rules to specify a file list when using **Aspera on Cloud**, refer to the AoC plugin section.

#### <a id="multisession"></a>Support of multi-session

Multi session, i.e. starting a transfer of a file set using multiple sessions (one `ascp` process per session) is supported on `direct` and `node` agents, not yet on connect.

- `--transfer=node`

```bash
--ts=@json:'{"multi_session":10,"multi_session_threshold":1}'
```

Multi-session is directly supported by the node daemon.

- `--transfer=direct`

```bash
--ts=@json:'{"multi_session":5,"multi_session_threshold":1,"resume_policy":"none"}'
```

Note: `resume_policy` set to `attr` may cause problems: `none` or `sparse_csum` shall be preferred.

<%=tool%> starts multiple `ascp` for Multi-session using `direct` agent.

When multi-session is used, one separate UDP port is used per session (refer to `ascp` manual page).

#### Content protection

Also known as Client-side encryption at rest (CSEAR), content protection allows a client to send files to a server which will store them encrypted (upload), and decrypt files as they are being downloaded from a server, both using a passphrase, only known by users sharing files.
Files stay encrypted on server side.

Activating CSEAR consists in using transfer spec parameters:

- `content_protection` : activate encryption (`encrypt` for upload) or decryption (`decrypt` for download)
- `content_protection_password` : the passphrase to be used.

Example: parameter to download a faspex package and decrypt on the fly

```bash
--ts=@json:'{"content_protection":"decrypt","content_protection_password":"my_password_here"}'
```

#### Transfer Spec Examples

- Change target rate

```bash
--ts=@json:'{"target_rate_kbps":500000}'
```

- Override the FASP SSH port to a specific TCP port:

```bash
--ts=@json:'{"ssh_port":33002}'
```

- Force http fallback mode:

```bash
--ts=@json:'{"http_fallback":"force"}'
```

- Activate progress when not activated by default on server

```bash
--ts=@json:'{"precalculate_job_size":true}'
```

### <a id="scheduler"></a>Scheduler

It is useful to configure automated scheduled execution.
<%=tool%> does not provide an internal scheduler.
Instead, use the service provided by the Operating system:

#### Windows Scheduler

Windows provides the [Task Scheduler](https://docs.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-start-page).
It can be configured:

- Using utility [`schtasks.exe`](https://learn.microsoft.com/fr-fr/windows-server/administration/windows-commands/schtasks-create)

- Using powershell function [scheduletasks](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks)

- Using `taskschd.msc` (UI)

#### Unix-like Scheduler

Unix-like systems (Linux, ...) provide cron, configured using a [crontab](https://www.man7.org/linux/man-pages/man5/crontab.5.html)

Linux also provides `anacron`, if tasks are hourly or daily.

For example, on Linux it is convenient to create a wrapping script, e.g. `cron_<%=cmd%>` that will setup the environment (e.g. Ruby) to properly start <%=tool%>:

```bash
#!/bin/bash
# load the ruby environment
. /etc/profile.d/rvm.sh
rvm use 2.6 --quiet
# set a timeout protection, just in case <%=cmd%> is frozen 
tmout=30m
# forward arguments to <%=cmd%>
exec timeout ${tmout} <%=cmd%> "${@}"
```

Example of cronjob created for user `xfer`.

```bash
crontab<<EOF
0    * * * *  /home/xfer/cron_<%=cmd%> preview scan --logger=syslog --display=error
2-59 * * * *  /home/xfer/cron_<%=cmd%> preview trev --logger=syslog --display=error
EOF
```

> **Note:** The logging options are kept here in the cronfile instead of conf file to allow execution on command line with output on command line.

### <a id="locking"></a>Locking for exclusive execution

In some cases one needs to ensure that <%=tool%> is not executed several times in parallel.

When <%=tool%> is executed automatically on a schedule basis, one generally desires that a new execution is not started if a previous execution is still running because an on-going operation may last longer than the scheduling period:

- Executing instances may pile-up and kill the system
- The same file may be transferred by multiple instances at the same time.
- `preview` may generate the same files in multiple instances.

Usually the OS native scheduler already provides some sort of protection against parallel execution:

- The Windows scheduler does this by default
- Linux cron can leverage the utility [`flock`](https://linux.die.net/man/1/flock) to do the same:

```bash
/usr/bin/flock -w 0 /var/cron.lock <%=cmd%> ...
```

<%=tool%> natively supports a locking mechanism with option `lock_port`.
(Technically, this opens a local TCP server port, and fails if this port is already used, providing a local lock. Lock is released when process exits).

Testing <%=tool%> locking:

Run this same command in two separate terminals within less than 30 seconds:

```bash
<%=cmd%> config echo @ruby:'sleep(30)' --lock-port=12345
```

The first instance will sleep 30 seconds, the second one will immediately exit like this:

```bash
WARN -- : Another instance is already running (Address already in use - bind(2) for "127.0.0.1" port 12345).
```

### "Proven&ccedil;ale"

`ascp`, the underlying executable implementing Aspera file transfer using FASP, has a capability to not only access the local file system (using system's `open`,`read`,`write`,`close` primitives), but also to do the same operations on other data storage such as S3, Hadoop and others. This mechanism is call *PVCL*. Several *PVCL* adapters are available, some are embedded in `ascp`
, some are provided om shared libraries and must be activated. (e.g. using `trapd`)

The list of supported *PVCL* adapters can be retrieved with command:

```bash
<%=cmd%> conf ascp info
```

```output
+--------------------+-----------------------------------------------------------+
| key                | value                                                     |
+--------------------+-----------------------------------------------------------+
-----8<-----snip-----8<-----
| product_name       | IBM Aspera SDK                                            |
| product_version    | 4.0.1.182389                                              |
| process            | pvcl                                                      |
| shares             | pvcl                                                      |
| noded              | pvcl                                                      |
| faux               | pvcl                                                      |
| file               | pvcl                                                      |
| stdio              | pvcl                                                      |
| stdio-tar          | pvcl                                                      |
+--------------------+-----------------------------------------------------------+
```

Here we can see the adapters: `process`, `shares`, `noded`, `faux`, `file`, `stdio`, `stdio-tar`.

Those adapters can be used wherever a file path is used in `ascp` including configuration. They act as a pseudo "drive".

The simplified format is:

```bash
<adapter>:///<sub file path>?<arg1>=<val1>&...
```

One of the adapters, used in this manual, for testing, is `faux`. It is a pseudo file system allowing generation of file data without actual storage (on source or destination).

### <a id="faux_testing"></a>`faux:` for testing

This is an extract of the man page of `ascp`.
This feature is a feature of `ascp`, not <%=tool%>.

This adapter can be used to simulate a file or a directory.

To discard data at the destination, the destination argument is set to `faux://`.

To send uninitialized data in place of an actual source file, the source file is replaced with an argument of the form:

```bash
faux:///filename?filesize
```

where:

- `filename` is the name that will be assigned to the file on the destination
- `filesize` is the number of bytes that will be sent (in decimal).

Note: characters `?` and `&` are shell special characters (wildcard and background), so `faux` file specification on command line should be protected (using quotes or `\`). If not, the shell may give error: `no matches found` or equivalent.

For all sizes, a suffix can be added (case insensitive) to the size: k,m,g,t,p,e (values are power of 2, e.g. 1M is 2<sup>20</sup>, i.e. 1 mebibyte, not megabyte). The maximum allowed value is 8*2<sup>60</sup>. Very large `faux` file sizes (petabyte range and above) will likely fail due to lack of destination storage unless destination is `faux://`.

To send uninitialized data in place of a source directory, the source argument is replaced with an argument of the form:

```bash
faux:///dirname?<arg1>=<val1>&...
```

where:

- `dirname` is the folder name and can contain `/` to specify a subfolder.
- supported arguments are:

| Name   | Type | Description |
|--------|------|-------------|
|count   |int   |mandatory|Number of files<br/>Mandatory|
|file    |string|Basename for files<br>Default: "file"|
|size    |int   |Size of first file.<br>Default: 0|
|inc     |int   |Increment applied to determine next file size<br>Default: 0|
|seq     |enum  |Sequence in determining next file size<br/>Values: random, sequential<br/>Default: sequential|
|buf_init|enum  |How source data is initialized<br/>Option 'none' is not allowed for downloads.<br/>Values:none, zero, random<br/>Default:zero|

The sequence parameter is applied as follows:

- If `seq` is `random` then each file size is:

  - size +/- (inc * rand())
  - Where rand is a random number between 0 and 1
  - Note that file size must not be negative, inc will be set to size if it is greater than size
  - Similarly, overall file size must be less than 8*2<sup>60</sup>. If size + inc is greater, inc will be reduced to limit size + inc to 7*2<sup>60</sup>.

- If `seq` is `sequential` then each file size is:

  - `size + ((file_index - 1) * inc)`
  - Where first file is index 1
  - So file1 is `size` bytes, file2 is `size + inc` bytes, file3 is `size + inc * 2` bytes, etc.
  - As with `random`, `inc` will be adjusted if `size + (count * inc)` is not less then 8*2<sup>60</sup>.

Filenames generated are of the form: `<file>_<00000 ... count>_<filesize>`

Examples:

- Upload 20 gibibytes of random data to file myfile to directory /Upload

```bash
<%=cmd%> server upload faux:///myfile\?20g --to-folder=/Upload
```

- Upload a file /tmp/sample but do not save results to disk (no docroot on destination)

```bash
<%=cmd%> server upload /tmp/sample --to-folder=faux://
```

- Upload a faux directory `mydir` containing 1 million files, sequentially with sizes ranging from 0 to 2 Mebibyte - 2 bytes, with the basename of each file being `testfile` to /Upload

```bash
<%=cmd%> server upload "faux:///mydir?file=testfile&count=1m&size=0&inc=2&seq=sequential" --to-folder=/Upload
```

### <a id="usage"></a>Usage

```text
<%=cmd%> -h
<%=include_usage%>

```

> **Note:** commands and parameter values can be written in short form.

### Bulk creation and deletion of resources

Bulk creation and deletion of resources are possible using option `bulk` (yes,no(default)).
In that case, the operation expects an Array of Hash instead of a simple Hash using the [Extended Value Syntax](#extended).
This option is available only for some of the resources: if you need it: try and see if the entities you try to create or delete support this option.

## <a id="aoc"></a>Plugin: `aoc`: IBM Aspera on Cloud

Aspera on Cloud uses the more advanced Oauth v2 mechanism for authentication (HTTP Basic authentication is not supported).

It is recommended to use the wizard to set it up, but manual configuration is also possible.

### <a id="aocwizard"></a>Configuration: using Wizard

<%=tool%> provides a configuration wizard. Here is a sample invocation :

```text
<%=cmd%> config wizard
option: url> https://myorg.ibmaspera.com
Detected: Aspera on Cloud
Preparing preset: aoc_myorg
Please provide path to your private RSA key, or empty to generate one:
option: pkeypath>
using existing key:
/Users/myself/.aspera/<%=cmd%>/aspera_aoc_key
Using global client_id.
option: username> john@example.com
Updating profile with new key
creating new config preset: aoc_myorg
Setting config preset as default for aspera
saving config file
Done.
You can test with:
<%=cmd%> aoc user profile show
```

Optionally, it is possible to create a new organization-specific "integration", i.e. client application identification.
For this, specify the option: `--use-generic-client=no`.

This will guide you through the steps to create.

If the wizard does not detect the application but you know the application, you can force it using option `query`:

```bash
<%=cmd%> config wizard --query=aoc
```

### <a id="aocmanual"></a>Configuration: using manual setup

> **Note:** If you used the wizard (recommended): skip this section.

#### Configuration details

Several types of OAuth authentication are supported:

- JSON Web Token (JWT) : authentication is secured by a private key (recommended for <%=tool%>)
- Web based authentication : authentication is made by user using a browser
- URL Token : external users authentication with url tokens (public links)

The authentication method is controlled by option `auth`.

For a *quick start*, follow the mandatory and sufficient section: [API Client Registration](#clientreg) (auth=web) as well as [<%=prst%> for Aspera on Cloud](#aocpreset).

For a more convenient, browser-less, experience follow the [JWT](#jwt) section (auth=jwt) in addition to Client Registration.

In Oauth, a "Bearer" token are generated to authenticate REST calls. Bearer tokens are valid for a period of time.<%=tool%> saves generated tokens in its configuration folder, tries to re-use them or regenerates them when they have expired.

#### <a id="clientreg"></a>Optional: API Client Registration

If you use the built-in client_id and client_secret, skip this and do not set them in next section.

Else you can use a specific OAuth API client_id, the first step is to declare <%=tool%> in Aspera on Cloud using the admin interface.

([AoC documentation: Registering an API Client](https://ibmaspera.com/help/admin/organization/registering_an_api_client) ).

Let's start by a registration with web based authentication (auth=web):

- Open a web browser, log to your instance: e.g. `https://myorg.ibmaspera.com/`
- Go to Apps &rarr; Admin &rarr; Organization &rarr; Integrations
- Click "Create New"
  - Client Name: <%=tool%>
  - Redirect URIs: `http://localhost:12345`
  - Origins: `localhost`
  - uncheck "Prompt users to allow client to access"
  - leave the JWT part for now
- Save

Note: for web based authentication, <%=tool%> listens on a local port (e.g. specified by the redirect_uri, in this example: 12345), and the browser will provide the OAuth code there. For `<%=tool%>, HTTP is required, and 12345 is the default port.

Once the client is registered, a "Client ID" and "Secret" are created, these values will be used in the next step.

#### <a id="aocpreset"></a><%=prst%> for Aspera on Cloud

If you did not use the wizard, you can also manually create a <%=prst%> for <%=tool%> in its configuration file.

Lets create an <%=prst%> called: `my_aoc_org` using `ask` interactive input (client info from previous step):

```bash
<%=cmd%> config preset ask my_aoc_org url client_id client_secret
option: url> https://myorg.ibmaspera.com/
option: client_id> my_client_id_here
option: client_secret> my_client_secret_here
updated: my_aoc_org
```

(This can also be done in one line using the command `config preset update my_aoc_org --url=...`)

Define this <%=prst%> as default configuration for the `aspera` plugin:

```bash
<%=cmd%> config preset set default aoc my_aoc_org
```

Note: Default `auth` method is `web` and default `redirect_uri` is `http://localhost:12345`. Leave those default values.

#### <a id="jwt"></a>Activation of JSON Web Token (JWT) for direct authentication

For a Browser-less, Private Key-based authentication, use the following steps.

In order to use JWT for Aspera on Cloud API client authentication,
a [private/public key pair](#private_key) must be used.

##### API Client JWT activation

If you are not using the built-in client_id and secret, JWT needs to be authorized in Aspera on Cloud. This can be done in two manners:

- Graphically

  - Open a web browser, log to your instance: `https://myorg.ibmaspera.com/`
  - Go to Apps &rarr; Admin &rarr; Organization &rarr; Integrations
  - Click on the previously created application
  - select tab : "JSON Web Token Auth"
  - Modify options if necessary, for instance: activate both options in section "Settings"
  - Click "Save"

- Using command line

```bash
<%=cmd%> aoc admin res client list
```

```output
+------------+---------------+
|     id     |  name         |
+------------+---------------+
| my_BJbQiFw | my-client-app |
+------------+---------------+
```

```bash
<%=cmd%> aoc admin res client modify my_BJbQiFw @json:'{"jwt_grant_enabled":true,"explicit_authorization_required":false}'
```

```output
modified
```

#### User key registration

The public key must be assigned to your user. This can be done in two manners:

##### Graphically

Open the previously generated public key located here: `$HOME/.aspera/<%=cmd%>/my_private_key.pub`

- Open a web browser, log to your instance: `https://myorg.ibmaspera.com/`
- Click on the user's icon (top right)
- Select "Account Settings"
- Paste the *Public Key* in the "Public Key" section
- Click on "Submit"

##### Using command line

```bash
<%=cmd%> aoc admin res user list
```

```output
+--------+----------------+
|   id   |      name      |
+--------+----------------+
| 109952 | Tech Support   |
| 109951 | LAURENT MARTIN |
+--------+----------------+
```

```ruby
<%=cmd%> aoc user profile modify @ruby:'{"public_key"=>File.read(File.expand_path("~/.aspera/<%=cmd%>/my_private_key.pub"))}'
```

```output
modified
```

Note: the `aspera user info show` command can be used to verify modifications.

#### <%=prst%> modification for JWT

To activate default use of JWT authentication for <%=tool%> using the <%=prst%>, do the following:

- change auth method to JWT
- provide location of private key
- provide username to login as (OAuth "subject")

Execute:

```bash
<%=cmd%> config preset update my_aoc_org --auth=jwt --private-key=@val:@file:~/.aspera/<%=cmd%>/my_private_key --username=laurent.martin.aspera@fr.ibm.com
```

Note: the private key argument represents the actual PEM string. In order to read the content from a file, use the `@file:` prefix. But if the @file: argument is used as is, it will read the file and set in the config file. So to keep the "@file" tag in the configuration file, the `@val:` prefix is added.

After this last step, commands do not require web login anymore.

#### <a id="aocfirst"></a>First Use

Once client has been registered and <%=prst%> created: <%=tool%> can be used:

```bash
<%=cmd%> aoc files br /
```

```output
Current Workspace: Default Workspace (default)
empty
```

### Calling AoC APIs from command line

The command `<%=cmd%> aoc bearer` can be used to generate an OAuth token suitable to call any AoC API (use the `scope` option to change the scope, default is `user:all`).
This can be useful when a command is not yet available.

Example:

```bash
curl -s -H "Authorization: $(<%=cmd%> aoc bearer_token)" 'https://api.ibmaspera.com/api/v1/group_memberships?embed[]=dropbox&embed[]=workspace'|jq -r '.[]|(.workspace.name + " -> " + .dropbox.name)'
```

It is also possible to get the bearer token for node, as user or as admin using:

```bash
<%=cmd%> aoc files bearer_token_node /
```

```bash
<%=cmd%> aoc admin res node v4 1234 --secret=_ak_secret_here_ bearer_token_node /
```

### Administration

The `admin` command allows several administrative tasks (and require admin privilege).

It allows actions (create, update, delete) on "resources": users, group, nodes, workspace, etc... with the `admin resource` command.

#### Listing resources

The command `aoc admin res <type> list` lists all entities of given type. It uses paging and multiple requests if necessary.

The option `query` can be optionally used. It expects a Hash using [Extended Value Syntax](#extended), generally provided using: `--query=@json:{...}`. Values are directly sent to the API call and used as a filter on server side.

The following parameters are supported:

- `q` : a filter on name of resource (case insensitive, matches if value is contained in name)
- `sort`: name of fields to sort results, prefix with `-` for reverse order.
- `max` : maximum number of items to retrieve (stop pages when the maximum is passed)
- `pmax` : maximum number of pages to request (stop pages when the maximum is passed)
- `page` : native api parameter, in general do not use (added by
- `per_page` : native api parameter, number of items par api call, in general do not use
- Other specific parameters depending on resource type.

Both `max` and `pmax` are processed internally in <%=tool%>, not included in actual API call and limit the number of successive pages requested to API. <%=tool%> will return all values using paging if not provided.

Other parameters are directly sent as parameters to the GET request on API.

`page` and `per_page` are normally added by <%=tool%> to build successive API calls to get all values if there are more than 1000. (AoC allows a maximum page size of 1000).

`q` and `sort` are available on most resource types.

Other parameters depend on the type of entity (refer to AoC API).

Examples:

- List users with `laurent` in name:

```bash
<%=cmd%> aoc admin res user list --query=--query=@json:'{"q":"laurent"}'
```

- List users who logged-in before a date:

```bash
<%=cmd%> aoc admin res user list --query=@json:'{"q":"last_login_at:<2018-05-28"}'
```

- List external users and sort in reverse alphabetical order using name:

```bash
<%=cmd%> aoc admin res user list --query=@json:'{"member_of_any_workspace":false,"sort":"-name"}'
```

Refer to the AoC API for full list of query parameters, or use the browser in developer mode with the web UI.

> **Note:** The option `select` can also be used to further refine selection, refer to [section earlier](#option_select).

#### <a id="res_select"></a>Selecting a resource

Resources are identified by a unique `id`, as well as a unique `name` (case insensitive).

To execute an action on a specific resource, select it using one of those methods:

- *recommended*: give id directly on command line *after the action*: `aoc admin res node show 123`
- give name on command line *after the action*: `aoc admin res node show name abc`
- provide option `id` : `aoc admin res node show 123`
- provide option `name` : `aoc admin res node show --name=abc`

#### <a id="res_create"></a>Creating a resource

New resources (users, groups, workspaces, etc..) can be created using a command like:

```bash
<%=cmd%> aoc admin res create <resource type> @json:'{<...parameters...>}'
```

Some of the API endpoints are described [here](https://developer.ibm.com/apis/catalog?search=%22aspera%20on%20cloud%20api%22). Sadly, not all.

Nevertheless, it is possible to guess the structure of the creation value by simply dumping an existing resource, and use the same parameters for the creation.

```bash
<%=cmd%> aoc admin res group show 12345 --format=json
```

```json
{"created_at":"2018-07-24T21:46:39.000Z","description":null,"id":"12345","manager":false,"name":"A8Demo WS1","owner":false,"queued_operation_count":0,"running_operation_count":0,"stopped_operation_count":0,"updated_at":"2018-07-24T21:46:39.000Z","saml_group":false,"saml_group_dn":null,"system_group":true,"system_group_type":"workspace_members"}
```

Remove the parameters that are either obviously added by the system: `id`, `created_at`, `updated_at` or optional.

And then craft your command:

```bash
<%=cmd%> aoc admin res group create @json:'{"description":"test to delete","name":"test 1 to delete","saml_group":false}'
```

If the command returns an error, example:

```output
+----+-----------------------------------------------------------------------------------+
| id | status                                                                            |
+----+-----------------------------------------------------------------------------------+
|    | found unpermitted parameters: :manager, :owner, :system_group, :system_group_type |
|    | code: unpermitted_parameters                                                      |
|    | request_id: b0f45d5b-c00a-4711-acef-72b633f8a6ea                                  |
|    | api.ibmaspera.com 422 Unprocessable Entity                                        |
+----+-----------------------------------------------------------------------------------+```
```

Well, remove the offending parameters and try again.

> **Note:** Some properties that are shown in the web UI, such as membership, are not listed directly in the resource, but instead another resource is created to link a user and its group: `group_membership`

#### Access Key secrets

In order to access some administrative actions on **nodes** (in fact, access keys), the associated secret is required.
The secret is provided using the `secret` option.
For example in a command like:

```bash
<%=cmd%> aoc admin res node 123 --secret="my_secret_here" v3 info
```

It is also possible to store secrets in the [secret vault](#vault) and then automatically find the related secret using the [config finder](#config_finder).

#### Activity

The activity app can be queried with:

```bash
<%=cmd%> aoc admin analytics transfers
```

It can also support filters and send notification using option `notif_to`. a template is defined using option `notif_template` :

`mytemplate.erb`:

```bash
From: <%='<'%>%=from_name%> <<%='<'%>%=from_email%>>
To: <<%='<'%>%=ev['user_email']%>>
Subject: <%='<'%>%=ev['files_completed']%> files received

Dear <%='<'%>%=ev[:user_email.to_s]%>,
We received <%='<'%>%=ev['files_completed']%> files for a total of <%='<'%>%=ev['transferred_bytes']%> bytes, starting with file:
<%='<'%>%=ev['content']%>

Thank you.
```

The environment provided contains the following additional variable:

- ev : all details on the transfer event

Example:

```bash
<%=cmd%> aoc admin analytics transfers --once-only=yes --lock-port=12345 \
--query=@json:'{"status":"completed","direction":"receive"}' \
--notif-to=active --notif-template=@file:mytemplate.erb
```

Options:

- `once_only` keep track of last date it was called, so next call will get only new events
- `query` filter (on API call)
- `notify` send an email as specified by template, this could be places in a file with the `@file` modifier.

> **Note:** This must not be executed in less than 5 minutes because the analytics interface accepts only a period of time between 5 minutes and 6 months. The period is [date of previous execution]..[now].

#### Transfer: Using specific transfer ports

By default transfer nodes are expected to use ports TCP/UDP 33001. The web UI enforces that.
The option `default_ports` ([yes]/no) allows <%=cmd%> to retrieve the server ports from an API call (download_setup) which reads the information from `aspera.conf` on the server.

#### Using ATS

Refer to section "Examples" of [ATS](#ats) and substitute command `ats` with `aoc admin ats`.

#### Files with type `link`

Aspera on Cloud Shared folders are implemented through a special type of file: `link`.
A `link` is the equivalent of a symbolic link on a file system: it points to another folder (not file).

Listing a link (in terminal position of path) will information on the link itself, not the content of the folder it points to.
To list the target folder content, add a `/` a the end of the path.

Example:

```console
$ ascli aoc files br the_link
Current Workspace: Default (default)
+------------+------+----------------+------+----------------------+--------------+
| name       | type | recursive_size | size | modified_time        | access_level |
+------------+------+----------------+------+----------------------+--------------+
| the_link   | link |                |      | 2021-04-28T09:17:14Z | edit         |
+------------+------+----------------+------+----------------------+--------------+
```

```console
$ ascli aoc files br the_link/
Current Workspace: Default (default)
+-------------+------+----------------+------+----------------------+--------------+
| name        | type | recursive_size | size | modified_time        | access_level |
+-------------+------+----------------+------+----------------------+--------------+
| file_inside | file |                |      | 2021-04-26T09:00:00Z | edit         |
+-------------+------+----------------+------+----------------------+--------------+
```

#### Example: Bulk creation of users

```bash
<%=cmd%> aoc admin res user create --bulk=yes @json:'[{"email":"dummyuser1@example.com"},{"email":"dummyuser2@example.com"}]'
```

```output
+-------+---------+
|  id   | status  |
+-------+---------+
| 98398 | created |
| 98399 | created |
+-------+---------+
```

#### Example: Find with filter and delete

```bash
<%=cmd%> aoc admin res user list --query='@json:{"q":"dummyuser"}' --fields=id,email
```

```output
+-------+------------------------+
|  id   |         email          |
+-------+------------------------+
| 98398 | dummyuser1@example.com |
| 98399 | dummyuser2@example.com |
+-------+------------------------+
```

```bash
thelist=$(<%=cmd%> aoc admin res user list --query='@json:{"q":"dummyuser"}' --fields=id --format=json --display=data|jq -cr 'map(.id)')
```

```bash
echo $thelist
```

```json
["113501","354061"]
```

```bash
<%=cmd%> aoc admin res user delete @json:"$thelist" --bulk=yes
```

```output
+-------+---------+
|  id   | status  |
+-------+---------+
| 98398 | deleted |
| 98399 | deleted |
+-------+---------+
```

#### Example: <a id="deactuser"></a>Find deactivated users since more than 2 years

```ruby
<%=cmd%> aoc admin res user list --query=@ruby:'{"deactivated"=>true,"q"=>"last_login_at:<#{(DateTime.now.to_time.utc-2*365*86400).iso8601}"}'
```

To delete them use the same method as before

#### Example: Display current user's workspaces

```bash
<%=cmd%> aoc user workspaces list
```

```output
+------+----------------------------+
|  id  |            name            |
+------+----------------------------+
| 16   | Engineering                |
| 17   | Marketing                  |
| 18   | Sales                      |
+------+----------------------------+
```

#### Example: Create a sub access key in a "node"

Creation of a sub-access key is like creation of access key with the following difference: authentication to node API is made with accesskey (master access key) and only the path parameter is provided: it is relative to the storage root of the master key. (id and secret are optional)

```bash
<%=cmd%> aoc admin resource node --name=_node_name_ --secret=_secret_ v4 access_key create @json:'{"storage":{"path":"/folder1"}}'
```

#### Example: Display transfer events (ops/transfer)

```bash
<%=cmd%> aoc admin res node --secret=_secret_ v3 transfer list --query=@json:'[["q","*"],["count",5]]'
```

Examples of query (TODO: cleanup):

```json
{"q":"type(file_upload OR file_delete OR file_download OR file_rename OR folder_create OR folder_delete OR folder_share OR folder_share_via_public_link)","sort":"-date"}
```

```json
{"tag":"aspera.files.package_id=LA8OU3p8w"}
```

#### Example: Display node events (events)

```bash
<%=cmd%> aoc admin res node --secret=_secret_ v3 events
```

#### Example: Display members of a workspace

```bash
<%=cmd%> aoc admin res workspace_membership list --fields=member_type,manager,member.email --query=@json:'{"embed":"member","inherited":false,"workspace_id":11363,"sort":"name"}'
```

```output
+-------------+---------+----------------------------------+
| member_type | manager |           member.email           |
+-------------+---------+----------------------------------+
| user        | true    | john.curtis@email.com            |
| user        | false   | laurent.martin.aspera@fr.ibm.com |
| user        | false   | jean.dupont@me.com               |
| user        | false   | another.user@example.com         |
| group       | false   |                                  |
| user        | false   | aspera.user@gmail.com            |
+-------------+---------+----------------------------------+
```

Other query parameters:

```json
{"workspace_membership_through":true,"include_indirect":true}
```

#### Example: <a id="aoc_sample_member"></a>add all members of a workspace to another workspace

a- Get id of first workspace

```bash
WS1='First Workspace'
WS1ID=$(<%=cmd%> aoc admin res workspace list --query=@json:'{"q":"'"$WS1"'"}' --select=@json:'{"name":"'"$WS1"'"}' --fields=id --format=csv)
```

b- Get id of second workspace

```bash
WS2='Second Workspace'
WS2ID=$(<%=cmd%> aoc admin res workspace list --query=@json:'{"q":"'"$WS2"'"}' --select=@json:'{"name":"'"$WS2"'"}' --fields=id --format=csv)
```

c- Extract membership information

```bash
<%=cmd%> aoc admin res workspace_membership list --fields=manager,member_id,member_type,workspace_id --query=@json:'{"workspace_id":'"$WS1ID"'}' --format=jsonpp > ws1_members.json
```

d- Convert to creation data for second workspace:

```bash
grep -Eve '(direct|effective_manager|_count|storage|"id")' ws1_members.json|sed '/workspace_id/ s/"'"$WS1ID"'"/"'"$WS2ID"'"/g' > ws2_members.json
```

or, using jq:

```bash
jq '[.[] | {member_type,member_id,workspace_id,manager,workspace_id:"'"$WS2ID"'"}]' ws1_members.json > ws2_members.json
```

e- Add members to second workspace

```bash
<%=cmd%> aoc admin res workspace_membership create --bulk=yes @json:@file:ws2_members.json
```

#### Example: Get users who did not log since a date

```bash
<%=cmd%> aoc admin res user list --fields=email --query=@json:'{"q":"last_login_at:<2018-05-28"}'
```

```output
+-------------------------------+
|             email             |
+-------------------------------+
| John.curtis@acme.com          |
| Jean.Dupont@tropfort.com      |
+-------------------------------+
```

#### Example: List "Limited" users

```bash
<%=cmd%> aoc admin res user list --fields=email --select=@json:'{"member_of_any_workspace":false}'
```

#### Example: create a group, add to workspace and add user to group

- Create the group and take note of `id`

```bash
<%=cmd%> aoc admin res group create @json:'{"name":"group 1","description":"my super group"}'
```

Group: `11111`

- Get the workspace id

```bash
<%=cmd%> aoc admin res workspace list --query=@json:'{"q":"myworkspace"}' --fields=id --format=csv --display=data
```

Workspace: 22222

- Add group to workspace

```bash
<%=cmd%> aoc admin res workspace_membership create @json:'{"workspace_id":22222,"member_type":"user","member_id":11111}'
```

- Get a user's id

```bash
<%=cmd%> aoc admin res user list --query=@json:'{"q":"manu.macron@example.com"}' --fields=id --format=csv --display=data
```

User: 33333

- Add user to group

```bash
<%=cmd%> aoc admin res group_membership create @json:'{"group_id":11111,"member_type":"user","member_id":33333}'
```

#### Example: Perform a multi Gbps transfer between two remote shared folders

In this example, a user has access to a workspace where two shared folders are located on different sites, e.g. different cloud regions.

First, setup the environment (skip if already done)

```bash
<%=cmd%> conf wizard --url=https://sedemo.ibmaspera.com --username=laurent.martin.aspera@fr.ibm.com
```

```output
Detected: Aspera on Cloud
Preparing preset: aoc_sedemo
Using existing key:
/Users/laurent/.aspera/<%=cmd%>/aspera_aoc_key
Using global client_id.
Please Login to your Aspera on Cloud instance.
Navigate to your "Account Settings"
Check or update the value of "Public Key" to be:
-----BEGIN PUBLIC KEY-----
SOME PUBLIC KEY PEM DATA HERE
-----END PUBLIC KEY-----
Once updated or validated, press enter.

creating new config preset: aoc_sedemo
Setting config preset as default for aspera
saving config file
Done.
You can test with:
<%=cmd%> aoc user profile show
```

This creates the option preset "aoc_&lt;org name&gt;" to allow seamless command line access and sets it as default for aspera on cloud.

Then, create two shared folders located in two regions, in your files home, in a workspace.

Then, transfer between those:

```bash
<%=cmd%> -Paoc_show aoc files transfer --from-folder='IBM Cloud SJ' --to-folder='AWS Singapore' 100GB.file --ts=@json:'{"target_rate_kbps":"1000000","multi_session":10,"multi_session_threshold":1}'
```

#### Example: create registration key to register a node

```bash
<%=cmd%> aoc admin res client create @json:'{"data":{"name":"laurentnode","client_subject_scopes":["alee","aejd"],"client_subject_enabled":true}}' --fields=token --format=csv
```

```output
jfqslfdjlfdjfhdjklqfhdkl
```

#### Example: delete all registration keys

```bash
<%=cmd%> aoc admin res client list --fields=id --format=csv|<%=cmd%> aoc admin res client delete @lines:@stdin: --bulk=yes
```

```output
+-----+---------+
| id  | status  |
+-----+---------+
| 99  | deleted |
| 100 | deleted |
| 101 | deleted |
| 102 | deleted |
+-----+---------+
```

#### Example: Create a Node

AoC nodes as actually composed with two related entities:

- An access key created on the Transfer Server (HSTS/ATS)
- a `node` resource in the AoC application.

The web UI allows creation of both entities in one shot.
For more flexibility, <%=tool%> allows this in two separate steps.

> **Note:** When selecting "Use existing access key" in the web UI, this actually skips access key creation (first step).

So, for example, the creation of a node using ATS in IBM Cloud looks like (see other example in this manual):

- Create the access key on ATS

  The creation options are the ones of ATS API, refer to the [section on ATS](#ats_params) for more details and examples.

  ```bash
  <%=cmd%> aoc admin ats access_key create --cloud=softlayer --region=eu-de --params=@json:'{"storage":{"type":"ibm-s3","bucket":"mybucket","credentials":{"access_key_id":"mykey","secret_access_key":"mysecret"},"path":"/"}}'
  ```

  Once executed, the access key `id` and `secret`, randomly generated by the node api, is displayed.
  
  > **Note:** Once returned by the API, the secret will not be available anymore, so store this preciously. ATS secrets can only be reset by asking to IBM support.

- Create the AoC node entity

  First, Retrieve the ATS node address

  ```bash
  <%=cmd%> aoc admin ats cluster show --cloud=softlayer --region=eu-de --fields=transfer_setup_url --format=csv --transpose-single=no
  ```

  Then use the returned address for the `url` key to actually create the AoC Node entity:

  ```bash
  <%=cmd%> aoc admin res node create @json:'{"name":"myname","access_key":"myaccesskeyid","ats_access_key":true,"ats_storage_type":"ibm-s3","url":"https://ats-sl-fra-all.aspera.io"}'
  ```

Creation of a node with a self-managed node is similar, but the command `aoc admin ats access_key create` is replaced with `node access_key create` on the private node itself.

### List of files to transfer

Source files are provided as a list with the `sources` option.
Refer to section [File list](#file_list)

> **Note:** A special case is when the source files are located on **Aspera on Cloud** (i.e. using access keys and the `file id` API).

Source files are located on "Aspera on cloud", when :

- the server is Aspera on Cloud, and executing a download or recv
- the agent is Aspera on Cloud, and executing an upload or send

In this case:

- If there is a single file : specify the full path
- Else, if there are multiple files:
  - All source files must be in the same source folder
  - Specify the source folder as first item in the list
  - followed by the list of file names.

### Packages

The webmail-like application.

#### Send a Package

General syntax:

```bash
<%=cmd%> aoc packages send [package extended value] [other parameters such as file list and transfer parameters]
```

Notes:

- Package creation parameter are sent as positional mandatory parameter.
  Refer to the AoC package creation API, or display an existing package in JSON to list attributes.
- List allowed shared inbox destinations with: `<%=cmd%> aoc packages shared_inboxes list`
- Use fields: `recipients` and/or `bcc_recipients` to provide the list of recipients: user or shared inbox.
  - Provide either ids as expected by API: `"recipients":[{"type":"dropbox","id":"1234"}]`
  - or just names: `"recipients":[{"The Dest"}]` . <%=cmd%> will resolve the list of email addresses and dropbox names to the expected type/id list, based on case insensitive partial match.
- If a user recipient (email) is not already registered and the workspace allows external users, then the package is sent to an external user, and
  - if the option `new_user_option` is `@json:{"package_contact":true}` (default), then a public link is sent and the external user does not need to create an account
  - if the option `new_user_option` is `@json:{}`, then external users are invited to join the workspace

#### Example: Send a package with one file to two users, using their email

```bash
<%=cmd%> aoc packages send @json:'{"name":"my title","note":"my note","recipients":["laurent.martin.aspera@fr.ibm.com","other@example.com"]}' my_file.dat
```

#### Example: Send a package to a shared inbox with metadata

```bash
<%=cmd%> aoc packages send --workspace=eudemo @json:'{"name":"my pack title","recipients":["Shared Inbox With Meta"],"metadata":{"Project Id":"123","Type":"Opt2","CheckThose":["Check1","Check2"],"Optional Date":"2021-01-13T15:02:00.000Z"}}' ~/Documents/Samples/200KB.1
```

It is also possible to use identifiers and API parameters:

```bash
<%=cmd%> aoc packages send --workspace=eudemo @json:'{"name":"my pack title","recipients":[{"type":"dropbox","id":"12345"}],"metadata":[{"input_type":"single-text","name":"Project Id","values":["123"]},{"input_type":"single-dropdown","name":"Type","values":["Opt2"]},{"input_type":"multiple-checkbox","name":"CheckThose","values":["Check1","Check2"]},{"input_type":"date","name":"Optional Date","values":["2021-01-13T15:02:00.000Z"]}]}' ~/Documents/Samples/200KB.1
```

#### Example: List packages in a given shared inbox

When user packages are listed, the following query is used:

```json
{"archived":false,"exclude_dropbox_packages":true,"has_content":true,"received":true}
```

To list packages in a shared inbox, the query has to be specified with the the shared inbox by name or its identifier.
Additional parameters can be specified, as supported by the API (to find out available filters, consult the API definition, or use the web interface in developer mode).
The current workspace is added unless specified in the query.

Using shared inbox name:

```bash
<%=cmd%> aoc packages list --query=@json:'{"dropbox_name":"My Shared Inbox","archived":false,"received":true,"has_content":true,"exclude_dropbox_packages":false,"include_draft":false,"sort":"-received_at"}'
```

Using shared inbox identifier: first retrieve the id of the shared inbox, and then list packages with the appropriate filter.

```bash
shared_box_id=$(<%=cmd%> aoc packages shared_inboxes show name 'My Shared Inbox' --format=csv --display=data --fields=id --transpose-single=no)
```

```bash
<%=cmd%> aoc packages list --query=@json:'{"dropbox_id":"'$shared_box_id'","archived":false,"received":true,"has_content":true,"exclude_dropbox_packages":false,"include_draft":false,"sort":"-received_at"}'
```

#### Example: Receive all packages from a given shared inbox

```bash
<%=cmd%> aoc packages recv ALL --workspace=_workspace_ --once-only=yes --lock-port=12345 --query=@json:'{"dropbox_name":"_shared_inbox_name_","archived":false,"received":true,"has_content":true,"exclude_dropbox_packages":false,"include_draft":false}' --ts=@json:'{"resume_policy":"sparse_csum","target_rate_kbps":50000}'
```

#### Example: Send a package with files from the Files app

Find files in Files app:

```bash
<%=cmd%> aoc files browse /src_folder
```

```bash
+------------------------------+--------+----------------+--------------+----------------------+--------------+
| name                         | type   | recursive_size | size         | modified_time        | access_level |
+------------------------------+--------+----------------+--------------+----------------------+--------------+
| sample_video                 | link   |                |              | 2020-11-29T22:49:09Z | edit         |
| 100G                         | file   |                | 107374182400 | 2021-04-21T18:19:25Z | edit         |
| 10M.dat                      | file   |                | 10485760     | 2021-05-18T08:22:39Z | edit         |
| Test.pdf                     | file   |                | 1265103      | 2022-06-16T12:49:55Z | edit         |
+------------------------------+--------+----------------+--------------+----------------------+--------------+
```

Let's send a package with the file `10M.dat` from subfolder /src_folder in a package:

```bash
<%=cmd%> aoc files node_info /src_folder --format=json --display=data | <%=cmd%> aoc packages send @json:'{"name":"test","recipients":["laurent.martin.aspera@fr.ibm.com"]}' 10M.dat --transfer=node --transfer-info=@json:@stdin:
```

#### <a id="aoccargo"></a>Receive new packages only (Cargo)

It is possible to automatically download new packages, like using Aspera Cargo:

```bash
<%=cmd%> aoc packages recv ALL --once-only=yes --lock-port=12345
```

- `ALL` (case sensitive) will download all packages
- `--once-only=yes` keeps memory of any downloaded package in persistency files located in the configuration folder
- `--lock-port=12345` ensures that only one instance is started at the same time, to avoid running two downloads in parallel

Typically, one would execute this command on a regular basis, using the method of your choice: see [Scheduler](#scheduler).

### Files

The Files application presents a **Home** folder to users in a given workspace.
Files located here are either user's files, or shared folders.

#### Download Files

The general download command is:

```bash
<%=cmd%> aoc files download <source folder path> <source filename 1> ...
```

I.e. the first argument is the source folder, and the following arguments are the source file names in this folder.

If a single file or folder is to be downloaded, then a single argument can be provided.

```bash
<%=cmd%> aoc files download <single file path>
```

#### Shared folders

Shared folder created by users are managed through **permissions**.
For creation, parameters are the same as for node api [permissions](https://developer.ibm.com/apis/catalog/aspera--aspera-node-api/api/API--aspera--node-api#post960739960).
<%=tool%> expects the same payload for creation, but it will automatically populate required tags if needed.
Also, the pseudo key `with` is available: it will lookup the name in the contacts and fill the proper type and id.
The pseudo parameter `link_name` allows changing default "shared as" name.

- List permissions on a shared folder as user

```bash
<%=cmd%> aoc files perm /shared_folder_test1 list
```

- Share a personal folder with other users

```bash
<%=cmd%> aoc files perm /shared_folder_test1 create @json:'{"with":"laurent"}'
```

- Revoke shared access

```bash
<%=cmd%> aoc files perm /shared_folder_test1 delete 6161
```

#### Cross Organization transfers

It is possible to transfer files directly between organizations without having to first download locally and then upload...

Although optional, the creation of <%=prst%> is recommended to avoid placing all parameters in the command line.

Procedure to send a file from org1 to org2:

- Get access to Organization 1 and create a <%=prst%>: e.g. `org1`, for instance, use the [Wizard](#aocwizard)
- Check that access works and locate the source file e.g. `mysourcefile`, e.g. using command `files browse`
- Get access to Organization 2 and create a <%=prst%>: e.g. `org2`
- Check that access works and locate the destination folder `mydestfolder`
- execute the following:

```bash
<%=cmd%> -Porg1 aoc files node_info /mydestfolder --format=json --display=data | <%=cmd%> -Porg2 aoc files upload mysourcefile --transfer=node --transfer-info=@json:@stdin:
```

Explanation:

- `-Porg1 aoc` use Aspera on Cloud plugin and load credentials for `org1`
- `files node_info /mydestfolder` generate transfer information including node api credential and root id, suitable for the next command
- `--format=json` format the output in JSON (instead of default text table)
- `--display=data` display only the result, and remove other information, such as workspace name
- `|` the standard output of the first command is fed into the second one
- `-Porg2 aoc` use Aspera on Cloud plugin and load credentials for `org2`
- `files upload mysourcefile` upload the file named `mysourcefile` (located in `org1`)
- `--transfer=node` use transfer agent type `node` instead of default [`direct`](#agt_direct)
- `--transfer-info=@json:@stdin:` provide `node` transfer agent information, i.e. node API credentials, those are expected in JSON format and read from standard input

#### Find Files

The command `aoc files find [--query=expression]` will recursively scan storage to find files matching the expression criteria. It works also on node resource using the v4 command. (see examples)

The expression can be of 3 formats:

- empty (default) : all files, equivalent to value: `exec:true`
- not starting with `exec:` : the expression is a regular expression, using [Ruby Regex](https://ruby-doc.org/core/Regexp.html) syntax, equivalent to value: `exec:f['name'].match(/expression/)`

  For instance, to find files with a special extension, use `--query='\.myext$'`

- starting with `exec:` : the Ruby code after the prefix is executed for each entry found. The entry variable name is `f`. The file is displayed if the result of the expression is true.

Examples of expressions: (using like this: `--query=exec:'<expression>'`)

- Find files more recent than 100 days

  ```ruby
  f["type"].eql?("file") and (DateTime.now-DateTime.parse(f["modified_time"]))<100
  ```

- Find files older than 1 year on a given node and store in file list

  ```ruby
  f["type"].eql?("file") and (DateTime.now-DateTime.parse(f["modified_time"]))<100
  ```

  ```bash
  <%=cmd%> aoc admin res node --name='my node name' --secret='my_secret_here' v4 find / --fields=path --query='exec:<above expression here>' --format=csv > my_file_list.txt
  ```

- Find files larger than 1MB

  ```ruby
  f["type"].eql?("file") and f["size"].to_i>1000000
  ```

- Delete the files, one by one

  ```bash
  cat my_file_list.txt|while read path;do echo <%=cmd%> aoc admin res node --name='my node name' --secret='my_secret_here' v4 delete "$path" ;done
  ```

- Delete the files in bulk

  ```bash
  cat my_file_list.txt | <%=cmd%> aoc admin res node --name='my node name' --secret='my_secret_here' v3 delete @lines:@stdin:
  ```

### AoC sample commands

```bash
<%=include_commands_for_plugin('aoc')%>
```

## <a id="ats"></a>Plugin: `ats`: IBM Aspera Transfer Service

ATS is usable either :

- from an AoC subscription : <%=cmd%> aoc admin ats : use AoC authentication

- or from an IBM Cloud subscription : <%=cmd%> ats : use IBM Cloud API key authentication

### IBM Cloud ATS : creation of api key

This section is about using ATS with an IBM cloud subscription.
If you are using ATS as part of AoC, then authentication is through AoC, not IBM Cloud.

First get your IBM Cloud APIkey. For instance, it can be created using the IBM Cloud web interface, or using command line:

```bash
ibmcloud iam api-key-create mykeyname -d 'my sample key'
```

```output
OK
API key mykeyname was created

Please preserve the API key! It cannot be retrieved after it's created.

Name          mykeyname
Description   my sample key
Created At    2019-09-30T12:17+0000
API Key       my_secret_api_key_here
Locked        false
UUID          ApiKey-05b8fadf-e7fe-4bc4-93a9-6fd348c5ab1f
```

References:
<!-- spellchecker: disable -->

- [https://console.bluemix.net/docs/iam/userid_keys.html#userapikey](https://console.bluemix.net/docs/iam/userid_keys.html#userapikey)
- [https://ibm.ibmaspera.com/helpcenter/transfer-service](https://ibm.ibmaspera.com/helpcenter/transfer-service)

<!-- spellchecker: enable -->

Then, to register the key by default for the ats plugin, create a preset. Execute:

```bash
<%=cmd%> config preset update my_ibm_ats --ibm-api-key=my_secret_api_key_here
```

```bash
<%=cmd%> config preset set default ats my_ibm_ats
```

```bash
<%=cmd%> ats api_key instances
```

```output
+--------------------------------------+
| instance                             |
+--------------------------------------+
| aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee |
+--------------------------------------+
```

```bash
<%=cmd%> config preset update my_ibm_ats --instance=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
```

```bash
<%=cmd%> ats api_key create
```

```output
+--------+----------------------------------------------+
| key    | value                                        |
+--------+----------------------------------------------+
| id     | ats_XXXXXXXXXXXXXXXXXXXXXXXX                 |
| secret | YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY |
+--------+----------------------------------------------+
<%=cmd%> config preset update my_ibm_ats --ats-key=ats_XXXXXXXXXXXXXXXXXXXXXXXX --ats-secret=YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY
```

### <a id="ats_params"></a>ATS Access key creation parameters

When creating an ATS access key, the option `params` must contain an extended value with the creation parameters.
Those are directly the parameters expected by the [ATS API](https://developer.ibm.com/apis/catalog?search=%22Aspera%20ATS%20API%22).

### Misc. Examples

Example: create access key on IBM Cloud (softlayer):

```bash
<%=cmd%> ats access_key create --cloud=softlayer --region=ams --params=@json:'{"storage":{"type":"softlayer_swift","container":"_container_name_","credentials":{"api_key":"my_secret_here","username":"_name_:_usr_name_"},"path":"/"},"id":"_optional_id_","name":"_optional_name_"}'
```

Example: create access key on AWS:

```bash
<%=cmd%> ats access_key create --cloud=aws --region=eu-west-1 --params=@json:'{"id":"myaccesskey","name":"laurent key AWS","storage":{"type":"aws_s3","bucket":"my-bucket","credentials":{"access_key_id":"_access_key_id_here_","secret_access_key":"my_secret_here"},"path":"/laurent"}}'
```

Example: create access key on Azure SAS:

```bash
<%=cmd%> ats access_key create --cloud=azure --region=eastus --params=@json:'{"id":"myaccesskey","name":"laurent key azure","storage":{"type":"azure_sas","credentials":{"shared_access_signature":"https://containername.blob.core.windows.net/blobname?sr=c&..."},"path":"/"}}'
```

(Note that the blob name is mandatory after server address and before parameters. and that parameter sr=c is mandatory.)

Example: create access key on Azure:

```bash
<%=cmd%> ats access_key create --cloud=azure --region=eastus --params=@json:'{"id":"myaccesskey","name":"laurent key azure","storage":{"type":"azure","credentials":{"account":"myaccount","key":"myaccesskey","storage_endpoint":"myblob"},"path":"/"}}'
```

delete all my access keys:

```bash
<%=cmd%> ats access_key list --field=id --format=csv | <%=cmd%> ats access_key delete @lines:@stdin: --bulk=yes
```

The parameters provided to ATS for access key creation are the ones of [ATS API](https://developer.ibm.com/apis/catalog?search=%22aspera%20ats%22) for the `POST /access_keys` endpoint.

### ATS sample commands

```bash
<%=include_commands_for_plugin('ats')%>
```

## <a id="server"></a>Plugin: `server`: IBM Aspera High Speed Transfer Server (SSH)

The `server` plugin is used for operations on Aspera HSTS using SSH authentication.
It is the legacy way of accessing an Aspera Server, often used for server to server transfers.
An SSH session is established, authenticated with either a password or an SSH private key,
then commands `ascp` (for transfers) and `ascmd` (for file operations) are executed.

> **Note:** The URL to be provided is usually: `ssh://_server_address_:33001`

### Server sample commands

```bash
<%=include_commands_for_plugin('server')%>
```

### Authentication on Server with SSH session

If SSH is the session protocol (by default i.e. not WSS), then following session authentication methods are supported:

- `password`: SSH password
- `ssh_keys`: SSH keys (Multiple SSH key paths can be provided.)

If `username` is not provided then the default transfer user `xfer` is used.

If no SSH password or key is provided and a transfer token is provided in transfer spec (option `ts`), then standard SSH bypass keys are used.
Example:

```bash
<%=cmd%> server --url=ssh://_server_address_:33001 ... --ts=@json:'{"token":"Basic _token_here_"}'
```

> **Note:** If you need to use the Aspera public keys, then specify an empty token: `--ts=@json:'{"token":""}'` : Aspera public SSH keys will be used, but the protocol will ignore the empty token.

The value of the `ssh_keys` option can be a single value or an `Array`.
Each value is a **path** to a private key and is expanded (`~` is replaced with the user's home folder).

Examples:

```bash
<%=cmd%> server --ssh-keys=~/.ssh/id_rsa
<%=cmd%> server --ssh-keys=@list:,~/.ssh/id_rsa
<%=cmd%> server --ssh-keys=@json:'["~/.ssh/id_rsa"]'
```

For file operation command (browse, delete), the Ruby SSH client library `Net::SSH` is used and provides several options settable using option `ssh_options`.

For a list of SSH client options, refer to the Ruby documentation of [Net::SSH](http://net-ssh.github.io/net-ssh/Net/SSH.html#method-c-start).

Some of the 50 available SSH options:

- `verbose`
- `use_agent`
- `passphrase`

By default the SSH library will check if a local `ssh-agent` is running.

On Linux, if you get an error message such as:

```bash
ERROR -- net.ssh.authentication.agent: could not connect to ssh-agent: Agent not configured
```

or on Windows:

```bash
ERROR -- net.ssh.authentication.agent: could not connect to ssh-agent: pageant process not running
```

This means that your environment suggests to use an agent but you don't have such an SSH agent running, then:

- Check env var: `SSH_AGENT_SOCK`
- Check your file: `$HOME/.ssh/config`
- Check if the SSH key is protected with a passphrase (then, use the `passphrase` SSH option)
- [Check the Ruby SSH manual](https://www.rubydoc.info/github/net-ssh/net-ssh/Net%2FSSH.start)
- To disable the use of `ssh-agent`, use the option `ssh_options` like this:

```bash
<%=cmd%> server --ssh-options=@json:'{"use_agent": false}' ...
```

> **Note:** This can also be set using a preset.

If one of the SSH private keys is passphrase-protected, then option `passphrase` can be used.
It is equivalent to setting both options `ssh_options.passphrase` and `ts.ssh_private_key_passphrase`.

### Other session channels for `server`

URL schemes `local` and `https` are also supported (mainly for testing purpose).
(`--url=local:` , `--url=https://...`)

- `local` will execute `ascmd` locally, instead of using an SSH connection.
- `https` will use Web Socket Session: This requires the use of a transfer token. For example a `Basic` token can be used.

As, most of the time, SSH is used, if an `http` scheme is provided without token, the plugin will fallback to SSH and port 33001.

### Examples: `server`

One can test the `server` application using the well known demo server:

```bash
<%=cmd%> config initdemo
<%=cmd%> server browse /aspera-test-dir-large
<%=cmd%> server download /aspera-test-dir-large/200MB
```

`initdemo` creates a <%=prst%> `demoserver` and set it as default for plugin `server`.

If an SSH private key is used for authentication with a passphrase, the passphrase needs to be provided to both options: `ssh_options`, for browsing, and `ts` for transfers:

```bash
<%=cmd%> server --url=ssh://_server_address_here_:33001 --username=_user_here_ --ssh_keys=_private_key_path_here_ --passphrase=_passphrase_here_
```

## <a id="node"></a>Plugin: `node`: IBM Aspera High Speed Transfer Server Node

This plugin gives access to capabilities provided by HSTS node API.

> **Note:** capabilities of this plugin are used in other plugins which access to the node API, such as `aoc`.

### File Operations

It is possible to:

- browse
- transfer (upload / download)
- ...

### Central

The central subcommand uses the "reliable query" API (session and file).
It allows listing transfer sessions and transferred files.

Filtering can be applied:

```bash
<%=cmd%> node central file list
```

by providing the `validator` option, offline transfer validation can be done.

### FASP Stream

It is possible to start a FASPStream session using the node API:

Use the "node stream create" command, then arguments are provided as a <%=trspec%>.

```bash
<%=cmd%> node stream create --ts=@json:'{"direction":"send","source":"udp://233.3.3.4:3000?loopback=1&ttl=2","destination":"udp://233.3.3.3:3001/","remote_host":"localhost","remote_user":"stream","remote_password":"my_pass_here"}' --preset=stream
```

### Watchfolder

Refer to [Aspera documentation](https://download.asperasoft.com/download/docs/entsrv/3.7.4/es_admin_linux/webhelp/index.html#watchfolder_external/dita/json_conf.html) for watch folder creation.

<%=tool%> supports remote operations through the node API. Operations are:

- Start watchd and watchfolderd services running as a system user having access to files
- configure a watchfolder to define automated transfers

```bash
<%=cmd%> node service create @json:'{"id":"mywatchd","type":"WATCHD","run_as":{"user":"user1"}}'
<%=cmd%> node service create @json:'{"id":"mywatchfolderd","type":"WATCHFOLDERD","run_as":{"user":"user1"}}'
<%=cmd%> node watch_folder create @json:'{"id":"mywfolder","source_dir":"/watch1","target_dir":"/","transport":{"host":"10.25.0.4","user":"user1","pass":"mypassword"}}'
```

### Out of Transfer File Validation

Follow the Aspera Transfer Server configuration to activate this feature.

```bash
<%=cmd%> node central file list --validator=<%=cmd%> --data=@json:'{"file_transfer_filter":{"max_result":1}}'
```

```output
+--------------+--------------+------------+--------------------------------------+
| session_uuid |    file_id   |   status   |              path                    |
+--------------+--------------+------------+--------------------------------------+
| 1a74444c-... | 084fb181-... | validating | /home/xfer.../PKG - my title/200KB.1 |
+--------------+--------------+------------+--------------------------------------+
```

```bash
<%=cmd%> node central file update --validator=<%=cmd%> --data=@json:'{"files":[{"session_uuid": "1a74444c-...","file_id": "084fb181-...","status": "completed"}]}'
```

```output
updated
```

### Example: SHOD to ATS

Scenario: Access to a **Shares on Demand** (SHOD) server on AWS is provided by a partner.
We need to transfer files from this third party SHOD instance into our Azure BLOB storage.
Simply create an **Aspera Transfer Service** instance, which provides access to the node API.
Then create a configuration for the **SHOD** instance in the configuration file: in section "shares", a configuration named: aws_shod.
Create another configuration for the Azure ATS instance: in section "node", named azure_ats.
Then execute the following command:

```bash
<%=cmd%> node download /share/sourcefile --to-folder=/destination_folder --preset=aws_shod --transfer=node --transfer-info=@preset:azure_ats
```

This will get transfer information from the SHOD instance and tell the Azure ATS instance to download files.

### node file information

When node api is used with an **Access key**, extra information can be retrieved, such as preview.

> **Note:** Display of preview on terminal requires installation of extra gem: `rmagick`

```bash
dnf install -y ImageMagick-devel
gem install rmagick rainbow
```

For example it is possible to display the preview of a file, if it exists, using:

```bash
<%=cmd%> aoc files thumbnail /preview_samples/Aspera.mpg
```

Using direct node access and an access key , one can do:

```bash
<%=cmd%> node access_key do self thumbnail /preview_samples/Aspera.mpg
```

> **Note:** To specify the file by its file id, use the selector syntax: `%id:_file_id_here_`
>
> **Note:** To force textual display of the preview on iTerm, prefix command with: `env -u TERM_PROGRAM -u LC_TERMINAL`

### Create access key

```bash
<%=cmd%> node access_key create @json:'{"id":"myaccesskey","secret":"my_secret_here","storage":{"type":"local","path":"/data/mydir"}}'
```

### Node sample commands

```bash
<%=include_commands_for_plugin('node')%>
```

## <a id="faspex5"></a>Plugin: `faspex5`: IBM Aspera Faspex v5

IBM Aspera's newer self-managed application.

3 authentication methods are supported:

- jwt : general purpose, private-key based authentication
- link : public link authentication
- web : requires authentication with web browser
- boot : use authentication token copied from browser (experimental)

### Faspex 5 JWT authentication

This is the general purpose and **recommended** method to use.

Activation is in two steps:

- The admninistrator must create an API client in Faspex with JWT support

  This operation is generally done only once:

  - As Admin, Navigate to the web UI: Admin &rarr; Configurations &rarr; API Clients &rarr; Create
  - Give a name, like `<%=cmd%>`
  - Activate JWT
  - There is an option to set a general public key allowing the owner of the private key to impersonate any user. Unless you want to do this, leave this field empty.
  - Click on `Create` Button
  - Take note of Client Id (and Client Secret, but not used in current version)

- The user uses a private key and sets the public key in his faspex 5 profile

  This operation is done by each user using the CLI.

  - As user, click on the user logo, left to the app switcher on top right.
  - Select `Account Settings`
  - on the bottom in the text field: `Public key in PEM format` paste the **public** key corresponding to the private key used by the user.

  **Note:** If you don't have any refer to section [Private Key](#private_key)

Then use these options:

```text
--auth=jwt
--client-id=_client_id_here_
--client-secret=my_secret_here
--username=_username_here_
--private-key=@file:.../path/to/key.pem
```

> **Note:** The `private_key` option must contain the PEM **value** (not file path) of the private key which can be read from a file using the modifier: `@file:`, e.g. `@file:/path/to/key.pem`.

As usual, typically a user will create preset to avoid having to type these options each time.

Example:

```bash
<%=cmd%> conf preset update myf5 --auth=jwt --client-id=_client_id_here_ --client-secret=my_secret_here --username=_username_here_ --private-key=@file:.../path/to/key.pem

<%=cmd%> conf preset set default faspx5 myf5

<%=cmd%> faspex5 user profile show
```

### Faspex 5 web authentication

The admninistrator must create an API client in Faspex for an external web app support:

- As Admin, Navigate to the web UI: Admin &rarr; Configurations &rarr; API Clients &rarr; Create
- Do not Activate JWT
- Set **Redirect URI** to `https://127.0.0.1:8888`
- Click on `Create` Button
- Take note of Client Id (and Client Secret, but not used in current version)

The user will use the following options:

```text
--auth=web
--client-id=_client_id_here_
--client-secret=my_secret_here
--redirect-uri=https://127.0.0.1:8888
```

### Faspex 5 bootstrap authentication

For `boot` method: (will be removed in future)

- As user: Open a Web Browser
- Start developer mode
- Login to Faspex 5
- Find the first API call with `Authorization` header, and copy the value of the token (series of base64 values with dots)

Use this token as password and use `--auth=boot`.

```bash
<%=cmd%> conf preset update f5boot --url=https://localhost/aspera/faspex --auth=boot --password=_token_here_
```

### Faspex 5 sample commands

Most commands are directly REST API calls.
Parameters to commands are carried through option `query`, as extended value, for `list`, or through positional parameter for creation.
One can conveniently use the JSON format with prefix `@json:`.

> **Note:** The API is listed in [Faspex 5 API Reference](https://developer.ibm.com/apis/catalog?search="faspex+5") under **IBM Aspera Faspex API**.

```bash
<%=include_commands_for_plugin('faspex5')%>
```

### Faspex 5: inbox selection

By default, package operations (send, receive, list) are done on the user's inbox.

To select another inbox, use option `box` with one of the following values:

- `inbox` : user's inbox
- `outbox` : user's sent packages
- name of a shared inbox

### Faspex 5: Send a package

The `Hash` creation parameter provided to command `faspex5 packages send` corresponds to the Faspex 5 API: `POST /packages`.

Required fields are `title` and `recipients`.
Example using `@json:` format:

```json
{"title":"some title","recipients":[{"recipient_type":"user","name":"user@example.com"}]}
```

`recipient_type` is one of (Refer to API):

- user
- workgroup
- external_user
- distribution_list
- shared_inbox

<%=tool%> adds some convenience: The API expects the field `recipients` to be an `Array` of `Hash`, each with field `name` and optionally `recipient_type`.
It is also possible to provide an `Array` of `String`, with simply a recipient name.
Then <%=tool%> will lookup existing contacts among all possible types, use it if a single match is found, and set the `name` and `recipient_type` accordingly.
Else an exception is sent.

> **Note:** The lookup is case insensitive and on partial matches.

```json
{"title":"some title","recipients":["user@example.com"]}
```

If the lookup needs to be only on certain types, you can specify the field: `recipient_types` with either a single value or an Array of values (from the list above). e.g. :

```json
{"title":"test title","recipient_types":"user","recipients":["user1@example.com","user2@example.com"]}
```

### Faspex 5:  Send a package with metadata

The interface is the one of the API (Refer to API documentation, or look at request in browser):

```bash
<%=cmd%> faspex5 packages send @json:'{"title":"test title","recipients":["my shared inbox"],"metadata":{"Confidential":"Yes","Drop menu":"Option 1"}}' 'faux:///test1?k1'
```

Basically, add the field `metadata`, with one key per metadata and the value is directly the metadata value.

### Faspex 5: Receive a package

The (numeric) identifier of the package t receive is given as argument to command `faspex5 packages receive`.

> **Note:** option `box` applies.

### Faspex 5: List packages

The following parameters in option `query` are supported:

- `q` : a filter on name (case insensitive, matches if value is contained in name)
- `max` : maximum number of items to retrieve (stop pages when the maximum is passed)
- `pmax` : maximum number of pages to request (stop pages when the maximum is passed)
- `offset` : native api parameter, in general do not use (added by <%=tool%>)
- `limit` : native api parameter, number of items par api call, in general do not use (added by <%=tool%>)

Admin only: If the value `ALL` is provided to option `box`, then all packages are selected.

### Faspex 5: List all shared inboxes

```bash
<%=cmd%> faspex5 admin res shared list --query=@json:'{"all":true}' --fields=id,name
```

Shared inbox members can also be listed, added, removed, and external users can be invited to a shared inbox.

```bash
<%=cmd%> faspex5 admin res shared_inboxes invite '%name:ascli shinbox' john@example.com
```

It is equivalent to:

```bash
<%=cmd%> faspex5 admin res shared_inboxes invite '%name:ascli shinbox' @json:'{"email_address":"john@example.com"}'
```

Other payload parameters are possible in Hash format:

```json
{"description":"blah","prevent_http_upload":true,"custom_link_expiration_policy":false,"invitation_expires_after_upload":false,"set_invitation_link_expiration":false,"invitation_expiration_days":3
```

### Faspex 5: Create Metadata profile

```bash
<%=cmd%> faspex5 admin res metadata_profiles create @json:'{"name":"the profile","default":false,"title":{"max_length":200,"illegal_chars":[]},"note":{"max_length":400,"illegal_chars":[],"enabled":false},"fields":[{"ordering":0,"name":"field1","type":"text_area","require":true,"illegal_chars":[],"max_length":100},{"ordering":1,"name":"fff2","type":"option_list","require":false,"choices":["opt1","opt2"]}]}'
```

### Faspex 5: Create a Shared inbox with specific metadata profile

```bash
<%=cmd%> faspex5 admin res shared create @json:'{"name":"the shared inbox","metadata_profile_id":1}'
```

### Faspex 5: List content in Shared folder and send package from remote source

```bash
<%=cmd%> faspex5 shared_folders list
```

```markdown
+----+----------+---------+-----+
| id | name     | node_id | ... |
+----+----------+---------+-----+
| 3  | partages | 2       | ... |
+----+----------+---------+-----+
```

```bash
<%=cmd%> faspex5 shared_folders br %name:partages /folder
```

```bash
<%=cmd%> faspex5 packages send @json:'{"title":"hello","recipients":[{"name":"_recipient_here_"}]}' --shared-folder=%name:partages /folder/file
```

> **Note:** The shared folder can be identified by its numerical `id` or by name using percent selector: `%<field>:<value>`. e.g. `--shared-folder=3`

### Faspex 5: receive all packages (cargo)

To receive all packages, only once, through persistency of already received packages:

```bash
<%=cmd%> faspex5 packages receive ALL --once-only=yes
```

To initialize, and skip all current package so that next time `ALL` is used, only newer packages are downloaded:

```bash
<%=cmd%> faspex5 packages receive INIT --once-only=yes
```

### Faspex 5: Faspex 4-style postprocessing

<%=tool%> provides command `postprocessing` in plugin `faspex5` to emulate Faspex 4 postprocessing.
It implements Faspex 5 web hooks, and calls a local script with the same environment as Faspex 4.

It is invoked like this:

```bash
<%=cmd%> faspex5 postprocessing @json:'{"url":"http://localhost:8080/processing"}'
```

The following parameters are supported:

| parameter                  | type    | default                | description                                         |
|----------------------------|---------|------------------------|-----------------------------------------------------|
| url                        | string  | <http://localhost:8080>  | Defines the base url on which requests are listened |
| certificate                | hash    | nil                    | used to define certificate if https is used         |
| certificate.key            | string  | nil                    | path to private key file                            |
| certificate.cert           | string  | nil                    | path to certificate                                 |
| certificate.chain          | string  | nil                    | path to intermediary certificates                   |
| processing                 | hash    | nil                    | behavior of post processing                        |
| processing.script_folder   | string  | .                      | prefix added to script path                         |
| processing.fail_on_error   | bool    | false                  | if true and process exit with non zero, then fail   |
| processing.timeout_seconds | integer | 60                     | processing script is killed if takes more time      |

Parameter `url` defines:

- if http or https is used
- the local port
- the "domain", i.e. main path of url

When a request is received the following happens:

- the processor get the path of the url called
- it removes the "domain
- it prepends it with the value of `script_folder`
- it executes the script
- upon success, a success code is returned

In Faspex 5, configure like this:

`Webhook endpoint URI` : `http://localhost:8080/processing/script1.sh`

Then, the postprocessing script executed will be `script1.sh`.

Environment variables at set to the values provided by the web hook which are the same as Faspex 4 postprocessing.

## <a id="faspex"></a>Plugin: `faspex`: IBM Aspera Faspex v4

Notes:

- The command `v4` requires the use of APIv4, refer to the Faspex Admin manual on how to activate.
- For full details on Faspex API, refer to: [Reference on Developer Site](https://developer.ibm.com/apis/catalog/?search=faspex)

### Listing Packages

Command: `faspex package list`

#### Option `box`

By default it looks in box `inbox`, but the following boxes are also supported: `archive` and `sent`, selected with option `box`.

#### Option `recipient`

A user can receive a package because the recipient is:

- the user himself (default)
- the user is member of a dropbox/workgroup: filter using option `recipient` set with value `*<name of dropbox/workgroup>`

#### Option `query`

As inboxes may be large, it is possible to use the following query parameters:

- `count` : (native) number items in one API call (default=0, equivalent to 10)
- `page` : (native) id of page in call (default=0)
- `startIndex` : (native) index of item to start, default=0, oldest index=0
- `max` : maximum number of items
- `pmax` : maximum number of pages

(SQL query is `LIMIT <startIndex>, <count>`)

The API is listed in [Faspex 4 API Reference](https://developer.ibm.com/apis/catalog/?search=faspex) under "Services (API v.3)".

If no parameter `max` or `pmax` is provided, then all packages will be listed in the inbox, which result in paged API calls (using parameter: `count` and `page`).
By default `count` is `0` (`10`), it can be increased to issue less HTTP calls.

#### Example: list packages in dropbox

```bash
<%=cmd%> faspex package list --box=inbox --recipient='*my_dropbox' --query=@json:'{"max":20,"pmax":2,"count":20}'
```

List a maximum of 20 items grouped by pages of 20, with maximum 2 pages in received box (inbox) when received in dropbox `*my_dropbox`.

### Receiving a Package

The command is `package recv`, possible methods are:

- provide a package id with option `id`
- provide a public link with option `link`
- provide a `faspe:` URI with option `link`

```bash
<%=cmd%> faspex package recv 12345
<%=cmd%> faspex package recv --link=faspe://...
```

If the package is in a specific **dropbox**/**workgroup**, add option `recipient` for both the `list` and `recv` commands.

```bash
<%=cmd%> faspex package list --recipient='*dropbox_name'
<%=cmd%> faspex package recv 125 --recipient='*dropbox_name'
```

if `id` is set to `ALL`, then all packages are downloaded, and if option `once_only`is used, then a persistency file is created to keep track of already downloaded packages.

### Sending a Package

The command is `faspex package send`. Package information (title, note, metadata, options) is provided in option `delivery_info`.
The contents of `delivery_info` is directly the contents of the `send` v3 [API of Faspex 4](https://developer.ibm.com/apis/catalog/aspera--aspera-faspex-client-sdk/API%20v.3:%20Send%20Packages), consult it for extended supported parameters.

Example:

```bash
<%=cmd%> faspex package send --delivery-info=@json:'{"title":"my title","recipients":["laurent.martin.aspera@fr.ibm.com"]}' --url=https://faspex.corp.com/aspera/faspex --username=foo --password=bar /tmp/file1 /home/bar/file2
```

If the recipient is a dropbox or workgroup: provide the name of the dropbox or workgroup preceded with `*` in the `recipients` field of the `delivery_info` option:
`"recipients":["*MyDropboxName"]`

Additional optional parameters in `delivery_info`:

- Package Note: : `"note":"note this and that"`
- Package Metadata: `"metadata":{"Meta1":"Val1","Meta2":"Val2"}`

### Email notification on transfer

Like for any transfer, a notification can be sent by email using parameters: `notif_to` and `notif_template` .

Example:

```bash
<%=cmd%> faspex package send --delivery-info=@json:'{"title":"test pkg 1","recipients":["aspera.user1@gmail.com"]}' ~/Documents/Samples/200KB.1 --notif-to=aspera.user1@gmail.com --notif-template=@ruby:'%Q{From: <%='<'%>%=from_name%> <<%='<'%>%=from_email%>>\nTo: <<%='<'%>%=to%>>\nSubject: Package sent: <%='<'%>%=ts["tags"]["aspera"]["faspex"]["metadata"]["_pkg_name"]%> files received\n\nTo user: <%='<'%>%=ts["tags"]["aspera"]["faspex"]["recipients"].first["email"]%>}'
```

In this example the notification template is directly provided on command line. Package information placed in the message are directly taken from the tags in transfer spec. The template can be placed in a file using modifier: `@file:`

### Operation on dropboxes

Example:

```bash
<%=cmd%> faspex v4 dropbox create @json:'{"dropbox":{"e_wg_name":"test1","e_wg_desc":"test1"}}'
<%=cmd%> faspex v4 dropbox list
<%=cmd%> faspex v4 dropbox delete 36
```

### Remote sources

Faspex lacks an API to list the contents of a remote source (available in web UI). To workaround this,
the node API is used, for this it is required to add a section ":storage" that links
a storage name to a node config and sub path.

Example:

```yaml
my_faspex_conf:
  url: https://10.25.0.3/aspera/faspex
  username: admin
  password: MyUserPassword
  storage:
    my_storage:
      node: "@preset:my_faspex_node"
      path: /mydir
my_faspex_node:
  url: https://10.25.0.3:9092
  username: node_faspex
  password: MyNodePassword
```

In this example, a faspex storage named `my_storage` exists in Faspex, and is located
under the docroot in `/mydir` (this must be the same as configured in Faspex).
The node configuration name is "my_faspex_node" here.

Note: the v4 API provides an API for nodes and shares.

### Automated package download (cargo)

It is possible to tell <%=tool%> to download newly received packages, much like the official
cargo client, or drive. Refer to the [same section](#aoccargo) in the Aspera on Cloud plugin:

```bash
<%=cmd%> faspex packages recv ALL --once-only=yes --lock-port=12345
```

### Faspex 4 sample commands

```bash
<%=include_commands_for_plugin('faspex')%>
```

## <a id="shares"></a>Plugin: `shares`: IBM Aspera Shares v1

Aspera Shares supports the "node API" for the file transfer part.

### Shares 1 sample commands

```bash
<%=include_commands_for_plugin('shares')%>
```

## <a id="console"></a>Plugin: `console`: IBM Aspera Console

### Console sample commands

```bash
<%=include_commands_for_plugin('console')%>
```

## <a id="orchestrator"></a>Plugin: `orchestrator`:IBM Aspera Orchestrator

### Orchestrator sample commands

```bash
<%=include_commands_for_plugin('orchestrator')%>
```

## <a id="cos"></a>Plugin: `cos`: IBM Cloud Object Storage

The IBM Cloud Object Storage provides the possibility to execute transfers using FASP.
It uses the same transfer service as Aspera on Cloud, called Aspera Transfer Service (ATS).
Available ATS regions: [https://status.aspera.io](https://status.aspera.io)

There are two possibilities to provide credentials.
If you already have the endpoint, apikey and CRN, use the first method.
If you don't have credentials but have access to the IBM Cloud console, then use the second method.

### Using endpoint, apikey and Resource Instance ID (CRN)

If you have those parameters already, then following options shall be provided:

- `bucket` bucket name
- `endpoint` storage endpoint url, e.g. `https://s3.hkg02.cloud-object-storage.appdomain.cloud`
- `apikey` API Key
- `crn` resource instance id

For example, let us create a default configuration:

```bash
<%=cmd%> conf preset update mycos --bucket=mybucket --endpoint=https://s3.us-east.cloud-object-storage.appdomain.cloud --apikey=abcdefgh --crn=crn:v1:bluemix:public:iam-identity::a/xxxxxxx
<%=cmd%> conf preset set default cos mycos
```

Then, jump to the transfer example.

### Using service credential file

If you are the COS administrator and don't have yet the credential:
Service credentials are directly created using the IBM cloud Console (web UI).
Navigate to:

- &rarr; Navigation Menu
- &rarr; [Resource List](https://cloud.ibm.com/resources)
- &rarr; [Storage](https://cloud.ibm.com/objectstorage)
- &rarr; Select your storage instance
- &rarr; Service Credentials
- &rarr; New credentials (Leave default role: Writer, no special options)
- &rarr; Copy to clipboard

Then save the copied value to a file, e.g. : `$HOME/cos_service_creds.json`

or using the IBM Cloud CLI:

```bash
ibmcloud resource service-keys
ibmcloud resource service-key _service_key_name_here_ --output JSON|jq '.[0].credentials'>$HOME/service_creds.json
```

(if you don't have `jq` installed, extract the structure as follows)

It consists in the following structure:

```json
{
  "apikey": "my_api_key_here",
  "cos_hmac_keys": {
    "access_key_id": "my_access_key_here",
    "secret_access_key": "my_secret_here"
  },
  "endpoints": "https://control.cloud-object-storage.cloud.ibm.com/v2/endpoints",
  "iam_apikey_description": "my_description_here",
  "iam_apikey_name": "my_key_name_here",
  "iam_role_crn": "crn:v1:bluemix:public:iam::::serviceRole:Writer",
  "iam_serviceid_crn": "crn:v1:bluemix:public:iam-identity::a/xxxxxxx.....",
  "resource_instance_id": "crn:v1:bluemix:public:cloud-object-storage:global:a/xxxxxxx....."
}
```

The field `resource_instance_id` is for option `crn`

The field `apikey` is for option `apikey`

(If needed: endpoints for regions can be found by querying the `endpoints` URL.)

The required options for this method are:

- `bucket` bucket name
- `region` bucket region, e.g. eu-de
- `service_credentials` see below

For example, let us create a default configuration:

```bash
<%=cmd%> conf preset update mycos --bucket=laurent --service-credentials=@val:@json:@file:~/service_creds.json --region=us-south
<%=cmd%> conf preset set default cos mycos
```

### Operations, transfers

Let's assume you created a default configuration from once of the two previous steps (else specify the access options on command lines).

A subset of `node` plugin operations are supported, basically node API:

```bash
<%=cmd%> cos node info
<%=cmd%> cos node upload 'faux:///sample1G?1g'
```

Note: we generate a dummy file `sample1G` of size 2GB using the `faux` PVCL (man `ascp` and section above), but you can of course send a real file by specifying a real file instead.

### COS sample commands

```bash
<%=include_commands_for_plugin('cos')%>
```

## <a id="async"></a>Plugin: `async`: IBM Aspera Sync

A basic plugin to start an `async` using <%=tool%>.
The main advantage over bare `async` command line is the possibility to use a configuration file, using standard options of <%=tool%>.

The `sync` command is also made available through the `server sync`, `aoc files sync` and `node sync` commands.
In this case, some of the `sync` parameters are filled by the related plugin using transfer spec parameters (including token).

> **Note:** All `sync` commands require an `async` enabled license and availability of the `async` executable (and `asyncadmin`).

Two JSON syntax are supported for option `sync_info`.

### async native JSON

It is the same payload as specified on the `async` option `--conf` or in the latest node API.
This is the preferred syntax and allows a single session definition.
But there is no progress output nor error messages.

Documentation on Async node API can be found on [IBM Developer Portal](https://developer.ibm.com/apis/catalog?search=%22aspera%20sync%20api%22).

### async options as JSON

This is specific to <%=tool%>.
It is based on a JSON representation of `async` command line options.
It allows definition of multiple sync sessions in a single command, although usually only one sync session is defined.

### Sync sample commands

```bash
<%=include_commands_for_plugin('sync')%>
```

## <a id="preview"></a>Plugin: `preview`: Preview generator for AoC

The `preview` generates thumbnails (office, images, video) and video previews on storage for use primarily in the Aspera on Cloud application.
It uses the **node API** of Aspera HSTS and requires use of Access Keys and it's **storage root**.
Several parameters can be used to tune several aspects:

- Methods for detection of new files needing generation
- Methods for generation of video preview
- Parameters for video handling

### Aspera Server configuration

Specify the previews folder as shown in:

<https://ibmaspera.com/help/admin/organization/installing_the_preview_maker>

By default, the `preview` plugin expects previews to be generated in a folder named `previews` located in the storage root. On the transfer server execute:

```bash
PATH=/opt/aspera/bin:$PATH

asconfigurator -x "server;preview_dir,previews"
asnodeadmin --reload
```

Note: the configuration `preview_dir` is *relative* to the storage root, no need leading or trailing `/`. In general just set the value to `previews`

If another folder is configured on the HSTS, then specify it to <%=tool%> using the option `previews_folder`.

The HSTS node API limits any preview file to a parameter: `max_request_file_create_size_kb` (1 KB is 1024 bytes).
This size is internally capped to `1<<24` Bytes (16777216) , i.e. 16384 KBytes.

To change this parameter in `aspera.conf`, use `asconfigurator`. To display the value, use `asuserdata`:

```bash
asuserdata -a | grep max_request_file_create_size_kb

  max_request_file_create_size_kb: "1024"

asconfigurator -x "server; max_request_file_create_size_kb,16384"
```

If you use a value different than 16777216, then specify it using option `max_size`.

Note: the HSTS parameter (max_request_file_create_size_kb) is in *kiloBytes* while the generator parameter is in *Bytes* (factor of 1024).

### <a id="prev_ext"></a>External tools: Linux

The tool requires the following external tools available in the `PATH`:

- ImageMagick : `convert` `composite`
- OptiPNG : `optipng`
- FFmpeg : `ffmpeg` `ffprobe`
- Libreoffice : `libreoffice`

Here shown on Redhat/CentOS.

Other OSes should work as well, but are note tested.

To check if all tools are found properly, execute:

```bash
<%=cmd%> preview check
```

#### Image: ImageMagick and optipng

```bash
dnf install -y ImageMagick optipng
```

You may also install `ghostscript` which adds fonts to ImageMagick.
Available fonts, used to generate png for text, can be listed with `magick identify -list font`.
Prefer ImageMagick version >=7.

#### Video: FFmpeg

The easiest method is to download and install the latest released version of ffmpeg with static libraries from [https://johnvansickle.com/ffmpeg/](https://johnvansickle.com/ffmpeg/)

```bash
curl -s https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz|(mkdir -p /opt && cd /opt && rm -f ffmpeg /usr/bin/{ffmpeg,ffprobe} && rm -fr ffmpeg-*-amd64-static && tar xJvf - && ln -s ffmpeg-* ffmpeg && ln -s /opt/ffmpeg/{ffmpeg,ffprobe} /usr/bin)
```

#### Office: Unoconv and Libreoffice

If you don't want to have preview for office documents or if it is too complex you can skip office document preview generation by using option: `--skip-types=office`

The generation of preview in based on the use of `unoconv` and `libreoffice`

- CentOS 8

```bash
dnf install unoconv
```

- Amazon Linux

```bash
amazon-linux-extras enable libreoffice
yum clean metadata
yum install libreoffice-core libreoffice-calc libreoffice-opensymbol-fonts libreoffice-ure libreoffice-writer libreoffice-pyuno libreoffice-impress
wget https://raw.githubusercontent.com/unoconv/unoconv/master/unoconv
mv unoconv /usr/bin
chmod a+x /usr/bin/unoconv
```

### Configuration

The preview generator should be executed as a non-user.
When using object storage, any user can be used, but when using local storage it is usually better to use the user `xfer`, as uploaded files are under this identity: this ensures proper access rights. (we will assume this)

Like any <%=tool%> commands, parameters can be passed on command line or using a configuration <%=prst%>.
The configuration file must be created with the same user used to run so that it is properly used on runtime.

The `xfer` user has a special protected shell: `aspshell`, so in order to update the configuration, and when changing identity, specify an alternate shell.
E.g.:

```bash
su -s /bin/bash - xfer

<%=cmd%> config preset update mypreviewconf --url=https://localhost:9092 --username=my_access_key --password=my_secret --skip-types=office --lock-port=12346

<%=cmd%> config preset set default preview mypreviewconf
```

Here we assume that Office file generation is disabled, else remove this option.
`lock_port` prevents concurrent execution of generation when using a scheduler.

One can check if the access key is well configured using:

```bash
<%=cmd%> -Ppreviewconf node browse /
```

This shall list the contents of the storage root of the access key.

### Options for generated files

When generating preview files, some options are provided by default.
Some values for the options can be modified on command line.
For video preview, the whole set of options can be overridden with option `reencode_ffmpeg`: it is a Hash with two keys: `in` and `out`, each is an array of strings with the native options to `ffmpeg`.

### Execution

The tool intentionally supports only a **one shot** mode (no infinite loop) in order to avoid having a hanging process or using too many resources (calling REST api too quickly during the scan or event method).
It needs to be run on a regular basis to create or update preview files.
For that use your best reliable scheduler, see [Scheduler](#scheduler).

Typically, for **Access key** access, the system/transfer is `xfer`. So, in order to be consistent have generate the appropriate access rights, the generation process should be run as user `xfer`.

Lets do a one shot test, using the configuration previously created:

```bash
su -s /bin/bash - xfer

<%=cmd%> preview scan --overwrite=always
```

When the preview generator is first executed it will create a file: `.aspera_access_key`
in the previews folder which contains the access key used.
On subsequent run it reads this file and check that previews are generated for the same access key, else it fails. This is to prevent clash of different access keys using the same root.

### Configuration for Execution in scheduler

Details are provided in section [Scheduler](#scheduler).

Shorter commands can be specified if a configuration preset was created as shown previously.

For example the timeout value can be differentiated depending on the option: event versus scan:

```bash
case "$*" in *trev*) tmout=10m ;; *) tmout=30m ;; esac
```

### Candidate detection for creation or update (or deletion)

The tool generates preview files using those commands:

- `trevents` : only recently uploaded files will be tested (transfer events)
- `events` : only recently uploaded files will be tested (file events: not working)
- `scan` : recursively scan all files under the access key&apos;s "storage root"
- `test` : test using a local file

Once candidate are selected, once candidates are selected,
a preview is always generated if it does not exist already,
else if a preview already exist, it will be generated
using one of three values for the `overwrite` option:

- `always` : preview is always generated, even if it already exists and is newer than original
- `never` : preview is generated only if it does not exist already
- `mtime` : preview is generated only if the original file is newer than the existing

Deletion of preview for deleted source files: not implemented yet (TODO).

If the `scan` or `events` detection method is used, then the option : `skip_folders` can be used to skip some folders. It expects a list of path relative to the storage root (docroot) starting with slash, use the `@json:` notation, example:

```bash
<%=cmd%> preview scan --skip-folders=@json:'["/not_here"]'
```

The option `folder_reset_cache` forces the node service to refresh folder contents using various methods.

When scanning the option `query` has the same behavior as for the `node find` command.

For instance to filter out files beginning with `._` do:

```bash
--query='exec:!f["name"].start_with?("._") or f["name"].eql?(".DS_Store")'
```

### Preview File types

Two types of preview can be generated:

- `png`: thumbnail
- `mp4`: video preview (only for video)

Use option `skip_format` to skip generation of a format.

### Supported input Files types

The preview generator supports rendering of those file categories:

- image
- pdf
- plaintext
- office
- video

To avoid generation for some categories, specify a list using option `skip_types`.

Each category has a specific rendering method to produce the png thumbnail.

The mp4 video preview file is only for category `video`

File type is primarily based on file extension detected by the node API and translated info a mime type returned by the node API.

### mimemagic

By default, the Mime type used for conversion is the one returned by the node API, based on file name extension.

It is also possible to detect the mime type using option `mimemagic`.
To use it, set option `mimemagic` to `yes`: `--mimemagic=yes`.

This requires to manually install the mimemagic gem: `gem install mimemagic`.

In this case the `preview` command will first analyze the file content using mimemagic, and if no match, will try by extension.

If the `mimemagic` gem complains about missing mime info file:

- any OS:

  - Examine the error message
  - Download the file: [freedesktop.org.xml.in](https://gitlab.freedesktop.org/xdg/shared-mime-info/-/raw/master/data/freedesktop.org.xml.in)
  - move and rename this file to one of the locations expected by mimemagic as specified in the error message

- Windows:

  - Download the file: [freedesktop.org.xml.in](https://gitlab.freedesktop.org/xdg/shared-mime-info/-/raw/master/data/freedesktop.org.xml.in)
  - Place this file in the root of Ruby (or elsewhere): `C:\RubyVV-x64\freedesktop.org.xml.in`
  - Set a global variable using `SystemPropertiesAdvanced.exe` or using `cmd` (replace `VV` with version) to the exact path of this file:

  ```cmd
  SETX FREEDESKTOP_MIME_TYPES_PATH C:\RubyVV-x64\freedesktop.org.xml.in
  ```

  - Close the `cmd` and restart a new one if needed to get refreshed env vars

- Linux RHEL 8+:

```bash
dnf install shared-mime-info
```

- macOS:

```bash
brew install shared-mime-info
```

### Generation: Read source files and write preview

Standard open source tools are used to create thumbnails and video previews.
Those tools require that original files are accessible in the local file system and also write generated files on the local file system.
The tool provides 2 ways to read and write files with the option: `file_access`

If the preview generator is run on a system that has direct access to the file system, then the value `local` can be used. In this case, no transfer happen, source files are directly read from the storage, and preview files
are directly written to the storage.

If the preview generator does not have access to files on the file system (it is remote, no mount, or is an object storage), then the original file is first downloaded, then the result is uploaded, use method `remote`.

### Preview sample commands

```bash
<%=include_commands_for_plugin('preview')%>
```

## SMTP for email notifications

<%=tool%> can send email, for that setup SMTP configuration. This is done with option `smtp`.

The `smtp` option is a hash table (extended value) with the following fields:

<!-- markdownlint-disable MD034 -->
| field        | default             | example                    | description                      |
|--------------|---------------------|----------------------------|----------------------------------|
| `server`     | -                   | smtp.gmail.com             | SMTP server address              |
| `tls`        | true                | true                       | enable STARTTLS (port 587)       |
| `ssl`        | false               | false                      | enable TLS (port 465)            |
| `port`       | 587 or 465 or 25    | 587                        | port for service                 |
| `domain`     | domain of server    | gmail.com                  | email domain of user             |
| `username`   | -                   | john@example.com           | user to authenticate on SMTP server, leave empty for open auth. |
| `password`   | -                   | my_password_here           | password for above username      |
| `from_email` | username if defined | johnny@example.com         | address used if receiver replies |
| `from_name`  | same as email       | John Wayne                 | display name of sender           |
<!-- markdownlint-enable MD034 -->

### Example of configuration

```bash
<%=cmd%> config preset set smtp_google server smtp.google.com
<%=cmd%> config preset set smtp_google username john@gmail.com
<%=cmd%> config preset set smtp_google password my_password_here
```

or

```bash
<%=cmd%> config preset init smtp_google @json:'{"server":"smtp.google.com","username":"john@gmail.com","password":"my_password_here"}'
```

or

```bash
<%=cmd%> config preset update smtp_google --server=smtp.google.com --username=john@gmail.com --password=my_password_here
```

Set this configuration as global default, for instance:

```bash
<%=cmd%> config preset set cli_default smtp @val:@preset:smtp_google
<%=cmd%> config preset set default config cli_default
```

### Email templates

Sent emails are built using a template that uses the [ERB](https://www.tutorialspoint.com/ruby/eruby.htm) syntax.

The template is the full SMTP message, including headers.

The following variables are defined by default:

- `from_name`
- `from_email`
- `to`

Other variables are defined depending on context.

### Test

Check settings with `smtp_settings` command. Send test email with `email_test`.

```bash
<%=cmd%> config --smtp=@preset:smtp_google smtp
<%=cmd%> config --smtp=@preset:smtp_google email --notif-to=sample.dest@example.com
```

### Notifications for transfer status

An e-mail notification can be sent upon transfer success and failure (one email per transfer job, one job being possibly multi session, and possibly after retry).

To activate, use option `notif_to`.

A default e-mail template is used, but it can be overridden with option `notif_template`.

The environment provided contains the following additional variables:

- subject
- body
- global_transfer_status
- ts

Example of template:

```text
From: <%='<'%>%=from_name%> <<%='<'%>%=from_email%>>
To: <<%='<'%>%=to%>>
Subject: <%='<'%>%=subject%>

Transfer is: <%='<'%>%=global_transfer_status%>
```

## Tool: `asession`

This gem comes with a second executable tool providing a simplified standardized interface to start a FASP session: `asession`.

It aims at simplifying the startup of a FASP session from a programmatic stand point as formatting a <%=trspec%> is:

- common to Aspera Node API (HTTP POST /ops/transfer)
- common to Aspera Connect API (browser javascript startTransfer)
- easy to generate by using any third party language specific JSON library

Hopefully, IBM integrates this directly in `ascp`, and this tool is made redundant.

This makes it easy to integrate with any language provided that one can spawn a sub process, write to its STDIN, read from STDOUT, generate and parse JSON.

The tool expect one single argument: a <%=trspec%>.

If no argument is provided, it assumes a value of: `@json:@stdin:`, i.e. a JSON formatted <%=trspec%> on stdin.

> **Note:** If JSON is the format, specify `@json:` to tell <%=tool%> to decode the hash using JSON syntax.

During execution, it generates all low level events, one per line, in JSON format on stdout.

There are special "extended" <%=trspec%> parameters supported by `asession`:

- `EX_loglevel` to change log level of the tool
- `EX_file_list_folder` to set the folder used to store (exclusively, because of garbage collection) generated file lists. By default it is `[system tmp folder]/[username]_asession_filelists`

> **Note:** In addition, many "EX_" <%=trspec%> parameters are supported for the [`direct`](#agt_direct) transfer agent (used by `asession`), refer to section <%=trspec%>.

### Comparison of interfaces

| feature/tool | asession | `ascp` | FaspManager | Transfer SDK |
|--------------|----------|--------|-------------|--------------|
| language integration | any | any | C/C++<br/>C#/.net<br/>Go<br/>Python<br/>java<br/> | many |
| required additional components to `ascp` | Ruby<br/>Aspera | - | library<br/>(headers) | daemon |
| startup | JSON on stdin<br/>(standard APIs:<br/>JSON.generate<br/>Process.spawn) | command line arguments | API | daemon |
| events | JSON on stdout | none by default<br/>or need to open management port<br/>and proprietary text syntax | callback | callback |
| platforms | any with Ruby and `ascp` | any with `ascp` (and SDK if compiled) | any with `ascp` | any with `ascp` and transfer daemon |

### Simple session

Create a file `session.json` with:

```json
{"remote_host":"demo.asperasoft.com","remote_user":"asperaweb","ssh_port":33001,"remote_password":"my_password_here","direction":"receive","destination_root":"./test.dir","paths":[{"source":"/aspera-test-dir-tiny/200KB.1"}],"resume_level":"none"}
````

Then start the session:

```bash
asession < session.json
```

### Asynchronous commands and Persistent session

`asession` also supports asynchronous commands (on the management port). Instead of the traditional text protocol as described in `ascp` manual, the format for commands is: one single line per command, formatted in JSON, where parameters shall be "snake" style, for example: `LongParameter` -&gt; `long_parameter`

This is particularly useful for a persistent session ( with the <%=trspec%> parameter: `"keepalive":true` )

```json
asession
{"remote_host":"demo.asperasoft.com","ssh_port":33001,"remote_user":"asperaweb","remote_password":"my_password_here","direction":"receive","destination_root":".","keepalive":true,"resume_level":"none"}
{"type":"START","source":"/aspera-test-dir-tiny/200KB.2"}
{"type":"DONE"}
```

(events from FASP are not shown in above example. They would appear after each command)

### Example of language wrapper

Nodejs: [https://www.npmjs.com/package/aspera](https://www.npmjs.com/package/aspera)

### Help

```bash
asession -h
<%=include_asession%>
```

## Hot folder

### Requirements

<%=tool%> maybe used as a simple hot folder engine.
A hot folder being defined as a tool that:

- locally (or remotely) detects new files in a top folder
- send detected files to a remote (respectively, local) repository
- only sends new files, do not re-send already sent files
- optionally: sends only files that are not still "growing"
- optionally: after transfer of files, deletes or moves to an archive

In addition: the detection should be made "continuously" or on specific time/date.

### Setup procedure

The general idea is to rely on :

- existing `ascp` features for detection and transfer
- take advantage of <%=tool%> configuration capabilities and server side knowledge
- the OS scheduler for reliability and continuous operation

#### `ascp` features

Interesting `ascp` features are found in its arguments: (see `ascp` manual):

- `ascp` already takes care of sending only **new** files: option `-k 1,2,3` (`resume_policy`)
- `ascp` has some options to remove or move files after transfer: `--remove-after-transfer`, `--move-after-transfer`, `--remove-empty-directories` (`remove_after_transfer`, `move_after_transfer`, `remove_empty_directories`)
- `ascp` has an option to send only files not modified since the last X seconds: `--exclude-newer-than`, `--exclude-older-than` (`exclude_newer_than`,`exclude_older_than`)
- `--src-base` (`src_base`) if top level folder name shall not be created on destination

> **Note:** <%=tool%> takes transfer parameters exclusively as a <%=trspec%>, with `ts` option.
>
> **Note:** Most, but not all, native `ascp` arguments are available as standard <%=trspec%> parameters.
>
> **Note:** Only for the [`direct`](#agt_direct) transfer agent (not others, like connect or node), native `ascp` arguments can be provided with parameter `ascp_args` of option `transfer_info` .

#### server side and configuration

Virtually any transfer on a "repository" on a regular basis might emulate a hot folder.

> **Note:** file detection is not based on events (inotify, etc...), but on a simple folder scan on source side.
>
> **Note:** parameters may be saved in a <%=prst%> and used with `-P`.

#### Scheduling

Once <%=tool%> parameters are defined, run the command using the OS native scheduler, e.g. every minutes, or 5 minutes, etc...
Refer to section [Scheduler](#scheduler). (on use of option `lock_port`)

### Example: upload hot folder

```bash
<%=cmd%> server upload source_hot --to-folder=/Upload/target_hot --lock-port=12345 --ts=@json:'{"remove_after_transfer":true,"remove_empty_directories":true,"exclude_newer_than:-8,"src_base":"source_hot"}'
```

The local folder (here, relative path: `source_hot`) is sent (upload) to an aspera server.
Source files are deleted after transfer.
Growing files will be sent only once they don't grow anymore (based on an 8-second cool-off period).
If a transfer takes more than the execution period, then the subsequent execution is skipped (`lock_port`) preventing multiple concurrent runs.

### Example: unidirectional synchronization (upload) to server

```bash
<%=cmd%> server upload source_sync --to-folder=/Upload/target_sync --lock-port=12345 --ts=@json:'{"resume_policy":"sparse_csum","exclude_newer_than":-8,"src_base":"source_sync"}'
```

This can also be used with other folder-based applications: Aspera on Cloud, Shares, Node:

### Example: unidirectional synchronization (download) from Aspera on Cloud Files

```bash
<%=cmd%> aoc files download . --to-folder=. --lock-port=12345 --progress=none --display=data \
--ts=@json:'{"resume_policy":"sparse_csum","target_rate_kbps":50000,"exclude_newer_than":-8,"delete_before_transfer":true}'
```

> **Note:** option `delete_before_transfer` will delete files locally, if they are not present on remote side.
>
> **Note:** options `progress` and `display` limit output for headless operation (e.g. cron job)

## Health check and Nagios

Most plugin provide a `health` command that will check the health status of the application. Example:

```bash
<%=cmd%> console health
```

```output
+--------+-------------+------------+
| status | component   | message    |
+--------+-------------+------------+
| ok     | console api | accessible |
+--------+-------------+------------+
```

Typically, the health check uses the REST API of the application with the following exception: the `server` plugin allows checking health by:

- issuing a transfer to the server
- checking web app status with `asctl all:status`
- checking daemons process status

<%=tool%> can be called by Nagios to check the health status of an Aspera server. The output can be made compatible to Nagios with option `--format=nagios` :

```bash
<%=cmd%> server health transfer --to-folder=/Upload --format=nagios --progress=none
```

```output
OK - [transfer:ok]
```

```bash
<%=cmd%> server health asctl status --cmd_prefix='sudo ' --format=nagios
```

```output
OK - [NP:running, MySQL:running, Mongrels:running, Background:running, DS:running, DB:running, Email:running, Apache:running]
```

## Ruby Module: `Aspera`

Main components:

- `Aspera` generic classes for REST and OAuth
- `Aspera::Fasp`: starting and monitoring transfers. It can be considered as a FASPManager class for Ruby.
- `Aspera::Cli`: <%=tool%>.

Working examples can be found in repo: <https://github.com/laurent-martin/aspera-api-examples> in Ruby examples.

## Changes (Release notes)

See [CHANGELOG.md](CHANGELOG.md)

## History

When I joined Aspera, there was only one CLI: `ascp`, which is the implementation of the FASP protocol, but there was no CLI to access the various existing products (Server, Faspex, Shares).
Once, Serban (founder) provided a shell script able to create a Faspex Package using Faspex REST API.
Since all products relate to file transfers using FASP (`ascp`), I thought it would be interesting to have a unified CLI for transfers using FASP.
Also, because there was already the `ascp` tool, I thought of an extended tool : `eascp.pl` which was accepting all `ascp` options for transfer but was also able to transfer to Faspex and Shares (destination was a kind of URI for the applications).

There were a few pitfalls:

- The tool was written in the aging `perl` language while most Aspera web application products (but the Transfer Server) are written in `ruby`.
- The tool was only for transfers, but not able to call other products APIs

So, it evolved into <%=tool%>:

- portable: works on platforms supporting `ruby` (and `ascp`)
- easy to install with the `gem` utility
- supports transfers with multiple [Transfer Agents](#agents), that&apos;s why transfer parameters moved from `ascp` command line to <%=trspec%> (more reliable , more standard)
- `ruby` is consistent with other Aspera products

Over the time, a supported command line tool `aspera` was developed in C++, it was later on deprecated.
It had the advantage of being relatively easy to installed, as a single executable (well, still using `ascp`), but it was too limited IMHO, and lacked a lot of the features of this CLI.

Enjoy a coffee on me:

```bash
<%=cmd%> conf coffee
<%=cmd%> conf coffee --ui=text
```

## Common problems

### Error: "Remote host is not who we expected"

Cause: `ascp` >= 4.x checks fingerprint of highest server host key, including ECDSA. `ascp` < 4.0 (3.9.6 and earlier) support only to RSA level (and ignore ECDSA presented by server). `aspera.conf` supports a single fingerprint.

Workaround on client side: To ignore the certificate (SSH fingerprint) add option on client side (this option can also be added permanently to the config file):

```bash
--ts=@json:'{"sshfp":null}'
```

Workaround on server side: Either remove the fingerprint from `aspera.conf`, or keep only RSA host keys in `sshd_config`.

References: ES-1944 in release notes of 4.1 and to [HSTS admin manual section "Configuring Transfer Server Authentication With a Host-Key Fingerprint"](https://www.ibm.com/docs/en/ahts/4.2?topic=upgrades-configuring-ssh-server).

### Error "can't find header files for ruby"

Some Ruby gems dependencies require compilation of native parts (C).
This also requires Ruby header files.
If Ruby was installed as a Linux Packages, then also install Ruby development package:
`ruby-dev` ir `ruby-devel`, depending on distribution.

### ED255519 key not supported

ED25519 keys are deactivated since version 0.9.24 so this type of key will just be ignored.

Without this deactivation, if such key was present the following error was generated:

```output
OpenSSH keys only supported if ED25519 is available
```

Which meant that you do not have Ruby support for ED25519 SSH keys.
You may either install the suggested Gems, or remove your ed25519 key from your `.ssh` folder to solve the issue.
