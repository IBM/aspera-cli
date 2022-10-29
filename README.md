# Command Line Interface for IBM Aspera products

[comment1]: # (Do not edit this README.md, edit docs/README.erb.md, for details, read docs/README.md)

Version : 4.10.0

Laurent/2016-2022

This gem provides the `ascli` Command Line Interface to IBM Aspera software.

`ascli` is a also great tool to learn Aspera APIs.

Ruby Gem: [https://rubygems.org/gems/aspera-cli](https://rubygems.org/gems/aspera-cli)

Ruby Doc: [https://www.rubydoc.info/gems/aspera-cli](https://www.rubydoc.info/gems/aspera-cli)

Minimum required Ruby version: >= 2.4. Deprecation notice: the minimum will be 2.5 in a future version.

[Aspera APIs on IBM developer](https://developer.ibm.com/?size=30&q=aspera&DWContentType[0]=APIs)
[Link 2](https://developer.ibm.com/apis/catalog/?search=aspera)

Release notes: see [CHANGELOG.md](CHANGELOG.md)

[![CII Best Practices](https://bestpractices.coreinfrastructure.org/projects/5861/badge)](https://bestpractices.coreinfrastructure.org/projects/5861)

## BUGS, FEATURES, CONTRIBUTION

Refer to [BUGS.md](BUGS.md) and [CONTRIBUTING.md](CONTRIBUTING.md).

One can also [create one's own plugin](#createownplugin).

## <a id="when_to_use"></a>When to use and when not to use

`ascli` is designed to be used as a command line tool to:

* execute commands on Aspera products
* transfer to/from Aspera products

So it is designed for:

* Interactive operations on a text terminal (typically, VT100 compatible)
* Batch operations in (shell) scripts (e.g. cron job)

`ascli` can be seen as a command line tool integrating:

* a configuration file (config.yaml)
* advanced command line options
* cURL (for REST calls)
* Aspera transfer (ascp)

One might be tempted to use it as an integration element, e.g. by building a command line programmatically, and then executing it. It is generally not a good idea.
For such integration cases, e.g. performing operations and transfer to aspera products, it is preferred to use [Aspera APIs](https://ibm.biz/aspera_api):

* Product APIs (REST) : e.g. AoC, Faspex, node
* Transfer SDK : with gRPC interface and language stubs (C, C++, Python, .NET/C#, java, ruby, etc...)

Using APIs (application REST API and transfer SDK) will prove to be easier to develop and maintain.

For scripting and ad'hoc command line operations, `ascli` is perfect.

## Notations, Shell, Examples

In examples, command line operations are shown using a shell such: `bash` or `zsh`.

Command line parameters in examples beginning with `my_`, like `my_param_value` are user-provided value and not fixed value commands.


## Quick Start

This section guides you from installation, first use and advanced use.

First, follow the section: [Installation](#installation) (Ruby, Gem, FASP) to start using `ascli`.

Once the gem is installed, `ascli` shall be accessible:

```bash
ascli --version
```

```bash
4.10.0
```

### First use

Once installation is completed, you can proceed to the first use with a demo server:

If you want to test with Aspera on Cloud, jump to section: [Wizard](#aocwizard)

To test with Aspera demo transfer server, setup the environment and then test:

```bash
ascli config initdemo
```

```bash
ascli server browse /
```

```output
:............:...........:......:........:...........................:.......................:
:   zmode    :   zuid    : zgid :  size  :           mtime           :         name          :
:............:...........:......:........:...........................:.......................:
: dr-xr-xr-x : asperaweb : fasp : 4096   : 2014-04-10 19:44:05 +0200 : aspera-test-dir-tiny  :
: drwxr-xr-x : asperaweb : fasp : 176128 : 2018-03-15 12:20:10 +0100 : Upload                :
: dr-xr-xr-x : asperaweb : fasp : 4096   : 2015-04-01 00:37:22 +0200 : aspera-test-dir-small :
: dr-xr-xr-x : asperaweb : fasp : 4096   : 2018-05-04 14:26:55 +0200 : aspera-test-dir-large :
:............:...........:......:........:...........................:.......................:
```

If you want to use `ascli` with another server, and in order to make further calls more convenient, it is advised to define a [option preset](#lprt) for the server's authentication options. The following example will:

* create a [option preset](#lprt)
* define it as default for `server` plugin
* list files in a folder
* download a file

```bash
ascli config preset update myserver --url=ssh://demo.asperasoft.com:33001 --username=asperaweb --password=_pass_here_
```

```output
updated: myserver
```

```bash
ascli config preset set default server myserver
```

```output
updated: default&rarr;server to myserver
```

```bash
ascli server browse /aspera-test-dir-large
```

```output
:............:...........:......:..............:...........................:............................:
:   zmode    :   zuid    : zgid :     size     :           mtime           :            name            :
:............:...........:......:..............:...........................:............................:
: -rw-rw-rw- : asperaweb : fasp : 10133504     : 2018-05-04 14:16:24 +0200 : ctl_female_2.fastq.partial :
: -rw-r--r-- : asperaweb : fasp : 209715200    : 2014-04-10 19:49:27 +0200 : 200MB                      :
: -rw-r--r-- : asperaweb : fasp : 524288000    : 2014-04-10 19:44:15 +0200 : 500MB                      :
: -rw-r--r-- : asperaweb : fasp : 5368709120   : 2014-04-10 19:45:52 +0200 : 5GB                        :
: -rw-r--r-- : asperaweb : fasp : 500000000000 : 2017-06-14 20:09:57 +0200 : 500GB                      :
: -rw-rw-rw- : asperaweb : fasp : 13606912     : 2018-05-04 14:20:21 +0200 : ctl_male_2.fastq.partial   :
: -rw-rw-rw- : asperaweb : fasp : 76           : 2018-05-04 14:13:18 +0200 : ctl_female_2.fastq.haspx   :
: -rw-rw-rw- : asperaweb : fasp : 647348       : 2018-05-04 14:26:39 +0200 : ctl_female_2.gz            :
: -rw-rw-rw- : asperaweb : fasp : 74           : 2018-05-04 14:16:00 +0200 : ctl_male_2.fastq.haspx     :
: -rw-r--r-- : asperaweb : fasp : 1048576000   : 2014-04-10 19:49:23 +0200 : 1GB                        :
: -rw-r--r-- : asperaweb : fasp : 104857600    : 2014-04-10 19:49:29 +0200 : 100MB                      :
: -rw-r--r-- : asperaweb : fasp : 10737418240  : 2014-04-10 19:49:04 +0200 : 10GB                       :
:............:...........:......:..............:...........................:............................:
```

```bash
ascli server download /aspera-test-dir-large/200MB
```

```output
Time: 00:00:02 ========================================================================================================== 100% 100 Mbps Time: 00:00:00
complete
```

### Going further

Get familiar with configuration, options, commands : [Command Line Interface](#cli).

Then, follow the section relative to the product you want to interact with ( Aspera on Cloud, Faspex, ...) : [Application Plugins](plugins)

## <a id="installation"></a>Installation

It is possible to install *either* directly on the host operating system (Linux, Windows, macOS) or as a docker container.

The direct installation is recommended and consists in installing:

* [Ruby](#ruby) (version: >= 2.4. Deprecation notice: the minimum will be 2.5 in a future version)
* [aspera-cli](#the_gem)
* [Aspera SDK (ascp)](#fasp_prot)

The following sections provide information on the various installation methods.

An internet connection is required for the installation. If you don't have internet for the installation, refer to section [Installation without internet access](#offline_install).

### Docker container

This method installs a docker image that contains: Ruby, `ascli` and the FASP SDK.

The image is: <https://hub.docker.com/r/martinlaurent/ascli>.
It is built from this [Dockerfile](Dockerfile).

Ensure that you have `docker` (or `podman`) installed.

```bash
docker --version
```

Download the script [`dascli`](../examples/dascli) from [the GIT repo](https://raw.githubusercontent.com/IBM/aspera-cli/main/examples/dascli) :

```bash
curl -o ascli https://raw.githubusercontent.com/IBM/aspera-cli/main/examples/dascli
```

```bash
chmod a+x ascli
```

If you have installed `ascli`, the script `dascli` can also be found:

```bash
cp $(ascli conf gem path)/../examples/dascli ascli
```

Once you have the base script: install the container image:

```bash
./ascli install
```

Note that ascli is run inside the container, so transfers are also executed inside the container and do not have access to host storage by default.

The wrapping script maps the folder  `$HOME/.aspera/ascli` on host to `/home/cliuser/.aspera/ascli` in the container.
This allows having persistent configuration on the host.

To transfer to/from the host, you will need to map a volume in docker or use the config folder (already mapped).
To add local storage as a volume, you can use the env var `docker_args`:

```bash
export docker_args='--volume /Users:/Users' 
```

Other env vars that can override values:

- `image` , by default: `martinlaurent/ascli`
- `version` , by default: `latest`

The config folder must be writable from the container, so the easiest way is to make it world readable and writable, for example:

```bash
export ASCLI_HOME=$HOME/.ascliconf
mkdir -p $ASCLI_HOME
chmod -R 777 $ASCLI_HOME
```

### <a id="ruby"></a>Ruby

Use this method to install on the native host.

A ruby interpreter is required to run the tool or to use the gem and tool.

Required Ruby version: >= 2.4. Deprecation notice: the minimum will be 2.5 in a future version.

*Ruby can be installed using any method* : rpm, yum, dnf, rvm, brew, windows installer, ... .

Refer to the following sections for a proposed method for specific operating systems.

The recommended installation method is `rvm` for systems with "bash-like" shell (Linux, macOS, Windows with cygwin, etc...).
If the generic install is not suitable (e.g. Windows, no cygwin), you can use one of OS-specific install method.
If you have a simpler better way to install Ruby : use it ! (version: >= 2.4. Deprecation notice: the minimum will be 2.5 in a future version)

#### Generic: RVM: single user installation (not root)

Use this method which provides more flexibility.

Install "rvm": follow [https://rvm.io/](https://rvm.io/) :

Execute the shell/curl command. As regular user, it install in the user's home: `~/.rvm` .

```bash
\curl -sSL https://get.rvm.io | bash -s stable
```

Follow on-screen instructions to install keys, and then re-execute the command.

If you keep the same terminal (not needed if re-login):

```bash
source ~/.rvm/scripts/rvm
```

It is advised to get one of the pre-compiled ruby version, you can list with:

```bash
rvm list --remote
```

Install the chosen pre-compiled Ruby version:

```bash
rvm install 2.7.2 --binary
```

Ruby is now installed for the user, go on to Gem installation.

#### Generic: RVM: global installation (as root)

Follow the same method as single user install, but execute as "root".

As root, it installs by default in /usr/local/rvm for all users and creates `/etc/profile.d/rvm.sh`.
One can install in another location with :

```bash
curl -sSL https://get.rvm.io | bash -s -- --path /usr/local
```

As root, make sure this will not collide with other application using Ruby (e.g. Faspex).
If so, one can rename the login script: `mv /etc/profile.d/rvm.sh /etc/profile.d/rvm.sh.ok`.
To activate ruby (and ascli) later, source it:

```bash
source /etc/profile.d/rvm.sh.ok
```

```bash
rvm version
```

#### Windows: Installer

Install Latest stable Ruby:

* Navigate to [https://rubyinstaller.org/](https://rubyinstaller.org/) &rarr; **Downloads**.
* Download the latest Ruby installer **with devkit**. (Msys2 is needed to install some native extensions, such as `grpc`)
* Execute the installer which installs by default in: `C:\RubyVV-x64` (VV is the version number)
* At the end of the installation procedure, the Msys2 installer is automatically executed, select option 3 (msys and mingw)
* for the installation of 
#### macOS: pre-installed or `brew`

macOS 10.13+ (High Sierra) comes with a recent Ruby. So you can use it directly. You will need to install aspera-cli using `sudo` :

```bash
sudo gem install aspera-cli
```

Alternatively, if you use [Homebrew](https://brew.sh/) already you can install Ruby with it:

```bash
brew install ruby
```

#### Linux: package

If your Linux distribution provides a standard ruby package, you can use it provided that the version is compatible (check at beginning of section).

Example: Centos 8 Stream

```bash
yum install make automake gcc gcc-c++ kernel-devel
yum install redhat-rpm-config
dnf module reset ruby
dnf module enable ruby:3.0
dnf module -y install ruby:3.0/common
gem install aspera-cli
```

Other examples:

```bash
yum install -y ruby ruby-devel rubygems ruby-json
```

```bash
apt install -y ruby ruby-dev rubygems ruby-json
```

One can cleanup the whole yum-installed ruby environment like this to uninstall:

```bash
gem uninstall $(ls $(gem env gemdir)/gems/|sed -e 's/-[^-]*$//'|sort -u)
```

#### Other Unixes (AIX)

Ruby is sometimes made available as installable package through third party providers.
For example for AIX, one can look at:

<https://www.ibm.com/support/pages/aix-toolbox-open-source-software-downloads-alpha#R>

If your Unix does not provide a pre-built ruby, you can get it using one of those
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

Note that using jruby the startup time is longer than the native ruby, but transfer speed is not impacted (executed by `ascp` binary).

### <a id="the_gem"></a>`aspera-cli` gem

Once you have Ruby and rights to install gems: Install the gem and its dependencies:

```bash
gem install aspera-cli
```

To upgrade to the latest version:

```bash
gem update aspera-cli
```

`ascli` checks every week if a new version is available and notify the user in a WARN log. To de-activate this feature set the option `version_check_days` to `0`, or specify a different period in days.

To check manually:

```bash
ascli conf check_update
```

### <a id="fasp_prot"></a>FASP Protocol

Most file transfers will be done using the FASP protocol, using `ascp`.
Only two additional files are required to perform an Aspera Transfer, which are part of Aspera SDK:

* ascp
* aspera-license (in same folder, or ../etc)

This can be installed either be installing an Aspera transfer software, or using an embedded command:

```bash
ascli conf ascp install
```

If a local SDK installation is preferred instead of fetching from internet: one can specify the location of the SDK file:

```bash
curl -Lso SDK.zip https://ibm.biz/aspera_sdk
```

```bash
ascli conf ascp install --sdk-url=file:///SDK.zip
```

The format is: `file:///<path>`, where `<path>` can be either a relative path (not starting with `/`), or an absolute path.

If the embedded method is not used, the following packages are also suitable:

* IBM Aspera Connect Client (Free)
* IBM Aspera Desktop Client (Free)
* IBM Aspera CLI (Free)
* IBM Aspera High Speed Transfer Server (Licensed)
* IBM Aspera High Speed Transfer EndPoint (Licensed)

For instance, Aspera Connect Client can be installed
by visiting the page: [https://www.ibm.com/aspera/connect/](https://www.ibm.com/aspera/connect/).

`ascli` will detect most of Aspera transfer products in standard locations and use the first one found.
Refer to section [FASP](#client) for details on how to select a client or set path to the FASP protocol.

Several methods are provided to start a transfer.
Use of a local client ([`direct`](#agt_direct) transfer agent) is one of them, but other methods are available. Refer to section: [Transfer Agents](#agents)

### <a id="offline_install"></a>Installation in air gapped environment

Note that currently no pre-packaged version exist yet.
A method to build one is provided here:

The procedure:

* Follow the non-root installation procedure with RVM, including gem
* Archive (zip, tar) the main RVM folder (includes ascli):

```bash
cd $HOME && tar zcvf rvm-ascli.tgz .rvm
```

* Get the Aspera SDK.

```bash
ascli conf --show-config --fields=sdk_url
```

* Download the SDK archive from that URL.

```bash
curl -Lso SDK.zip https://ibm.biz/aspera_sdk
```

* Transfer those 2 files to the target system

* On target system

```bash
cd $HOME

tar zxvf rvm-ascli.tgz

source ~/.rvm/scripts/rvm

ascli conf ascp install --sdk-url=file:///SDK.zip
```

* Add those lines to shell init (`.profile`)

```bash
source ~/.rvm/scripts/rvm
```

## <a id="cli"></a>Command Line Interface: `ascli`

The `aspera-cli` Gem provides a command line interface (CLI) which interacts with Aspera Products (mostly using REST APIs):

* IBM Aspera High Speed Transfer Server (FASP and Node)
* IBM Aspera on Cloud (including ATS)
* IBM Aspera Faspex
* IBM Aspera Shares
* IBM Aspera Console
* IBM Aspera Orchestrator
* and more...

`ascli` provides the following features:

* Supports most Aspera server products (on-premise and SaaS)
* Any command line options (products URL, credentials or any option) can be provided on command line, in configuration file, in env var, in files
* Supports Commands, Option values and Parameters shortcuts
* FASP [Transfer Agents](#agents) can be: local ascp, or Connect Client, or any transfer node
* Transfer parameters can be altered by modification of [*transfer-spec*](#transferspec), this includes requiring multi-session
* Allows transfers from products to products, essentially at node level (using the node transfer agent)
* Supports FaspStream creation (using Node API)
* Supports Watchfolder creation (using Node API)
* Additional command plugins can be written by the user
* Supports download of faspex and Aspera on Cloud "external" links
* Supports "legacy" ssh based FASP transfers and remote commands (ascmd)

Basic usage is displayed by executing:

```bash
ascli -h
```

Refer to sections: [Usage](#usage).

Not all `ascli` features are fully documented here, the user may explore commands on the command line.

### `ascp` command line

If you want to use `ascp` directly as a command line, refer to IBM Aspera documentation of either [Desktop Client](https://www.ibm.com/docs/en/asdc), [Endpoint](https://www.ibm.com/docs/en/ahte) or [Transfer Server](https://www.ibm.com/docs/en/ahts) where [a section on `ascp` can be found](https://www.ibm.com/docs/en/ahts/4.4?topic=linux-ascp-transferring-from-command-line).

Using `ascli` with plugin `server` for command line gives advantages over ascp:

* automatic resume on error
* configuration file
* choice of transfer agents
* integrated support of multi-session

Moreover all `ascp` options are supported either through transfer spec parameters and with the possibility to provide `ascp` arguments directly when the `direct` agent is used (`EX_ascp_args`).

### <a id="parsing"></a>Command line parsing, Special Characters

`ascli` is typically executed in a shell, either interactively or in a script.
`ascli` receives its arguments from this shell (through Operating System).

#### Shell parsing for Linux, Unix, Macos

On Linux and Unix environments, this is typically a POSIX shell (bash, zsh, ksh, sh).
In this environment the shell parses the command line, possibly replacing variables, etc...
see [bash shell operation](https://www.gnu.org/software/bash/manual/bash.html#Shell-Operation).
Then it builds a list of arguments and then `ascli` (Ruby) is executed.
Ruby receives a list parameters from shell and gives it to `ascli`.
So special character handling (quotes, spaces, env vars, ...) is first done in the shell.

#### Shell parsing for Windows

On Windows, `cmd.exe` is typically used.
Windows process creation does not receive the list of arguments but just the whole line.
It's up to the program to parse arguments. Ruby follows the Microsoft C/C++ parameter parsing rules.

* [Windows: How Command Line Parameters Are Parsed](https://daviddeley.com/autohotkey/parameters/parameters.htm#RUBY)
* [Understand Quoting and Escaping of Windows Command Line Arguments](http://www.windowsinspired.com/understanding-the-command-line-string-and-arguments-received-by-a-windows-program/)

#### Extended Values (JSON, Ruby, ...)

Some of the CLI parameters are expected to be [Extended Values](#extended), i.e. not a simple strings, but a complex structure (Hash, Array).
Typically, the `@json:` modifier is used, it expects a JSON string. JSON itself has some special syntax: for example `"` is used to denote strings.

#### Testing Extended Values

In case of doubt of argument values after parsing, one can test using command `config echo`. `config echo` takes exactly **one** argument which can use the [Extended Value](#extended) syntax. Unprocessed command line arguments are shown in the error message.

Example: The shell parses three arguments (as strings: `1`, `2` and `3`), so the additional two arguments are not processed by the `echo` command.

```bash
ascli conf echo 1 2 3
```

```bash
"1"
ERROR: Argument: unprocessed values: ["2", "3"]
```

`config echo` displays the value of the first argument using Ruby syntax: it surrounds a string with `"` and add `\` before special characters.
Note that it gets its value after shell command line parsing and `ascli` extended value parsing.

In the following examples (using a POSIX shell, such as `bash`), several sample commands are provided when equivalent.
For all example, most of special character handling is not specific to `ascli`: It depoends on the underlying syntax: shell , JSON, etc...
Depending on the case, a different `format` is used to display the actual value.

For example, in the simple string `Hello World`, the space character is special for the shell, so it must be escaped so that a single value is represented.

Double quotes are processed by the shell to create a single string argument.
For POSIX shells, single quotes can also be used in this case, or protext the special character ` ` (space) with a backslash.

```bash
ascli conf echo "Hello World" --format=text
ascli conf echo 'Hello World' --format=text
ascli conf echo Hello\ World --format=text
```

```output
Hello World
```

#### Using a shell variable, parsed by shell, in an extended value

To be evaluated by shell, the shell variable must not be in single quotes.
Note we use a simple variable here: the variable is not necessarily an environment variable.
Even if the variable contains spaces it makes only one argument to `ascli` because word parsing is made before variable expansion by shell. 

```bash
MYVAR="Hello World"
ascli conf echo @json:'{"title":"'$MYVAR'"}' --format=json
ascli conf echo @json:{\"title\":\"$MYVAR\"} --format=json
```

```json
{"title":"Hello World"}
```

#### Double quote in strings in command line

Double quote is a shell special character.
Like any shell special character, it can be protected either by preceding with a backslash or by enclosing in a single quote.

```bash
ascli conf echo \"
ascli conf echo '"'
```

```output
"
```

Double quote in JSON is a little tricky because `"` is special both for the shell and JSON. Both shell and JSON syntax allow to protect `"`, but only the shell allows protection using single quote.

```bash
ascli conf echo @json:'"\""' --format=text
ascli conf echo @json:\"\\\"\" --format=text
ascli conf echo @ruby:\'\"\' --format=text
```

```output
"
```

Here a single quote or a backslash protects the double quote to avoid shell processing, and then an additional `\` is added to protect the `"` for JSON. But as `\` is also shell special, then it is protected by another `\`.
  
#### Shell and JSON or Ruby special characters in extended value

Construction of values with special characters is done like this:

* First select a syntax to represent the extended value, e.g. JSON or Ruby

* Write the expression using this syntax, for example, using JSON:

```json
{"title":"Test \" ' & \\"}
```

or using Ruby:

```ruby
{"title"=>"Test \" ' & \\"}
{'title'=>%q{Test " ' & \\}}
```

Both `"` and `\` are special characters for JSON and Ruby and can be protected with `\` (unless Ruby's extended single quote notation `%q` is used).
  
* Then, since the value will be evaluated by shell, any shell special characters must be protected, either using preceding `\` for each character to protect, or by enclosing in single quote:

```bash
ascli conf echo @json:{\"title\":\"Test\ \\\"\ \'\ \&\ \\\\\"} --format=json
ascli conf echo @json:'{"title":"Test \" '\'' & \\"}' --format=json
ascli conf echo @ruby:"{'title'=>%q{Test \" ' & \\\\}}" --format=json
```

```json
{"title":"Test \" ' & \\"}
```

#### Reading special characters interractively

If `ascli` is used interractively (a user typing on terminal), it is easy to require the user to type values:

```bash
ascli conf echo @ruby:"{'title'=>gets.chomp}" --format=json
```

`gets` is Ruby's method of terminal input (terminated by `\n`), and `chomp` removes the trailing `\n`.

#### Extended value using special characters read from environmental variables or files

Using a text editor or shell: create a file `title.txt` (and env var) that contains exactly the text required: `Test " ' & \` :

```bash
export MYTITLE='Test " '\'' & \'
echo -n $MYTITLE > title.txt
```

Using those values will not require any escaping of characters since values do not go through shell or JSON parsing.

If the value is to be assigned directly to an option of ascli, then you can directly use the content of the file or env var using the `@file:` or `@env:` readers:

```bash
ascli conf echo @file:title.txt --format=text
ascli conf echo @env:MYTITLE --format=text
```

```output
Test " ' & \
```

If the value to be used is in a more complex structure, then the `@ruby:` modifier can be used: it allows any ruby code in expression, including reading from file or env var. In those cases, there is no character to protect because values are not parsed by the shell, or JSON or even Ruby.

```bash
ascli conf echo @ruby:"{'title'=>File.read('title.txt')}" --format=json
ascli conf echo @ruby:"{'title'=>ENV['MYTITLE']}" --format=json
```

```json
{"title":"Test \" ' & \\"}
```

### Arguments : Commands and options

Arguments are the units of command line, as parsed by the shell, typically separated by spaces (and called "argv").

There are two types of command line arguments: Commands and Options. Example :

```bash
ascli command subcommand --option-name=VAL1 VAL2
```

* executes *command*: `command subcommand`
* with one *option*: `option_name`
* this option is given a *value* of: `VAL1`
* the command has one additional *argument*: `VAL2`

When the value of a command, option or argument is constrained by a fixed list of values, it is possible to use the first letters of the value only, provided that it uniquely identifies a value. For example `ascli conf ov` is the same as `ascli config overview`.

The value of options and arguments is evaluated with the [Extended Value Syntax](#extended).

#### Options

All options, e.g. `--log-level=debug`, are command line arguments that:

* start with `--`
* have a name, in lowercase, using `-` as word separator in name  (e.g. `--log-level=debug`)
* have a value, separated from name with a `=`
* can be used by prefix, provided that it is unique. E.g. `--log-l=debug` is the same as `--log-level=debug`

Exceptions:

* some options accept a short form, e.g. `-Ptoto` is equivalent to `--preset=toto`, refer to the manual or `-h`.
* some options (flags) don't take a value, e.g. `-r`
* the special option `--` stops option processing and is ignored, following command line arguments are taken as arguments, including the ones starting with a `-`. Example:

```bash
ascli config echo -- --sample
```

```bash
"--sample"
```

Note that here, `--sample` is taken as an argument, and not as an option, due to `--`.

Options can be optional or mandatory, with or without (hardcoded) default value. Options can be placed anywhere on command line and evaluated in order.

The value for *any* options can come from the following locations (in this order, last value evaluated overrides previous value):

* [Configuration file](#configfile).
* Environment variable
* Command line

Environment variable starting with prefix: ASCLI_ are taken as option values, e.g. `ASCLI_OPTION_NAME` is for `--option-name`.

Options values can be displayed for a given command by providing the `--show-config` option: `ascli node --show-config`

#### Commands and Arguments

Command line arguments that are not options are either commands or arguments. If an argument must begin with `-`, then either use the `@val:` syntax (see [Extended Values](#extended)), or use the `--` separator (see above).

### Interactive Input

Some options and parameters are mandatory and other optional. By default, the tool will ask for missing mandatory options or parameters for interactive execution.

The behavior can be controlled with:

* --interactive=&lt;yes|no&gt; (default=yes if STDIN is a terminal, else no)
  * yes : missing mandatory parameters/options are asked to the user
  * no : missing mandatory parameters/options raise an error message
* --ask-options=&lt;yes|no&gt; (default=no)
  * optional parameters/options are asked to user

### Output

Command execution will result in output (terminal, stdout/stderr).
The information displayed depends on the action.

#### Types of output data

Depending on action, the output will contain:

* `single_object` : displayed as a 2 dimensional table: one line per attribute, first column is attribute name, and second is attribute value. Nested hashes are collapsed.
* `object_list` : displayed as a 2 dimensional table: one line per item, one column per attribute.
* `value_list` : a table with one column.
* `empty` : nothing
* `status` : a message
* `other_struct` : a complex structure that cannot be displayed as an array

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

* `text` : Value as String
* `table` : Text table
* `ruby` : Ruby code
* `json` : JSON code
* `jsonpp` : JSON pretty printed
* `yaml` : YAML
* `csv` : Comma Separated Values

#### <a id="option_select"></a>Option: `select`: Filter on columns values for `object_list`

Table output can be filtered using the `select` parameter. Example:

```javascript
ascli aoc admin res user list --fields=name,email,ats_admin --query=@json:'{"sort":"name"}' --select=@json:'{"ats_admin":true}'
```

```output
:...............................:..................................:...........:
:             name              :              email               : ats_admin :
:...............................:..................................:...........:
: John Curtis                   : john@example.com                 : true      :
: Laurent Martin                : laurent@example.com              : true      :
:...............................:..................................:...........:
```

Note that `select` filters selected elements from the result of API calls, while the `query` parameters gives filtering parameters to the API when listing elements.

#### Verbosity of output

Output messages are categorized in 3 types:

* `info` output contain additional information, such as number of elements in a table
* `data` output contain the actual output of the command (object, or list of objects)
* `error`output contain error messages

The option `display` controls the level of output:

* `info` displays all messages: `info`, `data`, and `error`
* `data` display `data` and `error` messages
* `error` display only error messages.

By default, secrets are removed from output: option `show_secrets` defaults to `no`, unless `display` is `data`, to allows piping results.
To hide secrets from output, set option `show_secrets` to `no`.

#### Selection of output object properties

By default, a table output will display one line per entry, and columns for each entries. Depending on the command, columns may include by default all properties, or only some selected properties. It is possible to define specific columns to be displayed, by setting the `fields` option to one of the following value:

* DEF : default display of columns (that's the default, when not set)
* ALL : all columns available
* a,b,c : the list of attributes specified by the comma separated list
* Array extended value: for instance, @json:'["a","b","c"]' same as above
* +a,b,c : add selected properties to the default selection.
* -a,b,c : remove selected properties from the default selection.

### <a id="extended"></a>Extended Value Syntax

Usually, values of options and arguments are specified by a simple string. But sometime it is convenient to read a value from a file, or decode it, or have a value more complex than a string (e.g. Hash table).

The extended value syntax is:

```bash
<0 or more decoders><0 or 1 reader><nothing or some text value>
```

The difference between reader and decoder is order and ordinality. Both act like a function of value on right hand side. Decoders are at the beginning of the value, followed by a single optional reader, followed by the optional value.

The following "readers" are supported (returns value in []):

* @val:VALUE   : [String] prevent further special prefix processing, e.g. `--username=@val:laurent` sets the option `username` to value `laurent`.
* @file:PATH   : [String] read value from a URL, e.g. `--fpac=@uri:http://serv/f.pac`
* @uri:URL     : [String] read value from a file (prefix `~/` is replaced with the users home folder), e.g. `--key=@file:~/.ssh/mykey`
* @path:PATH   : [String] performs path expansion (prefix `~/` is replaced with the users home folder), e.g. `--config-file=@path:~/sample_config.yml`
* @env:ENVVAR  : [String] read from a named env var, e.g.--password=@env:MYPASSVAR
* @stdin:      : [String] read from stdin (no value on right)
* @preset:NAME : [Hash] get whole option preset value by name. Subvalues can also be used using `.` as separator. e.g. foo.bar is conf[foo][bar]

In addition it is possible to decode a value, using one or multiple decoders :

* @base64: [String] decode a base64 encoded string
* @json: [any] decode JSON values (convenient to provide complex structures)
* @zlib: [String] uncompress data
* @ruby: [any] execute ruby code
* @csvt: [Array] decode a titled CSV value
* @lines: [Array] split a string in multiple lines and return an array
* @list: [Array] split a string in multiple items taking first character as separator and return an array
* @incps: [Hash] include values of presets specified by key `incps` in input hash

To display the result of an extended value, use the `config echo` command.

Example: read the content of the specified file, then, base64 decode, then unzip:

```bash
ascli config echo @zlib:@base64:@file:myfile.dat
```

Example: create a value as a hash, with one key and the value is read from a file:

```bash
ascli config echo @ruby:'{"token_verification_key"=>File.read("pubkey.txt")}'
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
ascli config echo @csvt:@file:test.csv
```

```output
:......:.....................:
: name :        email        :
:......:.....................:
: lolo : laurent@example.com :
: toto : titi@tutu.tata      :
:......:.....................:
```

Example: create a hash and include values from preset named "config" of config file in this hash

```javascript
ascli config echo @incps:@json:'{"hello":true,"incps":["config"]}'
```

```bash
{"version"=>"0.9", "hello"=>true}
```

Note that `@incps:@json:'{"incps":["config"]}'` or `@incps:@ruby:'{"incps"=>["config"]}'` is equivalent to: `@preset:config`

### <a id="native"></a>Structured Value

Some options and parameters expect a [Extended Value](#extended), i.e. a value more complex than a simple string. This is usually a Hash table or an Array, which could also contain sub structures.

For instance, a [*transfer-spec*](#transferspec) is expected to be a [Extended Value](#extended).

Structured values shall be described using the [Extended Value Syntax](#extended).
A convenient way to specify a [Extended Value](#extended) is to use the `@json:` decoder, and describe the value in JSON format. The `@ruby:` decoder can also be used. For an array of hash tables, the `@csvt:` decoder can be used.

It is also possible to provide a [Extended Value](#extended) in a file using `@json:@file:<path>`

### <a id="conffolder"></a>Configuration and Persistency Folder

`ascli` configuration and other runtime files (token cache, file lists, persistency files, SDK) are stored `[config folder]`: `[User's home folder]/.aspera/ascli`.

Note: `[User's home folder]` is found using ruby's `Dir.home` (`rb_w32_home_dir`).
It uses the `HOME` env var primarily, and on MS Windows it also looks at `%HOMEDRIVE%%HOMEPATH%` and `%USERPROFILE%`. `ascli` sets the env var `%HOME%` to the value of `%USERPROFILE%` if set and exists. So, on Windows `%USERPROFILE%` is used as it is more reliable than `%HOMEDRIVE%%HOMEPATH%`.

The [config folder] can be displayed using :

```bash
ascli config folder
```

```bash
/Users/kenji/.aspera/ascli
```

It can be overridden using the environment variable `ASCLI_HOME`.

Example (Windows):

```output
set ASCLI_HOME=C:\Users\Kenji\.aspera\ascli

ascli config folder

C:\Users\Kenji\.aspera\ascli
```

When OAuth is used (AoC, Faspex4 apiv4, Faspex5) `ascli` keeps a cache of generated bearer tokens in `[config folder]/persist_store` by default.
Option `cache_tokens` (**yes**/no) allows to control if Oauth tokens are cached on file system, or generated for each request.
The command `config flush_tokens` deletes all existing tokens.
Tokens are kept on disk for a maximum of 30 minutes (`TOKEN_CACHE_EXPIRY_SEC`) and garbage collected after that.
Tokens that can be refreshed are refreshed. Else tokens are re-generated if expired.

### <a id="configfile"></a>Configuration file

On the first execution of `ascli`, an empty configuration file is created in the configuration folder.
Nevertheless, there is no mandatory information required in this file, the use of it is optional as any option can be provided on the command line.

Although the file is a standard YAML file, `ascli` provides commands to read and modify it using the `config` command.

All options for `ascli` can be set on command line, or by env vars, or using [option presets](#lprt) in the configuration file.

A configuration file provides a way to define default values, especially for authentication parameters, thus avoiding to always having to specify those parameters on the command line.

The default configuration file is: `$HOME/.aspera/ascli/config.yaml` (this can be overridden with option `--config-file=path` or equivalent env var).

The configuration file is simply a catalog of pre-defined lists of options, called: [option presets](#lprt). Then, instead of specifying some common options on the command line (e.g. address, credentials), it is possible to invoke the ones of a [option preset](#lprt) (e.g. `mypreset`) using the option: `-Pmypreset` or `--preset=mypreset`.

#### <a id="lprt"></a>Option preset

A [option preset](#lprt) is simply a collection of parameters and their associated values in a named section in the configuration file.

A named [option preset](#lprt) can be modified directly using `ascli`, which will update the configuration file :

```bash
ascli config preset set|delete|show|initialize|update <option preset>
```

The command `update` allows the easy creation of [option preset](#lprt) by simply providing the options in their command line format, e.g. :

```bash
ascli config preset update demo_server --url=ssh://demo.asperasoft.com:33001 --username=asperaweb --password=_pass_here_ --ts=@json:'{"precalculate_job_size":true}'
```

* This creates a [option preset](#lprt) `demo_server` with all provided options.

The command `set` allows setting individual options in a [option preset](#lprt).

```bash
ascli config preset set demo_server password _pass_here_
```

The command `initialize`, like `update` allows to set several parameters at once, but it deletes an existing configuration instead of updating it, and expects a [*Structured Value*](#native).

```javascript
ascli config preset initialize demo_server @json:'{"url":"ssh://demo.asperasoft.com:33001","username":"asperaweb","password":"_pass_here_","ts":{"precalculate_job_size":true}}'
```

A full terminal based overview of the configuration can be displayed using:

```bash
ascli config preset over
```

A list of [option preset](#lprt) can be displayed using:

```bash
ascli config preset list
```

A good practice is to not manually edit the configuration file and use modification commands instead.
If necessary, the configuration file can opened in a text editor with:

```bash
ascli config open
```

Older format for commands are still supported:

```bash
ascli config id <name> set|delete|show|initialize|update
ascli config over
ascli config list
```

#### <a id="lprtconf"></a>Special Option preset: config

This preset name is reserved and contains a single key: `version`. This is the version of `ascli` which created the file.

#### <a id="lprtdef"></a>Special Option preset: default

This preset name is reserved and contains an array of key-value , where the key is the name of a plugin, and the value is the name of another preset.

When a plugin is invoked, the preset associated with the name of the plugin is loaded, unless the option --no-default (or -N) is used.

Note that special plugin name: `config` can be associated with a preset that is loaded initially, typically used for default values.

Operations on this preset are done using regular `config` operations:

```bash
ascli config preset set default _plugin_name_ _default_preset_for_plugin_
```

```bash
ascli config preset get default _plugin_name_
```

```javascript
"_default_preset_for_plugin_"
```

#### <a id="lplugconf"></a>Special Plugin: config

Plugin `config` (not to be confused with Option preset config) is used to configure `ascli` but it also contains global options.

When `ascli` starts, it looks for the `default` Option preset and if there is a value for `config`, if so, it loads the option values for any plugin used.

If no global default is set by the user, the tool will use `global_common_defaults` when setting global parameters (e.g. `conf ascp use`)

Sample commands

```bash
config ascp connect info 'Aspera Connect for Windows'
config ascp connect list
config ascp connect version 'Aspera Connect for Windows' download 'Windows Installer' --to-folder=.
config ascp connect version 'Aspera Connect for Windows' list
config ascp connect version 'Aspera Connect for Windows' open documentation
config ascp errors
config ascp info --sdk-folder=Tsdk_test_dir
config ascp install --sdk-folder=Tsdk_test_dir
config ascp products list
config ascp show
config ascp spec
config check_update
config detect --url=https://my_aoc_org.ibmaspera.com
config detect --url=my_faspex_url
config detect --url=my_node_url
config doc
config doc transfer-parameters
config echo 'hello'
config echo @base64:SGVsbG8gV29ybGQK
config echo @csvt:@stdin:
config echo @env:USER
config echo @lines:@stdin:
config echo @list:,1,2,3
config echo @uri:/etc/hosts
config echo @uri:file:/etc/hosts
config echo @uri:http://www.ibm.com
config echo @uri:https://www.ibm.com
config echo @val:@file:yo
config echo @zlib:@stdin:
config email_test --notif-to=my_recipient_email
config export
config flush_tokens
config genkey mykey
config plugin create mycommand T
config plugin list
config proxy_check --fpac=@file:examples/proxy.pac https://eudemo.asperademo.com
config wiz --url=https://my_aoc_org.ibmaspera.com --config-file=SAMPLE_CONFIG_FILE --pkeypath= --username=my_aoc_user_email --test-mode=yes
config wiz --url=https://my_aoc_org.ibmaspera.com --config-file=SAMPLE_CONFIG_FILE --pkeypath= --username=my_aoc_user_email --test-mode=yes --use-generic-client=yes
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
  password: _pass_here_
```

We can see here:

* The configuration was created with CLI version 0.3.7
* the default [option preset](#lprt) to load for `server` plugin is : `demo_server`
* the [option preset](#lprt) `demo_server` defines some parameters: the URL and credentials
* the default [option preset](#lprt) to load in any case is : `cli_default`

Two [option presets](#lprt) are reserved:

* `config` contains a single value: `version` showing the CLI
version used to create the configuration file. It is used to check compatibility.
* `default` is reserved to define the default [option preset](#lprt) name used for known plugins.

The user may create as many [option presets](#lprt) as needed. For instance, a particular [option preset](#lprt) can be created for a particular application instance and contain URL and credentials.

Values in the configuration also follow the [Extended Value Syntax](#extended).

Note: if the user wants to use the [Extended Value Syntax](#extended) inside the configuration file, using the `config preset update` command, the user shall use the `@val:` prefix. Example:

```bash
ascli config preset set my_aoc_org private_key @val:@file:"$HOME/.aspera/ascli/my_private_key"
```

This creates the [option preset](#lprt):

```yaml
...
my_aoc_org:
  private_key: @file:"/Users/laurent/.aspera/ascli/my_private_key"
...
```

So, the key file will be read only at execution time, but not be embedded in the configuration file.

#### Options evaluation order

Some options are global, some options are available only for some plugins. (the plugin is the first level command).

Options are loaded using this algorithm:

* If option `--no-default` (or `-N`) is specified, then no default value is loaded is loaded for the plugin
* else it looks for the name of the plugin as key in section `default`, the value is the name of the default [option preset](#lprt) for it, and loads it.
* If option `--preset=<name or extended value hash>` is specified (or `-Pxxxx`), this reads the [option preset](#lprt) specified from the configuration file, or of the value is a Hash, it uses it as options values.
* Environment variables are evaluated
* Command line options are evaluated

Parameters are evaluated in the order of command line.

To avoid loading the default [option preset](#lprt) for a plugin, use: `-N`

On command line, words in parameter names are separated by a dash, in configuration file, separator
is an underscore. E.g. --xxx-yyy  on command line gives xxx_yyy in configuration file.

The main plugin name is `config`, so it is possible to define a default [option preset](#lprt) for the main plugin with:

```bash
ascli config preset set cli_default interactive no
```

```bash
ascli config preset set default config cli_default
```

A [option preset](#lprt) value can be removed with `unset`:

```bash
ascli config preset unset cli_default interactive
```

Example: Define options using command line:

```bash
ascli -N --url=_url_here_ --password=_pass_here_ --username=_name_here_ node --show-config
```

Example: Define options using a hash:

```javascript
ascli -N --preset=@json:'{"url":"_url_here_","password":"_pass_here_","username":"_name_here_"}' node --show-config
```

#### Shares Examples

For Faspex, Shares, Node (including ATS, Aspera Transfer Service), Console,
only username/password and url are required (either on command line, or from config file).
Those can usually be provided on the command line:

```bash
ascli shares repo browse / --url=https://10.25.0.6 --username=john --password=_pass_here_
```

This can also be provisioned in a config file:

* Build [option preset](#lprt)

```bash
ascli config preset set shares06 url https://10.25.0.6
ascli config preset set shares06 username john
ascli config preset set shares06 password _pass_here_
```

This can also be done with one single command:

```javascript
ascli config preset init shares06 @json:'{"url":"https://10.25.0.6","username":"john","password":"_pass_here_"}'
```

or

```bash
ascli config preset update shares06 --url=https://10.25.0.6 --username=john --password=_pass_here_
```

* Define this [option preset](#lprt) as the default [option preset](#lprt) for the specified plugin (`shares`)

```bash
ascli config preset set default shares shares06
```

* Display the content of configuration file in table format

```bash
ascli config overview
```

* Execute a command on the shares application using default parameters

```bash
ascli shares repo browse /
```

### <a id="vault"></a>Secret Vault

When a secret or password is needed, it is possible to store in the secret vault.

By default the vault is defined using option `secrets`, which can be stored in the configuration file.

#### Using system keychain

Only on macOS.

It is possible to store secrets in macOS keychain (only read supported currently).

Set option `secrets` to value `system` to use the default keychain or use value `system:[name]` to use a custom keychain.

#### Modern config file format: encrypted in config file

It is possible to store and use secrets encrypted.
For this use the `config vault` command.

The vault can be initialized with `config vault init`

Then secrets can be manipulated using commands:

* `set`
* `get`
* `list`
* `delete`

Secrets must be uniquely identified by `url` and `username`. An optional description can be provided using option `value`.

#### Legacy config file format

THIS FORMAT WILL BE DEPRECATED

The value provided can be a Hash, where keys are usernames (or access key id), and values are the associated password or secrets in clear.

For example, choose a repository name, for example `my_secrets`, and populate it like this:

```bash
ascli conf id my_secrets set 'access_key1' 'secret1'

ascli conf id my_secrets set 'access_key2' 'secret2'

ascli conf id default get config

cli_default
```

Here above, one has already set a `config` global preset to preset `cli_default` (refer to earlier in documentation).
So the repository can be read by default like this (note the prefix `@val:` to avoid the evaluation of prefix `@preset:`):

```bash
ascli conf id cli_default set secrets @val:@preset:my_secrets
```

A secret repository can always be selected at runtime using `--secrets=@preset:xxxx`, or `--secrets=@json:'{"accesskey1":"secret1"}'`

To test if a secret can be found use:

```bash
ascli conf vault get --username=access_key1
```

### <a id="private_key"></a>Private Key

Some applications allow the user to be authenticated using a private key (Server, AoC, Faspex5, ...).
It consists in using a pair of keys: the private key and its associated public key.
The same key can be used for multiple applications.
Technically, a private key contains the public key, which can be extracted from it.
The private key can be protected by a passphrase or not.
If the key is protected by a passphrase, then it will be prompted.
(some plugins support option `passphrase`)

Several methods can be used to generate a key pair:

The following commands use this variable:

```bash
PRIVKEYFILE=~/.aspera/ascli/my_private_key
```

* `ascli`

The generated key is of type RSA, by default: 4096 bit.
For convenience, the public key is also extracted with extension `.pub`.
The key is not passphrase protected.

```bash
ascli config genkey ${PRIVKEYFILE} 4096
```

* `ssh-keygen`

Both private and public keys are generated, option `-N` is for passphrase.

```bash
ssh-keygen -t rsa -b 4096 -N '' -f ${PRIVKEYFILE}
```

* `openssl`

openssl is sometimes compiled to support option `-nodes` (no DES, i.e. no passphrase, e.g. on macOS).
To generate a private key pair without passphrase the following can be used on any system:

```bash
openssl genrsa -passout pass:dummypassword -out ${PRIVKEYFILE}.protected 4096
openssl rsa -passin pass:dummypassword -in ${PRIVKEYFILE}.protected -out ${PRIVKEYFILE}
openssl rsa -pubout -in ${PRIVKEYFILE} -out ${PRIVKEYFILE}.pub
rm -f ${PRIVKEYFILE}.protected
```

To change (or add) the passphrase for a key do:

```bash
openssl rsa -des3 -in old_file -out new_file
```

### <a id="certificates"></a>SSL CA certificate bundle

`ascli` uses ruby `openssl` gem, which uses the `openssl` library.
Certificates are checked against the ruby default certificates [OpenSSL::X509::DEFAULT_CERT_FILE](https://ruby-doc.org/stdlib-3.0.3/libdoc/openssl/rdoc/OpenSSL/X509/Store.html), which are typically the ones of `openssl` on Unix systems (Linux, macOS, etc..).
The environment variables `SSL_CERT_FILE` and `SSL_CERT_DIR` are used if defined.

`ascp` also needs to validate certificates when using WSS.
By default, `ascp` uses primarily certificates from hard-coded path (e.g. on macOS: `/Library/Aspera/ssl`).
`ascli` overrides and sets the default ruby certificate path as well for `ascp` using `-i` switch.
So to update certificates, update ruby's `openssl` gem, or use env vars `SSL_CERT_*`.

### Plugins

The CLI tool uses a plugin mechanism.
The first level command (just after `ascli` on the command line) is the name of the concerned plugin which will execute the command.
Each plugin usually represents commands sent to a specific application.
For instance, the plugin `faspex` allows operations on the application "Aspera Faspex".

Available plugins can be found using command:

```bash
ascli conf plugin list
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

By default plugins are looked-up in folders specifed by (multi-value) option `plugin_folder`:

```javascript
ascli --show-config --select=@json:'{"key":"plugin_folder"}'
```

You can create the skeleton of a new plugin like this:

```bash
ascli conf plugin create foo .
```

```output
Created ./foo.rb
```

```bash
ascli --plugin-folder=. foo
```

#### <a id="plugins"></a>Plugins: Application URL and Authentication

`ascli` comes with several Aspera application plugins.

REST APIs of Aspera legacy applications (Aspera Node, Faspex, Shares, Console, Orchestrator, Server) use simple username/password authentication: HTTP Basic Authentication.

Those are using options:

* url
* username
* password

Those can be provided using command line, parameter set, env var, see section above.

Aspera on Cloud relies on Oauth, refer to the [Aspera on Cloud](#aoc) section.

### Logging, Debugging

The gem is equipped with traces, mainly for debugging and learning APIs.
By default logging level is `warn` and the output channel is `stderr`.
To increase debug level, use parameter `log_level` (e.g. using command line `--log-level=xx`, env var `ASCLI_LOG_LEVEL`, or a parameter in the configuration file).

It is also possible to activate traces before log facility initialization using env var `ASCLI_LOG_LEVEL`.

By default passwords and secrets are removed from logs.
Use option `log_secrets` set to `yes` to reveal secrets in logs.

Available loggers: `stdout`, `stderr`, `syslog`.

Available levels: `debug`, `info`, `warn`, `error`.

Note that when using the `direct` agent (`ascp`), additional transfer logs can be activated using `ascp` option `EX_ascp_args`, see [`direct`](#agt_direct).

Examples:

* display debugging log on `stdout`:

```bash
ascli conf over --log-level=debug --logger=stdout
```

* log errors to `syslog`:

```bash
ascli conf over --log-level=error --logger=syslog
```

When `ascli` is used interactively in a shell, the shell itself will usually log executed commands in the history file.

### Learning Aspera Product APIs (REST)

This CLI uses REST APIs.
To display HTTP calls, use argument `-r` or `--rest-debug`, this is useful to display exact content of HTTP requests and responses.

In order to get traces of execution, use argument : `--log-level=debug`

### <a id="http_options"></a>HTTP socket parameters

If the server does not provide a valid certificate, use option: `--insecure=yes`.

Ruby HTTP socket parameters can be adjusted.

| parameter            | default |
|----------------------|---------|
| `read_timeout`       | 60      |
| `write_timeout`      | 60      |
| `open_timeout`       | 60      |
| `keep_alive_timeout` | 2       |

Values are in set *seconds* and can be of type either integer or float.
Default values are the ones of Ruby.
For details refer to the Ruby library: [`Net::HTTP`](https://ruby-doc.org/stdlib/libdoc/net/http/rdoc/Net/HTTP.html).

Like any other option, those can be set either on command line, or in config file, either in a global preset or server-specific one.

Example:

```javascript
ascli aoc admin res package list --http-options=@json:'{"read_timeout":10.0}'
```

### <a id="graphical"></a>Graphical Interactions: Browser and Text Editor

Some actions may require the use of a graphical tool:

* a browser for Aspera on Cloud authentication (web auth method)
* a text editor for configuration file edition

By default the CLI will assume that a graphical environment is available on windows, and on other systems, rely on the presence of the "DISPLAY" environment variable.
It is also possible to force the graphical mode with option --ui :

* `--ui=graphical` forces a graphical environment, a browser will be opened for URLs or a text editor for file edition.
* `--ui=text` forces a text environment, the URL or file path to open is displayed on terminal.

### Proxy

There are several types of network connections, each of them use a different mechanism to define a *proxy*.

#### HTTP proxy for REST calls and transfers using HTTP gateway

To specify a HTTP proxy when ruby HTTP is used, set the `http_proxy` environment variable (lower case, preferred, or upper case).
See [Ruby findproxy](https://rubyapi.org/3.0/o/uri/generic#method-i-find_proxy).

```bash
export http_proxy=http://myproxy.org.net:3128
```

Note that ruby expects a URL and `myproxy.org.net:3128` alone is not accepted.

#### FASP proxy (forward) for transfers

To specify a FASP proxy (forward), set the [*transfer-spec*](#transferspec) parameter: `EX_fasp_proxy_url` (only supported with the `direct` agent).

#### HTTP proxy legacy Aspera HTTP fallback transfers

To specify a proxy for legacy HTTP fallback, set the [*transfer-spec*](#transferspec) parameter: `EX_http_proxy_url` (only supported with the `direct` agent).
(It is also possible to use `EX_ascp_args` and native options in `direct`)

#### Proxy auto config

The `fpac` option allows use of a [Proxy Auto Configuration (PAC)](https://en.wikipedia.org/wiki/Proxy_auto-config) script defined as javascript value.
To read the script from a URL (`http:`, `https:` and `file:`), use: `@uri:`.
A minimal script can be specified, for example like this, to define the use of a local proxy:

```bash
export ASCLI_FPAC='function FindProxyForURL(url, host){return "PROXY localhost:3128"}'
```

The PAC file will be used for any HTTP/HTTPS/REST connection, but not other (e.g. FASP, HTTP fallback, HTTPGW)

The PAC file can be tested with command: `config proxy_check`. Example, using command line option:

```bash
ascli conf proxy_check --fpac='function FindProxyForURL(url, host) {return "PROXY proxy.example.com:1234;DIRECT";}' http://example.com
PROXY proxy.example.com:1234;DIRECT
```

```bash
ascli config proxy_check --fpac=@file:./proxy.pac http://www.example.com
PROXY proxy.example.com:8080
```

```bash
ascli config proxy_check --fpac=@uri:http://server/proxy.pac http://www.example.com
PROXY proxy.example.com:8080
```

### <a id="client"></a>FASP configuration

The `config` plugin also allows specification for the use of a local FASP client. It provides the following commands for `ascp` subcommand:

* `show` : shows the path of ascp used
* `use` : list,download connect client versions available on internet
* `products` : list Aspera transfer products available locally
* `connect` : list,download connect client versions available on internet

#### Show path of currently used `ascp`

```bash
ascli config ascp show
```

```output
/Users/laurent/.aspera/ascli/sdk/ascp
```

```bash
ascli config ascp info
```

```output
+--------------------+-----------------------------------------------------------+
| key                | value                                                     |
+--------------------+-----------------------------------------------------------+
| ascp               | /Users/laurent/.aspera/ascli/sdk/ascp                     |
...
```

#### Selection of `ascp` location for [`direct`](#agt_direct) agent

By default, `ascli` uses any found local product with ascp, including SDK.

To temporarily use an alternate ascp path use option `ascp_path` (`--ascp-path=`)

For a permanent change, the command `config ascp use` sets the same parameter for the global default.

Using a POSIX shell:

```bash
ascli config ascp use @path:'~/Applications/Aspera CLI/bin/ascp'
```

```output
ascp version: 4.0.0.182279
Updated: global_common_defaults: ascp_path <- /Users/laurent/Applications/Aspera CLI/bin/ascp
Saved to default global preset global_common_defaults
```

Windows:

```bash
ascli config ascp use C:\Users\admin\.aspera\ascli\sdk\ascp.exe
```

```output
ascp version: 4.0.0.182279
Updated: global_common_defaults: ascp_path <- C:\Users\admin\.aspera\ascli\sdk\ascp.exe
Saved to default global preset global_common_defaults
```

If the path has spaces, read section: [Shell and Command line parsing](#parsing).

#### List locally installed Aspera Transfer products

Locally installed Aspera products can be listed with:

```bash
ascli config ascp products list
```

```output
:.........................................:................................................:
:                  name                   :                    app_root                    :
:.........................................:................................................:
: Aspera Connect                          : /Users/laurent/Applications/Aspera Connect.app :
: IBM Aspera CLI                          : /Users/laurent/Applications/Aspera CLI         :
: IBM Aspera High-Speed Transfer Endpoint : /Library/Aspera                                :
: Aspera Drive                            : /Applications/Aspera Drive.app                 :
:.........................................:................................................:
```

#### Selection of local client for `ascp` for [`direct`](#agt_direct) agent

If no ascp is selected, this is equivalent to using option: `--use-product=FIRST`.

Using the option use_product finds the ascp binary of the selected product.

To permanently use the ascp of a product:

```bash
ascli config ascp products use 'Aspera Connect'
saved to default global preset /Users/laurent/Applications/Aspera Connect.app/Contents/Resources/ascp
```

#### Installation of Connect Client on command line

```bash
ascli config ascp connect list
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
ascli config ascp connect version 'Aspera Connect for Mac Intel' list
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
ascli config ascp connect version 'Aspera Connect for Mac Intel' download enclosure --to-folder=.
```

```output
Time: 00:00:02 ======================================================================= 100% 27766 KB/sec Time: 00:00:02
Downloaded: IBMAsperaConnectInstaller-3.11.2.63.dmg
```

### <a id="agents"></a>Transfer Agents

Some of the actions on Aspera Applications lead to file transfers (upload and download) using the FASP protocol (`ascp`).

When a transfer needs to be started, a [*transfer-spec*](#transferspec) has been internally prepared.
This [*transfer-spec*](#transferspec) will be executed by a transfer client, here called "Transfer Agent".

There are currently 3 agents:

* [`direct`](#agt_direct) : a local execution of `ascp`
* [`connect`](#agt_connect) : use of a local Connect Client
* [`node`](#agt_node) : use of an Aspera Transfer Node (potentially *remote*).
* [`httpgw`](#agt_httpgw) : use of an Aspera HTTP Gateway
* [`trsdk`](#agt_trsdk) : use of Aspera Transfer SDK

Note that all transfer operation are seen from the point of view of the agent.
For instance, a node agent making an "upload", or "package send" operation,
will effectively push files to the related server from the agent node.

`ascli` standardizes on the use of a [*transfer-spec*](#transferspec) instead of *raw* ascp options to provide parameters for a transfer session, as a common method for those three Transfer Agents.

#### <a id="agt_direct"></a>Direct

The `direct` agent directly executes a local ascp.
This is the default agent for `ascli`.
This is equivalent to option `--transfer=direct`.
`ascli` will detect locally installed Aspera products, including SDK, and use `ascp` from that component.
Refer to section [FASP](#client).

The `transfer_info` option accepts the following optional parameters to control multi-session, Web Socket Session and Resume policy:

<table>
<tr><th>Name</th><th>Type</th><th>Description</th></tr>
<tr><td>wss</td><td>Bool</td><td>Web Socket Session<br/>Enable use of web socket session in case it is available<br/>Default: false</td></tr>
<tr><td>spawn_timeout_sec</td><td>Float</td><td>Multi session<br/>Verification time that ascp is running<br/>Default: 3</td></tr>
<tr><td>spawn_delay_sec</td><td>Float</td><td>Multi session<br/>Delay between startup of sessions<br/>Default: 2</td></tr>
<tr><td>multi_incr_udp</td><td>Bool</td><td>Multi Session<br/>Increment UDP port on multi-session<br/>If true, each session will have a different UDP port starting at `fasp_port` (or default 33001)<br/>Else, each session will use `fasp_port` (or `ascp` default)<br/>Default: true</td></tr>
<tr><td>resume</td><td>Hash</td><td>Resume<br/>parameters<br/>See below</td></tr>
<tr><td>resume.iter_max</td><td>int</td><td>Resume<br/>Max number of retry on error<br/>Default: 7</td></tr>
<tr><td>resume.sleep_initial</td><td>int</td><td>Resume<br/>First Sleep before retry<br/>Default: 2</td></tr>
<tr><td>resume.sleep_factor</td><td>int</td><td>Resume<br/>Multiplier of sleep period between attempts<br/>Default: 2</td></tr>
<tr><td>resume.sleep_max</td><td>int</td><td>Resume<br/>Default: 60</td></tr>
</table>

In case of transfer interruption, the agent will **resume** a transfer up to `iter_max` time.
Sleep between iterations is:

```bash
max( sleep_max , sleep_initial * sleep_factor ^ (iter_index-1) )
```

Some transfer errors are considered "retryable" (e.g. timeout) and some other not (e.g. wrong password).
The list of known protocol errors and retry level can be listed:

```bash
ascli config ascp errors
```

Examples:

```javascript
ascli ... --transfer-info=@json:'{"wss":true,"resume":{"iter_max":20}}'
ascli ... --transfer-info=@json:'{"spawn_delay_sec":2.5,"multi_incr_udp":false}'
```

Note that the `direct` agent supports additional `transfer_spec` parameters starting with `EX_` (extended).
In particular the field, `EX_ascp_args` which is a list of additional command line options to `ascp`.

This can be useful to activate logging using option `-L` of ascp.
For example the option `--ts=@json:'{"EX_ascp_args":["-DDL-"]}'` will activate debug level 2 for `ascp` (`DD`), and display those logs on the terminal (`-`).
This is useful if the transfer fails.
To store ascp logs in file `aspera-scp-transfer.log` in a folder, use `--ts=@json:'{"EX_ascp_args":["-L","/path/to/folder"]}'`.

> Implementation note: when transfer agent [`direct`](#agt_direct) is used, the list of files to transfer is provided to `ascp` using either `--file-list` or `--file-pair-list` and a file list (or pair) file generated in a temporary folder. (unless `--file-list` or `--file-pair-list` is provided in option `ts` in `EX_ascp_args`).

In addition to standard methods described in section [File List](#file_list), it is possible to specify the list of file using those additional methods:

* Using the pseudo [*transfer-spec*](#transferspec) parameter `EX_file_list`

```javascript
--sources=@ts --ts=@json:'{"EX_file_list":"filelist.txt"}'
```

* Using the pseudo [*transfer-spec*](#transferspec) parameter `EX_ascp_args`

```javascript
--sources=@ts --ts=@json:'{"EX_ascp_args":["--file-list","myfilelist"]}'
```

> File lists is shown here, there are also similar options for file pair lists.

> Those 2 additional methods avoid the creation of a copy of the file list: if the standard options `--sources=@lines:@file:... --src-type=...` are used, then the file is list read and parsed, and a new file list is created in a temporary folder.

> Those methods have limitations: they apply **only** to the [`direct`](#agt_direct) transfer agent (i.e. local `ascp`) and not for Aspera on Cloud.

#### <a id="agt_connect"></a>IBM Aspera Connect Client GUI

By specifying option: `--transfer=connect`, `ascli` will start transfers using the locally installed Aspera Connect Client. There are no option for `transfer_info`.

#### <a id="agt_node"></a>Aspera Node API : Node to node transfers

By specifying option: `--transfer=node`, the CLI will start transfers in an Aspera
Transfer Server using the Node API, either on a local or remote node.
Parameters provided in option `transfer_info` are:

<table>
<tr><th>Name</th><th>Type</th><th>Description</th></tr>
<tr><td>url</td><td>string</td><td>URL of the node API</br>Mandatory</td></tr>
<tr><td>username</td><td>string</td><td>node api user or access key</br>Mandatory</td></tr>
<tr><td>password</td><td>string</td><td>password, secret or bearer token</br>Mandatory</td></tr>
<tr><td>root_id</td><td>string</td><td>password or secret</br>Mandatory only for bearer token</td></tr>
</table>

Like any other option, `transfer_info` can get its value from a pre-configured [option preset](#lprt) :
`--transfer-info=@preset:<psetname>` or be specified using the extended value syntax :
`--transfer-info=@json:'{"url":"https://...","username":"theuser","password":"_pass_here_"}'`

If `transfer_info` is not specified and a default node has been configured (name in `node` for section `default`) then this node is used by default.

If the `password` value begins with `Bearer` then the `username` is expected to be an access key and the parameter `root_id` is mandatory and specifies the root file id on the node. It can be either the access key's root file id, or any authorized file id underneath it.

#### <a id="agt_httpgw"></a>HTTP Gateway

If it possible to send using a HTTP gateway, in case FASP is not allowed.

Parameters provided in option `transfer_info` are:

<table>
<tr><th>Name</th><th>Type</th><th>Description</th></tr>
<tr><td>url</td><td>string</td><td>URL of the HTTP GW</br>Mandatory</td></tr>
<tr><td>upload_bar_refresh_sec</td><td>float</td><td>Refresh rate for upload progress bar</td></tr>
<tr><td>upload_chunksize</td><td>int</td><td>Size in bytes of chunks for upload</td></tr>
</table>

Example:

```javascript
ascli faspex package recv --id=323 --transfer=httpgw --transfer-info=@json:'{"url":"https://asperagw.example.com:9443/aspera/http-gwy/v1"}'
```

> The gateway only supports transfers authorized with a token.

#### <a id="agt_trsdk"></a>Transfer SDK

Another possibility is to use the Transfer SDK daemon (asperatransferd).

By default it will listen on local port `55002` on `127.0.0.1`.

The gem `grpc` was removed from dependencies, as it requires compilation of a native part. So, to use the Transfer SDK you should install this gem:

```bash
gem install grpc
```

On Windows the compilation may fail for various reasons (3.1.1):

* `cannot find -lx64-ucrt-ruby310`
   &rarr; copy the file `[Ruby main dir]\lib\libx64-ucrt-ruby310.dll.a` to `[Ruby main dir]\lib\libx64-ucrt-ruby310.a` (remove the dll extension)
* `conflicting types for 'gettimeofday'`
  &rarr; edit the file `[Ruby main dir]/include/ruby-[version]/ruby/win32.h` and change the signature of `gettimeofday` to `gettimeofday(struct timeval *, void *)` ,i.e. change `struct timezone` to `void`

### <a id="transferspec"></a>Transfer Specification

Some commands lead to file transfer (upload/download), all parameters necessary for this transfer
is described in a [*transfer-spec*](#transferspec) (Transfer Specification), such as:

* server address
* transfer user name
* credentials
* file list
* etc...

`ascli` builds a default [*transfer-spec*](#transferspec) internally, so it is not necessary to provide additional parameters on the command line for this transfer.

If needed, it is possible to modify or add any of the supported [*transfer-spec*](#transferspec) parameter using the `ts` option. The `ts` option accepts a [Structured Value](#native) containing one or several [*transfer-spec*](#transferspec) parameters. Multiple `ts` options on command line are cumulative.

It is possible to specify ascp options when the `transfer` option is set to [`direct`](#agt_direct) using the special [*transfer-spec*](#transferspec) parameter: `EX_ascp_args`. Example: `--ts=@json:'{"EX_ascp_args":["-l","100m"]}'`. This is especially useful for ascp command line parameters not supported yet in the transfer spec.

The use of a [*transfer-spec*](#transferspec) instead of `ascp` parameters has the advantage of:

* common to all [Transfer Agent](#agents)
* not dependent on command line limitations (special characters...)

A [*transfer-spec*](#transferspec) is a Hash table, so it is described on the command line with the [Extended Value Syntax](#extended).

### <a id="transferparams"></a>Transfer Parameters

All standard [*transfer-spec*](#transferspec) parameters can be specified.
[*transfer-spec*](#transferspec) can also be saved/overridden in the config file.

References:

* [Aspera Node API Documentation](https://developer.ibm.com/apis/catalog?search=%22aspera%20node%20api%22)&rarr;/opt/transfers
* [Aspera Transfer SDK Documentation](https://developer.ibm.com/apis/catalog?search=%22aspera%20transfer%20sdk%22)&rarr;Guides&rarr;API Ref&rarr;Transfer Spec V1
* [Aspera Connect SDK](https://d3gcli72yxqn2z.cloudfront.net/connect/v4/asperaweb-4.js) &rarr; search `The parameters for starting a transfer.`

Parameters can be displayed with commands:

```javascript
ascli config ascp spec
ascli config ascp spec --select=@json:'{"d":"Y"}' --fields=-d,n,c
```

Columns:

* D=Direct (local `ascp` execution)
* N=Node API
* C=Connect Client

`ascp` argument or environment variable is provided in description.

Fields with EX_ prefix are extensions to transfer agent [`direct`](#agt_direct). (only in `ascli`).

<table><tr><th>Field</th><th>Type</th><th>D</th><th>N</th><th>C</th><th>Description</th></tr>
<tr><td>EX_ascp_args</td><td>array</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Add native command line arguments to ascp</td></tr>
<tr><td>EX_at_rest_password</td><td>string</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>DEPRECATED: Prefer to use standard parameter: content_protection_password<br/>(env:ASPERA_SCP_FILEPASS)</td></tr>
<tr><td>EX_file_list</td><td>string</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>source file list</td></tr>
<tr><td>EX_file_pair_list</td><td>string</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>source file pair list</td></tr>
<tr><td>EX_http_proxy_url</td><td>string</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Specify the proxy server address used by HTTP Fallback<br/>(-x {string})</td></tr>
<tr><td>EX_http_transfer_jpeg</td><td>int</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>HTTP transfers as JPEG file<br/>(-j {int})</td></tr>
<tr><td>EX_license_text</td><td>string</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>License file text override.<br/>By default ascp looks for license file near executable.<br/>(env:ASPERA_SCP_LICENSE)</td></tr>
<tr><td>EX_no_read</td><td>bool</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>no read source<br/>(--no-read)</td></tr>
<tr><td>EX_no_write</td><td>bool</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>no write on destination<br/>(--no-write)</td></tr>
<tr><td>EX_proxy_password</td><td>string</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Password used for Aspera proxy server authentication.<br/>May be overridden by password in URL EX_fasp_proxy_url.<br/>(env:ASPERA_PROXY_PASS)</td></tr>
<tr><td>EX_ssh_key_paths</td><td>array</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Use public key authentication for SSH and specify the private key file paths<br/>(-i {array})</td></tr>
<tr><td>apply_local_docroot</td><td>bool</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>(--apply-local-docroot)</td></tr>
<tr><td>authentication</td><td>string</td><td>&nbsp;</td><td>&nbsp;</td><td>Y</td><td>value=token for SSH bypass keys, else password asked if not provided.</td></tr>
<tr><td>cipher</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>In transit encryption type.<br/>Allowed values: none, aes-128, aes-192, aes-256, aes-128-cfb, aes-192-cfb, aes-256-cfb, aes-128-gcm, aes-192-gcm, aes-256-gcm<br/>(-c (conversion){enum})</td></tr>
<tr><td>cipher_allowed</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>returned by node API. Valid literals include "aes-128" and "none".</td></tr>
<tr><td>content_protection</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Enable client-side encryption at rest. (CSEAR, content protection)<br/>Allowed values: encrypt, decrypt<br/>(--file-crypt {enum})</td></tr>
<tr><td>content_protection_password</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Specifies CSEAR password. (content protection)<br/>(env:ASPERA_SCP_FILEPASS)</td></tr>
<tr><td>cookie</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Metadata for transfer specified by application<br/>(env:ASPERA_SCP_COOKIE)</td></tr>
<tr><td>create_dir</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>Specifies whether to create new directories.<br/>(-d)</td></tr>
<tr><td>delete_before_transfer</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>Before transfer, delete files that exist at the destination but not at the source.<br/>The source and destination arguments must be directories that have matching names.<br/>Objects on the destination that have the same name but different type or size as objects<br/>on the source are not deleted.<br/>(--delete-before-transfer)</td></tr>
<tr><td>delete_source</td><td>bool</td><td>Y</td><td>Y</td><td>&nbsp;</td><td>Remove SRC files after transfer success<br/>(--remove-after-transfer)</td></tr>
<tr><td>destination_root</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Destination root directory.</td></tr>
<tr><td>dgram_size</td><td>int</td><td>Y</td><td>Y</td><td>Y</td><td>UDP datagram size in bytes<br/>(-Z {int})</td></tr>
<tr><td>direction</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Direction of transfer (on client side)<br/>Allowed values: send, receive<br/>(--mode (conversion){enum})</td></tr>
<tr><td>exclude_newer_than</td><td>int</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>skip src files with mtime > arg<br/>(--exclude-newer-than {int})</td></tr>
<tr><td>exclude_older_than</td><td>int</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>skip src files with mtime < arg<br/>(--exclude-older-than {int})</td></tr>
<tr><td>fasp_port</td><td>int</td><td>Y</td><td>Y</td><td>Y</td><td>Specifies fasp (UDP) port.<br/>(-O {int})</td></tr>
<tr><td>file_checksum</td><td>string</td><td>Y</td><td>Y</td><td>&nbsp;</td><td>Enable checksum reporting for transferred files by specifying the hash to use.<br/>Allowed values: sha-512, sha-384, sha-256, sha1, md5, none</td></tr>
<tr><td>http_fallback</td><td>bool<br/>string</td><td>Y</td><td>Y</td><td>Y</td><td>When true(1), attempts to perform an HTTP transfer if a FASP transfer cannot be performed.<br/>(-y (conversion){bool}|{string})</td></tr>
<tr><td>http_fallback_port</td><td>int</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Specifies http port when no cipher is used<br/>(-t {int})</td></tr>
<tr><td>https_fallback_port</td><td>int</td><td>Y</td><td>Y</td><td>Y</td><td>Specifies https port when cipher is used<br/>(-t {int})</td></tr>
<tr><td>lock_min_rate</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>&nbsp;</td></tr>
<tr><td>lock_min_rate_kbps</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>&nbsp;</td></tr>
<tr><td>lock_rate_policy</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>&nbsp;</td></tr>
<tr><td>lock_target_rate</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>&nbsp;</td></tr>
<tr><td>lock_target_rate_kbps</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>&nbsp;</td></tr>
<tr><td>min_rate_cap_kbps</td><td>int</td><td>Y</td><td>Y</td><td>Y</td><td>&nbsp;</td></tr>
<tr><td>min_rate_kbps</td><td>int</td><td>Y</td><td>Y</td><td>Y</td><td>Set the minimum transfer rate in kilobits per second.<br/>(-m {int})</td></tr>
<tr><td>move_after_transfer</td><td>string</td><td>Y</td><td>Y</td><td>&nbsp;</td><td>The relative path to which the files will be moved after the transfer at the source side. Available as of 3.8.0.<br/>(--move-after-transfer {string})</td></tr>
<tr><td>multi_session</td><td>int</td><td>Y</td><td>Y</td><td>Y</td><td>Use multi-session transfer. max 128.<br/>Each participant on one host needs an independent UDP (-O) port.<br/>Large files are split between sessions only when transferring with resume_policy=none.<br/></td></tr>
<tr><td>multi_session_threshold</td><td>int</td><td>Y</td><td>Y</td><td>&nbsp;</td><td>Split files across multiple ascp sessions if their size in bytes is greater than or equal to the specified value.<br/>(0=no file is split)<br/>(--multi-session-threshold {int})</td></tr>
<tr><td>overwrite</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Overwrite destination files with the source files of the same name.<br/>Allowed values: never, always, diff, older, diff+older<br/>(--overwrite {enum})</td></tr>
<tr><td>password</td><td>string</td><td>&nbsp;</td><td>Y</td><td>&nbsp;</td><td>Password for local Windows user when transfer user associated with node api user is not the same as the one running asperanoded.<br/>Allows impersonating the transfer user and have access to resources (e.g. network shares).<br/>Windows only, node api only.</td></tr>
<tr><td>paths</td><td>array</td><td>Y</td><td>Y</td><td>Y</td><td>Array of path to the source (required) and a path to the destination (optional).</td></tr>
<tr><td>precalculate_job_size</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>Specifies whether to precalculate the job size.<br/>(--precalculate-job-size)</td></tr>
<tr><td>preserve_access_time</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>(--preserve-access-time)</td></tr>
<tr><td>preserve_acls</td><td>string</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Preserve access control lists.<br/>Allowed values: none, native, metafile<br/>(--preserve-acls {enum})</td></tr>
<tr><td>preserve_creation_time</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>(--preserve-creation-time)</td></tr>
<tr><td>preserve_file_owner_gid</td><td>bool</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Preserve the group ID for a file owner<br/>(--preserve-file-owner-gid)</td></tr>
<tr><td>preserve_file_owner_uid</td><td>bool</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Preserve the user ID for a file owner<br/>(--preserve-file-owner-uid)</td></tr>
<tr><td>preserve_modification_time</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>(--preserve-modification-time)</td></tr>
<tr><td>preserve_remote_acls</td><td>string</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Preserve remote access control lists.<br/>Allowed values: none, native, metafile<br/>(--remote-preserve-acls {enum})</td></tr>
<tr><td>preserve_source_access_time</td><td>bool</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Preserve the time logged for when the source file was accessed<br/>(--preserve-source-access-time)</td></tr>
<tr><td>preserve_times</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>(--preserve-times)</td></tr>
<tr><td>proxy</td><td>string</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Specify the address of the Aspera high-speed proxy server.<br/>dnat(s)://[user[:password]@]server:port<br/>Default ports for DNAT and DNATS protocols are 9091 and 9092.<br/>Password, if specified here, overrides the value of environment variable ASPERA_PROXY_PASS.<br/>(--proxy {string})</td></tr>
<tr><td>rate_policy</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>The transfer rate policy to use when sharing bandwidth.<br/>Allowed values: low, fair, high, fixed<br/>(--policy {enum})</td></tr>
<tr><td>rate_policy_allowed</td><td>string</td><td>&nbsp;</td><td>&nbsp;</td><td>Y</td><td>Specifies most aggressive rate policy that is allowed.<br/>Returned by node API.<br/>Allowed values: low, fair, high, fixed</td></tr>
<tr><td>remote_host</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>IP or fully qualified domain name of the remote server<br/>(--host {string})</td></tr>
<tr><td>remote_password</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>SSH session password<br/>(env:ASPERA_SCP_PASS)</td></tr>
<tr><td>remote_user</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Remote user. Default value is "xfer" on node or connect.<br/>(--user {string})</td></tr>
<tr><td>remove_after_transfer</td><td>bool</td><td>Y</td><td>Y</td><td>&nbsp;</td><td>Remove SRC files after transfer success<br/>(--remove-after-transfer)</td></tr>
<tr><td>remove_empty_directories</td><td>bool</td><td>Y</td><td>Y</td><td>&nbsp;</td><td>Specifies whether to remove empty directories.<br/>(--remove-empty-directories)</td></tr>
<tr><td>remove_empty_source_directory</td><td>bool</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Remove empty source subdirectories and remove the source directory itself, if empty<br/>(--remove-empty-source-directory)</td></tr>
<tr><td>remove_skipped</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>Must also have remove_after_transfer set to true, Defaults to false, if true, skipped files will be removed as well.<br/>(--remove-skipped)</td></tr>
<tr><td>resume_policy</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>If a transfer is interrupted or fails to finish, resume without re-transferring the whole files.<br/>Allowed values: none, attrs, sparse_csum, full_csum<br/>(-k (conversion){enum})</td></tr>
<tr><td>retry_duration</td><td>string<br/>int</td><td>&nbsp;</td><td>Y</td><td>Y</td><td>Specifies how long to wait before retrying transfer. (e.g. "5min")</td></tr>
<tr><td>source_root</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Path to be prepended to each source path.<br/>This is either a conventional path or it can be a URI but only if there is no root defined.<br/>(--source-prefix64 (conversion){string})</td></tr>
<tr><td>source_root_id</td><td>string</td><td>&nbsp;</td><td>Y</td><td>&nbsp;</td><td>The file ID of the source root directory. Required when using Bearer token auth for the source node.</td></tr>
<tr><td>src_base</td><td>string</td><td>Y</td><td>Y</td><td>&nbsp;</td><td>Specify the prefix to be stripped off from each source object.<br/>The remaining portion of the source path is kept intact at the destination.<br/>Special care must be taken when used with cloud storage.<br/>(--src-base64 (conversion){string})</td></tr>
<tr><td>ssh_port</td><td>int</td><td>Y</td><td>Y</td><td>Y</td><td>Specifies SSH (TCP) port. Default: local:22, other:33001<br/>(-P {int})</td></tr>
<tr><td>ssh_private_key</td><td>string</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Private key used for SSH authentication.<br/>Shall look like: -----BEGIN RSA PRIV4TE KEY-----\nMII...<br/>Note the JSON encoding: \n for newlines.<br/>(env:ASPERA_SCP_KEY)</td></tr>
<tr><td>ssh_private_key_passphrase</td><td>string</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>The passphrase associated with the transfer user's SSH private key. Available as of 3.7.2.<br/>(env:ASPERA_SCP_PASS)</td></tr>
<tr><td>sshfp</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Check it against server SSH host key fingerprint<br/>(--check-sshfp {string})</td></tr>
<tr><td>symlink_policy</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Handle source side symbolic links<br/>Allowed values: follow, copy, copy+force, skip<br/>(--symbolic-links {enum})</td></tr>
<tr><td>tags</td><td>hash</td><td>Y</td><td>Y</td><td>Y</td><td>Metadata for transfer as JSON<br/>(--tags64 (conversion){hash})</td></tr>
<tr><td>target_rate_cap_kbps</td><td>int</td><td>&nbsp;</td><td>&nbsp;</td><td>Y</td><td>Returned by upload/download_setup node API.</td></tr>
<tr><td>target_rate_kbps</td><td>int</td><td>Y</td><td>Y</td><td>Y</td><td>Specifies desired speed for the transfer.<br/>(-l {int})</td></tr>
<tr><td>target_rate_percentage</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>&nbsp;</td></tr>
<tr><td>title</td><td>string</td><td>&nbsp;</td><td>Y</td><td>Y</td><td>Title of the transfer</td></tr>
<tr><td>token</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Authorization token: Bearer, Basic or ATM (Also arg -W)<br/>(env:ASPERA_SCP_TOKEN)</td></tr>
<tr><td>use_ascp4</td><td>bool</td><td>Y</td><td>Y</td><td>&nbsp;</td><td>specify version of protocol</td></tr>
<tr><td>wss_enabled</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>&nbsp;</td></tr>
<tr><td>wss_port</td><td>int</td><td>Y</td><td>Y</td><td>Y</td><td>TCP port used for websocket service feed.</td></tr>
</table>

#### Destination folder for transfers

The destination folder is set by `ascli` by default to:

* `.` for downloads
* `/` for uploads

It is specified by the [*transfer-spec*](#transferspec) parameter `destination_root`.
As such, it can be modified with option: `--ts=@json:'{"destination_root":"<path>"}'`.
The option `to_folder` provides an equivalent and convenient way to change this parameter:
`--to-folder=<path>` .

#### <a id="file_list"></a>List of files for transfers

When uploading, downloading or sending files, the user must specify the list of files to transfer.

By default the list of files to transfer is simply provided on the command line.

The list of (source) files to transfer is specified by (extended value) option `sources` (default: `@args`).
The list is either simply the list of source files, or a combined source/destination list (see below) depending on value of option `src_type` (default: `list`).

In `ascli`, all transfer parameters, including file list, are provided to the transfer agent in a [*transfer-spec*](#transferspec) so that execution of a transfer is independent of the transfer agent (direct, connect, node, transfer sdk...).
So, eventually, the list of files to transfer is provided to the transfer agent using the [*transfer-spec*](#transferspec) field: `"paths"` which is a list (array) of pairs of `"source"` (mandatory) and `"destination"` (optional).
The `sources` and `src_type` options provide convenient ways to populate the transfer spec with the source file list.

Possible values for option `sources` are:

* `@args` : (default) the list of files (or file pair) is directly provided on the command line (after commands): unused arguments (not starting with `-`) are considered as source files.
So, by default, the list of files to transfer will be simply specified on the command line. Example:

  ```bash
  ascli server upload ~/first.file secondfile
  ```

  This is the same as (with default values):

  ```bash
  ascli server upload --sources=@args --src-type=list ~/mysample.file secondfile
  ```

* an [Extended Value](#extended) with type **Array of String**

  > Note: extended values can be tested with the command `conf echo`

  Examples:

  * Using extended value

    Create the file list:

    ```bash
    echo ~/mysample.file > myfilelist.txt
    echo secondfile >> myfilelist.txt
    ```

    Use the file list: one path per line:

    ```ruby
    --sources=@lines:@file:myfilelist.txt
    ```

  * Using JSON array

    ```javascript
    --sources=@json:'["file1","file2"]'
    ```

  * Using STDIN, one path per line

    ```bash
    --sources=@lines:@stdin:
    ```

  * Using ruby code (one path per line in file)

    ```ruby
    --sources=@ruby:'File.read("myfilelist.txt").split("\n")'
    ```

* `@ts` : the user provides the list of files directly in the `paths` field of transfer spec (option `ts`).
Examples:

  * Using transfer spec

  ```javascript
  --sources=@ts --ts=@json:'{"paths":[{"source":"file1"},{"source":"file2"}]}'
  ```

The option `src_type` allows specifying if the list specified in option `sources` is a simple file list or if it is a file pair list.

> Note: Option `src_type` is not used if option `sources` is set to `@ts`

Supported values for `src_type` are:

* `list` : (default) the path of destination is the same as source and each entry is a source file path
* `pair` : the first element is the first source, the second element is the first destination, and so on.

Example: Source file `200KB.1` is renamed `sample1` on destination:

```bash
ascli server upload --src-type=pair ~/Documents/Samples/200KB.1 /Upload/sample1
```

> Note there are some specific rules to specify file list when using "Aspera on Cloud", refer to the AoC plugin section.

#### <a id="multisession"></a>Support of multi-session

Multi session, i.e. starting a transfer of a file set using multiple sessions (one ascp process per session) is supported on "direct" and "node" agents, not yet on connect.

* when agent=node :

```javascript
--ts=@json:'{"multi_session":10,"multi_session_threshold":1}'
```

Multi-session is directly supported by the node daemon.

* when agent=direct :

```javascript
--ts=@json:'{"multi_session":5,"multi_session_threshold":1,"resume_policy":"none"}'
```

Note: `resume_policy` set to `attr` may cause problems: `none` or `sparse_csum` shall be preferred.

`ascli` starts multiple `ascp` for Multi-session using `direct` agent.

When multi-session is used, one separate UDP port is used per session (refer to `ascp` manual page).

#### Content protection

Also known as Client-side encryption at reast (CSEAR), content protection allows a client to send files to a server
which will store them encrypted (upload), and decrypt files as they are being downloaded from a server, both
using a passphrase, only known by users sharing files. Files stay encrypted on server side.

activating CSEAR consists in using transfer spec parameters:

* `content_protection` : activate encryption (`encrypt` for upload) or decryption (`decrypt` for download)
* `content_protection_password` : the passphrase to be used.

Example: parameter to download a faspex package and decrypt on the fly

```javascript
--ts=@json:'{"content_protection":"decrypt","content_protection_password":"_pass_here_"}'
```

Note that up to version 4.6.0, the following parameters should be used for agent `direct`:

```javascript
--ts=@json:'{"EX_ascp_args":["--file-crypt=decrypt"],"EX_at_rest_password":"_secret_here_"}'
```

#### Transfer Spec Examples

* Change target rate

```javascript
--ts=@json:'{"target_rate_kbps":500000}'
```

* Override the FASP SSH port to a specific TCP port:

```javascript
--ts=@json:'{"ssh_port":33002}'
```

* Force http fallback mode:

```javascript
--ts=@json:'{"http_fallback":"force"}'
```

* Activate progress when not activated by default on server

```javascript
--ts=@json:'{"precalculate_job_size":true}'
```

### <a id="scheduling"></a>Lock for exclusive execution

In some conditions, it may be desirable to ensure that `ascli` is not executed several times in parallel.

For instance when `ascli` is executed automatically on a schedule basis, one generally desire that a new execution is not started if a previous execution is still running because an on-going operation may last longer than the scheduling period:

* Executing instances may pile-up and kill the system
* The same file may be transferred by multiple instances at the same time.
* `preview` may generate the same files in multiple instances.

Usually the OS native scheduler already provides some sort of protection against parallel execution:

* The Windows scheduler does this by default
* Linux cron can leverage the utility [`flock`](https://linux.die.net/man/1/flock) to do the same:

```bash
/usr/bin/flock -w 0 /var/cron.lock ascli ...
```

`ascli` natively supports a locking mechanism with option `lock_port`.
(Technically, this opens a local TCP server port, and fails if this port is already used, providing a local lock. Lock is released when process exits).

Example:

Run this same command in two separate terminals within less than 30 seconds:

```bash
ascli config echo @ruby:'sleep(30)' --lock-port=12345
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
ascli conf ascp info
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

This is an extract of the man page of `ascp`. This feature is a feature of `ascp`, not `ascli`.

This adapter can be used to simulate a file or a directory.

To send uninitialized data in place of an actual source file, the source file is replaced with an argument of the form:

```bash
faux:///filename?filesize
```

where:

* `filename` is the name that will be assigned to the file on the destination
* `filesize` is the number of bytes that will be sent (in decimal).

Note: characters `?` and `&` are shell special characters (wildcard and backround), so `faux` file specification on command line should be protected (using quotes or `\`). If not, the shell may give error: `no matches found` or equivalent.

For all sizes, a suffix can be added (case insensitive) to the size: k,m,g,t,p,e (values are power of 2, e.g. 1M is 2<sup>20</sup>, i.e. 1 mebibyte, not megabyte). The maximum allowed value is 8*2<sup>60</sup>. Very large `faux` file sizes (petabyte range and above) will likely fail due to lack of destination storage unless destination is `faux://`.

To send uninitialized data in place of a source directory, the source argument is replaced with an argument of the form:

```bash
faux:///dirname?<arg1>=<val1>&...
```

where:

* `dirname` is the folder name and can contain `/` to specify a subfolder.
* supported arguments are:

| Name   | Type | Description |
|--------|------|-------------|
|count   |int   |mandatory|Number of files<br/>Mandatory|
|file    |string|Basename for files<br>Default: "file"|
|size    |int   |Size of first file.<br>Default: 0|
|inc     |int   |Increment applied to determine next file size<br>Default: 0|
|seq     |enum  |Sequence in determining next file size<br/>Values: random, sequential<br/>Default: sequential|
|buf_init|enum  |How source data is initialized<br/>Option 'none' is not allowed for downloads.<br/>Values:none, zero, random<br/>Default:zero|

The sequence parameter is applied as follows:

* If `seq` is `random` then each file size is:

  * size +/- (inc * rand())
  * Where rand is a random number between 0 and 1
  * Note that file size must not be negative, inc will be set to size if it is greater than size
  * Similarly, overall file size must be less than 8*2<sup>60</sup>. If size + inc is greater, inc will be reduced to limit size + inc to 7*2<sup>60</sup>.

* If `seq` is `sequential` then each file size is:

  * `size + ((fileindex - 1) * inc)`
  * Where first file is index 1
  * So file1 is `size` bytes, file2 is `size + inc` bytes, file3 is `size + inc * 2` bytes, etc.
  * As with `random`, `inc` will be adjusted if `size + (count * inc)` is not less then 8*2<sup>60</sup>.

Filenames generated are of the form: `<file>_<00000 ... count>_<filesize>`

To discard data at the destination, the destination argument is set to `faux://` .

Examples:

* Upload 20 gibibytes of random data to file myfile to directory /Upload

```bash
ascli server upload faux:///myfile\?20g --to-folder=/Upload
```

* Upload a file /tmp/sample but do not save results to disk (no docroot on destination)

```bash
ascli server upload /tmp/sample --to-folder=faux://
```

* Upload a faux directory `mydir` containing 1 million files, sequentially with sizes ranging from 0 to 2 Mebibyte - 2 bytes, with the basename of each file being `testfile` to /Upload

```bash
ascli server upload "faux:///mydir?file=testfile&count=1m&size=0&inc=2&seq=sequential" --to-folder=/Upload
```

### <a id="usage"></a>Usage

```text
ascli -h
NAME
        ascli -- a command line tool for Aspera Applications (v4.10.0)

SYNOPSIS
        ascli COMMANDS [OPTIONS] [ARGS]

DESCRIPTION
        Use Aspera application to perform operations on command line.
        Documentation and examples: https://rubygems.org/gems/aspera-cli
        execute: ascli conf doc
        or visit: https://www.rubydoc.info/gems/aspera-cli
        source repo: https://github.com/IBM/aspera-cli

ENVIRONMENT VARIABLES
        ASCLI_HOME config folder, default: $HOME/.aspera/ascli
        Any option can be set as an environment variable, refer to the manual

COMMANDS
        To list first level commands, execute: ascli
        Note that commands can be written shortened (provided it is unique).

OPTIONS
        Options begin with a '-' (minus), and value is provided on command line.
        Special values are supported beginning with special prefix @pfx:, where pfx is one of:
        base64, json, zlib, ruby, csvt, lines, list, incps, val, file, path, env, uri, stdin, preset
        Dates format is 'DD-MM-YY HH:MM:SS', or 'now' or '-<num>h'

ARGS
        Some commands require mandatory arguments, e.g. a path.

OPTIONS: global
        --interactive=ENUM           use interactive input of missing params: [no], yes
        --ask-options=ENUM           ask even optional options: [no], yes
        --format=ENUM                output format: text, nagios, ruby, json, jsonpp, yaml, [table], csv
        --display=ENUM               output only some information: [info], data, error
        --fields=VALUE               comma separated list of fields, or ALL, or DEF
        --select=VALUE               select only some items in lists, extended value: hash (column, value)
        --table-style=VALUE          table display style
        --flat-hash=ENUM             display hash values as additional keys: no, [yes]
        --transpose-single=ENUM      single object fields output vertically: no, [yes]
        --show-secrets=ENUM          show secrets on command output: [no], yes
    -h, --help                       Show this message.
        --bash-comp                  generate bash completion for command
        --show-config                Display parameters used for the provided action.
    -r, --rest-debug                 more debug for HTTP calls
    -v, --version                    display version
    -w, --warnings                   check for language warnings
        --ui=ENUM                    method to start browser: text, [graphical]
        --log-level=ENUM             Log level: debug, info, [warn], error, fatal, unknown
        --logger=ENUM                log method: [stderr], stdout, syslog
        --lock-port=VALUE            prevent dual execution of a command, e.g. in cron
        --query=VALUE                additional filter for API calls (extended value) (some commands)
        --http-options=VALUE         options for http socket (extended value)
        --insecure=ENUM              do not validate HTTPS certificate: no, [yes]
        --once-only=ENUM             process only new items (some commands): [no], yes
        --log-secrets=ENUM           show passwords in logs: [no], yes
        --cache-tokens=ENUM          save and reuse Oauth tokens: no, [yes]

COMMAND: config
SUBCOMMANDS: list overview id preset open documentation genkey gem plugin flush_tokens echo wizard export_to_cli detect coffee ascp email_test smtp_settings proxy_check folder file check_update initdemo vault
OPTIONS:
        --value=VALUE                extended value for create, update, list filter
        --property=VALUE             name of property to set
        --id=VALUE                   resource identifier (modify,delete,show)
        --bulk=ENUM                  Bulk operation (only some): [no], yes
        --config-file=VALUE          read parameters from file in YAML format, current=/Users/laurent/.ascliconf/config.yaml
    -N, --no-default                 do not load default configuration for plugin
        --override=ENUM              Wizard: override existing value: [no], yes
        --use-generic-client=ENUM    Wizard: AoC: use global or org specific jwt client id: [no], yes
        --default=ENUM               Wizard: set as default configuration for specified plugin (also: update): [no], yes
        --test-mode=ENUM             Wizard: skip private key check step: [no], yes
    -P, --presetVALUE                load the named option preset from current config file
        --pkeypath=VALUE             Wizard: path to private key for JWT
        --ascp-path=VALUE            path to ascp
        --use-product=VALUE          use ascp from specified product
        --smtp=VALUE                 smtp configuration (extended value: hash)
        --fpac=VALUE                 proxy auto configuration script
        --secret=VALUE               default secret
        --secrets=VALUE              secret vault
        --sdk-url=VALUE              URL to get SDK
        --sdk-folder=VALUE           SDK folder path
        --notif-to=VALUE             email recipient for notification of transfers
        --notif-template=VALUE       email ERB template for notification of transfers
        --version-check-days=VALUE   period in days to check new version (zero to disable)
        --plugin-folder=VALUE        folder where to find additional plugins
        --ts=VALUE                   override transfer spec values (Hash, use @json: prefix), current={"create_dir"=>true}
        --local-resume=VALUE         set resume policy (Hash, use @json: prefix), current=
        --to-folder=VALUE            destination folder for transfered files
        --sources=VALUE              how list of transfered files is provided (@args,@ts,Array)
        --src-type=ENUM              type of file list: list, pair
        --transfer=ENUM              type of transfer agent: direct, node, connect, httpgw, trsdk
        --transfer-info=VALUE        parameters for transfer agent
        --progress=ENUM              type of progress bar: none, native, multi


COMMAND: shares
SUBCOMMANDS: health repository admin
OPTIONS:
        --url=VALUE                  URL of application, e.g. https://org.asperafiles.com
        --username=VALUE             username to log in
        --password=VALUE             user's password


COMMAND: node
SUBCOMMANDS: postprocess stream transfer cleanup forward access_key watch_folder service async central asperabrowser basic_token browse upload download api_details health events space info license mkdir mklink mkfile rename delete search
OPTIONS:
        --url=VALUE                  URL of application, e.g. https://org.asperafiles.com
        --username=VALUE             username to log in
        --password=VALUE             user's password
        --validator=VALUE            identifier of validator (optional for central)
        --asperabrowserurl=VALUE     URL for simple aspera web ui
        --sync-name=VALUE            sync name
        --token-type=ENUM            Type of token used for transfers: aspera, basic, hybrid


COMMAND: orchestrator
SUBCOMMANDS: health info workflow plugins processes
OPTIONS:
        --url=VALUE                  URL of application, e.g. https://org.asperafiles.com
        --username=VALUE             username to log in
        --password=VALUE             user's password
        --params=VALUE               parameters hash table, use @json:{"param":"value"}
        --result=VALUE               specify result value as: 'work step:parameter'
        --synchronous=ENUM           work step:parameter expected as result: [no], yes
        --ret-style=ENUM             how return type is requested in api: header, arg, ext
        --auth-style=ENUM            authentication type: arg_pass, head_basic, apikey


COMMAND: bss
SUBCOMMANDS: subscription
OPTIONS:
        --url=VALUE                  URL of application, e.g. https://org.asperafiles.com
        --username=VALUE             username to log in
        --password=VALUE             user's password


COMMAND: alee
SUBCOMMANDS: entitlement
OPTIONS:
        --url=VALUE                  URL of application, e.g. https://org.asperafiles.com
        --username=VALUE             username to log in
        --password=VALUE             user's password


COMMAND: ats
SUBCOMMANDS: cluster access_key api_key aws_trust_policy
OPTIONS:
        --ibm-api-key=VALUE          IBM API key, see https://cloud.ibm.com/iam/apikeys
        --instance=VALUE             ATS instance in ibm cloud
        --ats-key=VALUE              ATS key identifier (ats_xxx)
        --ats-secret=VALUE           ATS key secret
        --params=VALUE               Parameters access key creation (@json:)
        --cloud=VALUE                Cloud provider
        --region=VALUE               Cloud region


COMMAND: faspex5
SUBCOMMANDS: health user bearer_token package admin
OPTIONS:
        --url=VALUE                  URL of application, e.g. https://org.asperafiles.com
        --username=VALUE             username to log in
        --password=VALUE             user's password
        --client-id=VALUE            OAuth client identifier
        --client-secret=VALUE        OAuth client secret
        --redirect-uri=VALUE         OAuth redirect URI for web authentication
        --auth=ENUM                  OAuth type of authentication: web, jwt, boot
        --private-key=VALUE          OAuth JWT RSA private key PEM value (prefix file path with @file:)
        --passphrase=VALUE           RSA private key passphrase


COMMAND: cos
SUBCOMMANDS: node
OPTIONS:
        --bucket=VALUE               Bucket name
        --endpoint=VALUE             Storage endpoint url
        --apikey=VALUE               Storage API key
        --crn=VALUE                  Ressource instance id
        --service-credentials=VALUE  IBM Cloud service credentials (Hash)
        --region=VALUE               Storage region
        --identity=VALUE             Authentication url (https://iam.cloud.ibm.com/identity)


COMMAND: faspex
SUBCOMMANDS: health package source me dropbox v4 address_book login_methods
OPTIONS:
        --url=VALUE                  URL of application, e.g. https://org.asperafiles.com
        --username=VALUE             username to log in
        --password=VALUE             user's password
        --link=VALUE                 public link for specific operation
        --delivery-info=VALUE        package delivery information (extended value)
        --source-name=VALUE          create package from remote source (by name)
        --storage=VALUE              Faspex local storage definition
        --recipient=VALUE            use if recipient is a dropbox (with *)
        --box=ENUM                   package box: inbox, archive, sent


COMMAND: preview
SUBCOMMANDS: scan events trevents check test
OPTIONS:
        --url=VALUE                  URL of application, e.g. https://org.asperafiles.com
        --username=VALUE             username to log in
        --password=VALUE             user's password
        --skip-format=ENUM           skip this preview format (multiple possible): png, mp4
        --folder-reset-cache=ENUM    force detection of generated preview by refresh cache: [no], header, read
        --skip-types=VALUE           skip types in comma separated list
        --previews-folder=VALUE      preview folder in storage root
        --temp-folder=VALUE          path to temp folder
        --skip-folders=VALUE         list of folder to skip
        --case=VALUE                 basename of output for for test
        --scan-path=VALUE            subpath in folder id to start scan in (default=/)
        --scan-id=VALUE              forder id in storage to start scan in, default is access key main folder id
        --mimemagic=ENUM             use Mime type detection of gem mimemagic: [no], yes
        --overwrite=ENUM             when to overwrite result file: always, never, [mtime]
        --file-access=ENUM           how to read and write files in repository: [local], remote
        --max-size=VALUE             maximum size (in bytes) of preview file
        --thumb-vid-scale=VALUE      png: video: size (ffmpeg scale argument)
        --thumb-vid-fraction=VALUE   png: video: time percent position of snapshot
        --thumb-img-size=VALUE       png: non-video: height (and width)
        --thumb-text-font=VALUE      png: plaintext: font to render text with imagemagick convert (identify -list font)
        --video-conversion=ENUM      mp4: method for preview generation: [reencode], blend, clips
        --video-png-conv=ENUM        mp4: method for thumbnail generation: [fixed], animated
        --video-start-sec=VALUE      mp4: start offset (seconds) of video preview
        --video-scale=VALUE          mp4: video scale (ffmpeg)
        --blend-keyframes=VALUE      mp4: blend: # key frames
        --blend-pauseframes=VALUE    mp4: blend: # pause frames
        --blend-transframes=VALUE    mp4: blend: # transition blend frames
        --blend-fps=VALUE            mp4: blend: frame per second
        --clips-count=VALUE          mp4: clips: number of clips
        --clips-length=VALUE         mp4: clips: length in seconds of each clips


COMMAND: sync
SUBCOMMANDS: start admin
OPTIONS:
        --parameters=VALUE           extended value for session set definition
        --session-name=VALUE         name of session to use for admin commands, by default first one


COMMAND: aoc
SUBCOMMANDS: reminder servers bearer_token organization tier_restrictions user packages files admin automation gateway
OPTIONS:
        --url=VALUE                  URL of application, e.g. https://org.asperafiles.com
        --username=VALUE             username to log in
        --password=VALUE             user's password
        --auth=ENUM                  OAuth type of authentication: web, jwt
        --operation=ENUM             client operation for transfers: push, pull
        --client-id=VALUE            OAuth API client identifier in application
        --client-secret=VALUE        OAuth API client passcode
        --redirect-uri=VALUE         OAuth API client redirect URI
        --private-key=VALUE          OAuth JWT RSA private key PEM value (prefix file path with @file:)
        --passphrase=VALUE           RSA private key passphrase
        --workspace=VALUE            name of workspace
        --name=VALUE                 resource name
        --path=VALUE                 file or folder path
        --link=VALUE                 public link to shared resource
        --new-user-option=VALUE      new user creation option for unknown package recipients
        --from-folder=VALUE          share to share source folder
        --scope=VALUE                OAuth scope for AoC API calls
        --default-ports=ENUM         use standard FASP ports or get from node api: [no], yes
        --validate-metadata=ENUM     validate shared inbox metadata: [no], yes


COMMAND: server
SUBCOMMANDS: health download upload browse delete rename ls rm mv du info mkdir cp df md5sum
OPTIONS:
        --url=VALUE                  URL of application, e.g. https://org.asperafiles.com
        --username=VALUE             username to log in
        --password=VALUE             user's password
        --ssh-keys=VALUE             SSH key path list (Array or single)
        --ssh-options=VALUE          SSH options (Hash)


COMMAND: console
SUBCOMMANDS: transfer health
OPTIONS:
        --url=VALUE                  URL of application, e.g. https://org.asperafiles.com
        --username=VALUE             username to log in
        --password=VALUE             user's password
        --filter-from=DATE           only after date
        --filter-to=DATE             only before date


```

Note that actions and parameter values can be written in short form.

### Bulk creation and deletion of resources

Bulk creation and deletion of resources are possible using option `bulk` (yes,no(default)).
In that case, the operation expects an Array of Hash instead of a simple Hash using the [Extended Value Syntax](#extended).
This option is available only for some of the resources: if you need it: try and see if the entities you try to create or delete support this option.

## <a id="aoc"></a>Plugin: Aspera on Cloud

Aspera on Cloud uses the more advanced Oauth v2 mechanism for authentication (HTTP Basic authentication is not supported).

It is recommended to use the wizard to set it up, but manual configuration is also possible.

### <a id="aocwizard"></a>Configuration: using Wizard

`ascli` provides a configuration wizard. Here is a sample invocation :

```text
ascli config wizard
option: url> https://myorg.ibmaspera.com
Detected: Aspera on Cloud
Preparing preset: aoc_myorg
Please provide path to your private RSA key, or empty to generate one:
option: pkeypath>
using existing key:
/Users/myself/.aspera/ascli/aspera_aoc_key
Using global client_id.
option: username> john@example.com
Updating profile with new key
creating new config preset: aoc_myorg
Setting config preset as default for aspera
saving config file
Done.
You can test with:
ascli aoc user profile show
```

Optionally, it is possible to create a new organization-specific "integration", i.e. client application identification.
For this, specify the option: `--use-generic-client=no`.

This will guide you through the steps to create.

If the wizard does not detect the application but you know the application, you can force it using option `value`:

```bash
ascli config wizard --value=aoc
```

### <a id="aocmanual"></a>Configuration: using manual setup

> If you used the wizard (recommended): skip this section.

#### Configuration details

Several types of OAuth authentication are supported:

* JSON Web Token (JWT) : authentication is secured by a private key (recommended for CLI)
* Web based authentication : authentication is made by user using a browser
* URL Token : external users authentication with url tokens (public links)

The authentication method is controlled by option `auth`.

For a *quick start*, follow the mandatory and sufficient section: [API Client Registration](#clientreg) (auth=web) as well as [[option preset](#lprt) for Aspera on Cloud](#aocpreset).

For a more convenient, browser-less, experience follow the [JWT](#jwt) section (auth=jwt) in addition to Client Registration.

In Oauth, a "Bearer" token are generated to authenticate REST calls. Bearer tokens are valid for a period of time.`ascli` saves generated tokens in its configuration folder, tries to re-use them or regenerates them when they have expired.

#### <a id="clientreg"></a>Optional: API Client Registration

If you use the built-in client_id and client_secret, skip this and do not set them in next section.

Else you can use a specific OAuth API client_id, the first step is to declare `ascli` in Aspera on Cloud using the admin interface.

(official documentation: <https://ibmaspera.com/help/admin/organization/registering_an_api_client> ).

Let's start by a registration with web based authentication (auth=web):

* Open a web browser, log to your instance: e.g. `https://myorg.ibmaspera.com/`
* Go to Apps&rarr;Admin&rarr;Organization&rarr;Integrations
* Click "Create New"
  * Client Name: `ascli`
  * Redirect URIs: `http://localhost:12345`
  * Origins: `localhost`
  * uncheck "Prompt users to allow client to access"
  * leave the JWT part for now
* Save

Note: for web based authentication, `ascli` listens on a local port (e.g. specified by the redirect_uri, in this example: 12345), and the browser will provide the OAuth code there. For ``ascli`, HTTP is required, and 12345 is the default port.

Once the client is registered, a "Client ID" and "Secret" are created, these values will be used in the next step.

#### <a id="aocpreset"></a>[option preset](#lprt) for Aspera on Cloud

If you did not use the wizard, you can also manually create a [option preset](#lprt) for `ascli` in its configuration file.

Lets create an [option preset](#lprt) called: `my_aoc_org` using `ask` interactive input (client info from previous step):

```bash
ascli config preset ask my_aoc_org url client_id client_secret
option: url> https://myorg.ibmaspera.com/
option: client_id> my_BJbQiFw
option: client_secret> yFS1mu-crbKuQhGFtfhYuoRW...
updated: my_aoc_org
```

(This can also be done in one line using the command `config preset update my_aoc_org --url=...`)

Define this [option preset](#lprt) as default configuration for the `aspera` plugin:

```bash
ascli config preset set default aoc my_aoc_org
```

Note: Default `auth` method is `web` and default `redirect_uri` is `http://localhost:12345`. Leave those default values.

#### <a id="jwt"></a>Activation of JSON Web Token (JWT) for direct authentication

For a Browser-less, Private Key-based authentication, use the following steps.

In order to use JWT for Aspera on Cloud API client authentication,
a [private/public key pair](#private_key) must be used.

##### API Client JWT activation

If you are not using the built-in client_id and secret, JWT needs to be authorized in Aspera on Cloud. This can be done in two manners:

* Graphically

  * Open a web browser, log to your instance: `https://myorg.ibmaspera.com/`
  * Go to Apps&rarr;Admin&rarr;Organization&rarr;Integrations
  * Click on the previously created application
  * select tab : "JSON Web Token Auth"
  * Modify options if necessary, for instance: activate both options in section "Settings"
  * Click "Save"

* Using command line

```bash
ascli aoc admin res client list
```

```output
:............:...............:
:     id     :  name         :
:............:...............:
: my_BJbQiFw : my-client-app :
:............:...............:
```

```javascript
ascli aoc admin res client modify my_BJbQiFw @json:'{"jwt_grant_enabled":true,"explicit_authorization_required":false}'
```

```output
modified
```

#### User key registration

The public key must be assigned to your user. This can be done in two manners:

##### Graphically

Open the previously generated public key located here: `$HOME/.aspera/ascli/my_private_key.pub`

* Open a web browser, log to your instance: `https://myorg.ibmaspera.com/`
* Click on the user's icon (top right)
* Select "Account Settings"
* Paste the *Public Key* in the "Public Key" section
* Click on "Submit"

##### Using command line

```bash
ascli aoc admin res user list
```

```output
:........:................:
:   id   :      name      :
:........:................:
: 109952 : Tech Support   :
: 109951 : LAURENT MARTIN :
:........:................:
```

```ruby
ascli aoc user profile modify @ruby:'{"public_key"=>File.read(File.expand_path("~/.aspera/ascli/my_private_key.pub"))}'
```

```output
modified
```

Note: the `aspera user info show` command can be used to verify modifications.

#### [option preset](#lprt) modification for JWT

To activate default use of JWT authentication for `ascli` using the [option preset](#lprt), do the following:

* change auth method to JWT
* provide location of private key
* provide username to login as (OAuth "subject")

Execute:

```bash
ascli config preset update my_aoc_org --auth=jwt --private-key=@val:@file:~/.aspera/ascli/my_private_key --username=laurent.martin.aspera@fr.ibm.com
```

Note: the private key argument represents the actual PEM string. In order to read the content from a file, use the `@file:` prefix. But if the @file: argument is used as is, it will read the file and set in the config file. So to keep the "@file" tag in the configuration file, the `@val:` prefix is added.

After this last step, commands do not require web login anymore.

#### <a id="aocfirst"></a>First Use

Once client has been registered and [option preset](#lprt) created: `ascli` can be used:

```bash
ascli aoc files br /
```

```output
Current Workspace: Default Workspace (default)
empty
```

### Calling AoC APIs from command line

The command `ascli aoc bearer` can be used to generate an OAuth token suitable to call any AoC API (use the `scope` option to change the scope, default is `user:all`).
This can be useful when a command is not yet available.

Example:

```bash
curl -s -H "Authorization: $(ascli aoc bearer_token)" 'https://api.ibmaspera.com/api/v1/group_memberships?embed[]=dropbox&embed[]=workspace'|jq -r '.[]|(.workspace.name + " -> " + .dropbox.name)'
```

It is also possible to get the bearer token for node, as user or as admin using:

```bash
ascli aoc files bearer_token_node /
```

```bash
ascli aoc admin res node v4 1234 --secret=_ak_secret_here_ bearer_token_node /
```

### Administration

The `admin` command allows several administrative tasks (and require admin privilege).

It allows actions (create, update, delete) on "resources": users, group, nodes, workspace, etc... with the `admin resource` command.

#### Listing resources

The command `aoc admin res <type> list` lists all entities of given type. It uses paging and multiple requests if necessary.

The option `query` can be optionally used. It expects a Hash using [Extended Value Syntax](#extended), generally provided using: `--query=@json:{...}`. Values are directly sent to the API call and used as a filter on server side.

The following parameters are supported:

* `q` : a filter on name of resource (case insensitive, matches if value is contained in name)
* `sort`: name of fields to sort results, prefix with `-` for reverse order.
* `max` : maximum number of items to retrieve (stop pages when the maximum is passed)
* `pmax` : maximum number of pages to request (stop pages when the maximum is passed)
* `page` : native api parameter, in general do not use (added by
* `per_page` : native api parameter, number of items par api call, in general do not use
* Other specific parameters depending on resource type.

Both `max` and `pmax` are processed internally in `ascli`, not included in actual API call and limit the number of successive pages requested to API. `ascli` will return all values using paging if not provided.

Other parameters are directly sent as parameters to the GET request on API.

`page` and `per_page` are normally added by `ascli` to build successive API calls to get all values if there are more than 1000. (AoC allows a maximum page size of 1000).

`q` and `sort` are available on most resource types.

Other parameters depend on the type of entity (refer to AoC API).

Examples:

* List users with `laurent` in name:

```javascript
ascli aoc admin res user list --query=--query=@json:'{"q":"laurent"}'
```

* List users who logged-in before a date:

```javascript
ascli aoc admin res user list --query=@json:'{"q":"last_login_at:<2018-05-28"}'
```

* List external users and sort in reverse alphabetical order using name:

```javascript
ascli aoc admin res user list --query=@json:'{"member_of_any_workspace":false,"sort":"-name"}'
```

Refer to the AoC API for full list of query parameters, or use the browser in developer mode with the web UI.

Note the option `select` can also be used to further refine selection, refer to [section earlier](#option_select).

#### <a id="res_select"></a>Selecting a resource

Resources are identified by a unique `id`, as well as a unique `name` (case insensitive).

To execute an action on a specific resource, select it using one of those methods:

* *recommended*: give id directly on command line *after the action*: `aoc admin res node show 123`
* give name on command line *after the action*: `aoc admin res node show name abc`
* provide option `id` : `aoc admin res node show --id=123`
* provide option `name` : `aoc admin res node show --name=abc`

#### <a id="res_create"></a>Creating a resource

New resources (users, groups, workspaces, etc..) can be created using a command like:

```bash
ascli aoc admin res create <resource type> @json:'{<...parameters...>}'
```

Some of the API endpoints are described [here](https://developer.ibm.com/apis/catalog?search=%22aspera%20on%20cloud%20api%22). Sadly, not all.

Nevertheless, it is possible to guess the structure of the creation value by simply dumping an existing resource, and use the same parameters for the creation.

```bash
ascli aoc admin res group show 12345 --format=json
```

```json
{"created_at":"2018-07-24T21:46:39.000Z","description":null,"id":"12345","manager":false,"name":"A8Demo WS1","owner":false,"queued_operation_count":0,"running_operation_count":0,"stopped_operation_count":0,"updated_at":"2018-07-24T21:46:39.000Z","saml_group":false,"saml_group_dn":null,"system_group":true,"system_group_type":"workspace_members"}
```

Remove the parameters that are either obviously added by the system: `id`, `created_at`, `updated_at` or optional.

And then craft your command:

```bash
ascli aoc admin res group create @json:'{"description":"test to delete","name":"test 1 to delete","saml_group":false}'
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

Well, remove the offending parameters and try again.

Note that some properties that are shown in the web UI, such as membership, are not listed directly in the resource, but instead another resource is created to link a user and its group: `group_membership`

#### Access Key secrets

In order to access some administrative actions on "nodes" (in fact, access keys), the associated secret is required.
It is usually provided using the `secret` option.
For example in a command like:

```bash
ascli aoc admin res node --id=123 --secret="secret1" v3 info
```

It is also possible to provide a set of secrets used on a regular basis using the [secret vault](#vault).

#### Activity

The activity app can be queried with:

```bash
ascli aoc admin analytics transfers
```

It can also support filters and send notification using option `notif_to`. a template is defined using option `notif_template` :

`mytemplate.erb`:

```bash
From: <%=from_name%> <<%=from_email%>>
To: <<%=ev['user_email']%>>
Subject: <%=ev['files_completed']%> files received

Dear <%=ev[:user_email.to_s]%>,
We received <%=ev['files_completed']%> files for a total of <%=ev['transferred_bytes']%> bytes, starting with file:
<%=ev['content']%>

Thank you.
```

The environment provided contains the following additional variable:

* ev : all details on the transfer event

Example:

```javascript
ascli aoc admin analytics transfers --once-only=yes --lock-port=12345 \
--query=@json:'{"status":"completed","direction":"receive"}' \
--notif-to=active --notif-template=@file:mytemplate.erb
```

Options:

* `once_only` keep track of last date it was called, so next call will get only new events
* `query` filter (on API call)
* `notify` send an email as specified by template, this could be places in a file with the `@file` modifier.

Note this must not be executed in less than 5 minutes because the analytics interface accepts only a period of time between 5 minutes and 6 months. The period is [date of previous execution]..[now].

#### Transfer: Using specific transfer ports

By default transfer nodes are expected to use ports TCP/UDP 33001. The web UI enforces that.
The option `default_ports` ([yes]/no) allows ascli to retrieve the server ports from an API call (download_setup) which reads the information from `aspera.conf` on the server.

#### Using ATS

Refer to section "Examples" of [ATS](#ats) and substitute command `ats` with `aoc admin ats`.

#### Example: Bulk creation of users

```javascript
ascli aoc admin res user create --bulk=yes @json:'[{"email":"dummyuser1@example.com"},{"email":"dummyuser2@example.com"}]'
```

```output
:.......:.........:
:  id   : status  :
:.......:.........:
: 98398 : created :
: 98399 : created :
:.......:.........:
```

#### Example: Find with filter and delete

```javascript
ascli aoc admin res user list --query='@json:{"q":"dummyuser"}' --fields=id,email
```

```output
:.......:........................:
:  id   :         email          :
:.......:........................:
: 98398 : dummyuser1@example.com :
: 98399 : dummyuser2@example.com :
:.......:........................:
```

```bash
thelist=$(ascli aoc admin res user list --query='@json:{"q":"dummyuser"}' --fields=id --format=json --display=data|jq -cr 'map(.id)')
```

```bash
echo $thelist
```

```javascript
["113501","354061"]
```

```bash
ascli aoc admin res user --bulk=yes --id=@json:"$thelist" delete
```

```output
:.......:.........:
:  id   : status  :
:.......:.........:
: 98398 : deleted :
: 98399 : deleted :
:.......:.........:
```

#### Example: <a id="deactuser"></a>Find deactivated users since more than 2 years

```ruby
ascli aoc admin res user list --query=@ruby:'{"deactivated"=>true,"q"=>"last_login_at:<#{(DateTime.now.to_time.utc-2*365*86400).iso8601}"}'
```

To delete them use the same method as before

#### Example: Display current user's workspaces

```bash
ascli aoc user workspaces list
```

```output
:......:............................:
:  id  :            name            :
:......:............................:
: 16   : Engineering                :
: 17   : Marketing                  :
: 18   : Sales                      :
:......:............................:
```

#### Example: Create a sub access key in a "node"

Creation of a sub-access key is like creation of access key with the following difference: authentication to node API is made with accesskey (master access key) and only the path parameter is provided: it is relative to the storage root of the master key. (id and secret are optional)

```bash
ascli aoc admin resource node --name=_node_name_ --secret=_secret_ v4 access_key create --value=@json:'{"storage":{"path":"/folder1"}}'
```

#### Example: Display transfer events (ops/transfer)

```bash
ascli aoc admin res node --secret=_secret_ v3 transfer list --value=@json:'[["q","*"],["count",5]]'
```

Examples of query (TODO: cleanup):

```javascript
{"q":"type(file_upload OR file_delete OR file_download OR file_rename OR folder_create OR folder_delete OR folder_share OR folder_share_via_public_link)","sort":"-date"}
```

```javascript
{"tag":"aspera.files.package_id=LA8OU3p8w"}
```

#### Example: Display node events (events)

```bash
ascli aoc admin res node --secret=_secret_ v3 events
```

#### Example: Display members of a workspace

```javascript
ascli aoc admin res workspace_membership list --fields=member_type,manager,member.email --query=@json:'{"embed":"member","inherited":false,"workspace_id":11363,"sort":"name"}'
```

```output
:.............:.........:..................................:
: member_type : manager :           member.email           :
:.............:.........:..................................:
: user        : true    : john.curtis@email.com            :
: user        : false   : laurent.martin.aspera@fr.ibm.com :
: user        : false   : jean.dupont@me.com               :
: user        : false   : another.user@example.com         :
: group       : false   :                                  :
: user        : false   : aspera.user@gmail.com            :
:.............:.........:..................................:
```

Other query parameters:

```javascript
{"workspace_membership_through":true,"include_indirect":true}
```

#### Example: <a id="aoc_sample_member"></a>add all members of a workspace to another workspace

a- Get id of first workspace

```bash
WS1='First Workspace'
WS1ID=$(ascli aoc admin res workspace list --query=@json:'{"q":"'"$WS1"'"}' --select=@json:'{"name":"'"$WS1"'"}' --fields=id --format=csv)
```

b- Get id of second workspace

```bash
WS2='Second Workspace'
WS2ID=$(ascli aoc admin res workspace list --query=@json:'{"q":"'"$WS2"'"}' --select=@json:'{"name":"'"$WS2"'"}' --fields=id --format=csv)
```

c- Extract membership information

```bash
ascli aoc admin res workspace_membership list --fields=manager,member_id,member_type,workspace_id --query=@json:'{"workspace_id":'"$WS1ID"'}' --format=jsonpp > ws1_members.json
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
ascli aoc admin res workspace_membership create --bulk=yes @json:@file:ws2_members.json
```

#### Example: Get users who did not log since a date

```javascript
ascli aoc admin res user list --fields=email --query=@json:'{"q":"last_login_at:<2018-05-28"}'
```

```output
:...............................:
:             email             :
:...............................:
: John.curtis@acme.com          :
: Jean.Dupont@tropfort.com      :
:...............................:
```

#### Example: List "Limited" users

```javascript
ascli aoc admin res user list --fields=email --select=@json:'{"member_of_any_workspace":false}'
```

#### Example: create a group, add to workspace and add user to group

* Create the group and take note of `id`

```bash
ascli aoc admin res group create @json:'{"name":"group 1","description":"my super group"}'
```

Group: `11111`

* Get the workspace id

```bash
ascli aoc admin res workspace list --query=@json:'{"q":"myworkspace"}' --fields=id --format=csv --display=data
```

Workspace: 22222

* Add group to workspace

```bash
ascli aoc admin res workspace_membership create @json:'{"workspace_id":22222,"member_type":"user","member_id":11111}'
```

* Get a user's id

```bash
ascli aoc admin res user list --query=@json:'{"q":"manu.macron@example.com"}' --fields=id --format=csv --display=data
```

User: 33333

* Add user to group

```bash
ascli aoc admin res group_membership create @json:'{"group_id":11111,"member_type":"user","member_id":33333}'
```

#### Example: Perform a multi Gbps transfer between two remote shared folders

In this example, a user has access to a workspace where two shared folders are located on different sites, e.g. different cloud regions.

First, setup the environment (skip if already done)

```bash
ascli conf wizard --url=https://sedemo.ibmaspera.com --username=laurent.martin.aspera@fr.ibm.com
```

```output
Detected: Aspera on Cloud
Preparing preset: aoc_sedemo
Using existing key:
/Users/laurent/.aspera/ascli/aspera_aoc_key
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
ascli aoc user profile show
```

This creates the option preset "aoc_&lt;org name&gt;" to allow seamless command line access and sets it as default for aspera on cloud.

Then, create two shared folders located in two regions, in your files home, in a workspace.

Then, transfer between those:

```javascript
ascli -Paoc_show aoc files transfer --from-folder='IBM Cloud SJ' --to-folder='AWS Singapore' 100GB.file --ts=@json:'{"target_rate_kbps":"1000000","multi_session":10,"multi_session_threshold":1}'
```

#### Example: create registration key to register a node

```javascript
ascli aoc admin res client create @json:'{"data":{"name":"laurentnode","client_subject_scopes":["alee","aejd"],"client_subject_enabled":true}}' --fields=token --format=csv
```

```output
jfqslfdjlfdjfhdjklqfhdkl
```

#### Example: delete all registration keys

```bash
ascli aoc admin res client list --fields=id --format=csv|ascli aoc admin res client delete --bulk=yes --id=@lines:@stdin:
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

* An access key created on the Transfer Server (HSTS/ATS)
* a `node` resource in the AoC application.

The web UI allows creation of both entities in one shot.
For more flexibility, `ascli` allows this in two separate steps.
Note that when selecting "Use existing access key" in the web UI, this actually skips access key creation (first step).

So, for example, the creation of a node using ATS in IBM Cloud looks like (see other example in this manual):

* Create the access key on ATS

  The creation options are the ones of ATS API, refer to the [section on ATS](#ats_params) for more details and examples.

  ```javascript
  ascli aoc admin ats access_key create --cloud=softlayer --region=eu-de --params=@json:'{"storage":{"type":"ibm-s3","bucket":"mybucket","credentials":{"access_key_id":"mykey","secret_access_key":"mysecret"},"path":"/"}}'
  ```

  Once executed, the access key `id` and `secret`, randomly generated by the node api, is displayed: take note of it as the secrets will not be disclosed again.

* Create the AoC node entity

  First, Retrieve the ATS node address

  ```bash
  ascli aoc admin ats cluster show --cloud=softlayer --region=eu-de --fields=transfer_setup_url --format=csv --transpose-single=no
  ```

  Then use the returned address for the `url` key to actually create the AoC Node entity:

  ```javascript
  ascli aoc admin res node create @json:'{"name":"myname","access_key":"*accesskeyid*","ats_access_key":true,"ats_storage_type":"ibm-s3","url":"https://ats-sl-fra-all.aspera.io"}'
  ```

Creation of a node with a self-managed node is similar, but the command `aoc admin ats access_key create` is replaced with `node access_key create` on the private node itself.

### List of files to transfer

Source files are provided as a list with the `sources` option. Refer to section [File list](#file_list)

Note the special case when the source files are located on "Aspera on Cloud" (i.e. using access keys and the `file id` API).

Source files are located on "Aspera on cloud", when :

* the server is Aspera on Cloud, and executing a download or recv
* the agent is Aspera on Cloud, and executing an upload or send

In this case:

* If there is a single file : specify the full path
* Else, if there are multiple files:
  * All source files must be in the same source folder
  * Specify the source folder as first item in the list
  * followed by the list of file names.

### Packages

The webmail-like application.

#### Send a Package

General syntax:

```bash
ascli aoc packages send --value=[package extended value] [other parameters such as file list and transfer parameters]
```

Notes:

* The `value` option can contain any supported package creation parameter. Refer to the AoC package creation API, or display an existing package in JSON to list attributes.
* List allowed shared inbox destinations with: `ascli aoc packages shared_inboxes list`
* Use fields: `recipients` and/or `bcc_recipients` to provide the list of recipients: user or shared inbox.
  * Provide either ids as expected by API: `"recipients":[{"type":"dropbox","id":"1234"}]`
  * or just names: `"recipients":[{"The Dest"}]` . ascli will resolve the list of email addresses and dropbox names to the expected type/id list, based on case insensitive partial match.
* If a user recipient (email) is not already registered and the workspace allows external users, then the package is sent to an external user, and
  * if the option `new_user_option` is `@json:{"package_contact":true}` (default), then a public link is sent and the external user does not need to create an account
  * if the option `new_user_option` is `@json:{}`, then external users are invited to join the workspace

#### Example: Send a package with one file to two users, using their email

```javascript
ascli aoc package send --value=@json:'{"name":"my title","note":"my note","recipients":["laurent.martin.aspera@fr.ibm.com","other@example.com"]}' my_file.dat
```

#### Example: Send a package to a shared inbox with metadata

```javascript
ascli aoc package send --workspace=eudemo --value=@json:'{"name":"my pack title","recipients":["Shared Inbox With Meta"],"metadata":{"Project Id":"123","Type":"Opt2","CheckThose":["Check1","Check2"],"Optional Date":"2021-01-13T15:02:00.000Z"}}' ~/Documents/Samples/200KB.1
```

It is also possible to use identifiers and API parameters:

```javascript
ascli aoc package send --workspace=eudemo --value=@json:'{"name":"my pack title","recipients":[{"type":"dropbox","id":"12345"}],"metadata":[{"input_type":"single-text","name":"Project Id","values":["123"]},{"input_type":"single-dropdown","name":"Type","values":["Opt2"]},{"input_type":"multiple-checkbox","name":"CheckThose","values":["Check1","Check2"]},{"input_type":"date","name":"Optional Date","values":["2021-01-13T15:02:00.000Z"]}]}' ~/Documents/Samples/200KB.1
```

#### Example: List packages in a given shared inbox

When user packages are listed, the following query is used:

```javascript
{"archived":false,"exclude_dropbox_packages":true,"has_content":true,"received":true}
```

To list packages in a shared inbox, the query has to be specified with withe the shared inbox by name or its identifier. Additionnal parameters can be specified, as supported by the API (to find out available filters, consult the API definition, or use the web interface in developer mode). The current workspace is added unless specified in the query.

Using shared inbox name:

```javascript
ascli aoc packages list --query=@json:'{"dropbox_name":"My Shared Inbox","archived":false,"received":true,"has_content":true,"exclude_dropbox_packages":false,"include_draft":false,"sort":"-received_at"}'
```

Using shared inbox identifier: first retrieve the id of the shared inbox, and then list packages with the appropriate filter.

```bash
shbxid=$(ascli aoc packages shared_inboxes show name 'My Shared Inbox' --format=csv --display=data --fields=id --transpose-single=no)
```

```javascript
ascli aoc packages list --query=@json:'{"dropbox_id":"'$shbxid'","archived":false,"received":true,"has_content":true,"exclude_dropbox_packages":false,"include_draft":false,"sort":"-received_at"}'
```

#### Example: Send a package with files from the Files app

Find files in Files app:

```bash
ascli aoc files browse /src_folder
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
ascli aoc files node_info /src_folder --format=json --display=data | ascli aoc package send --value=@json:'{"name":"test","recipients":["laurent.martin.aspera@fr.ibm.com"]}' 10M.dat --transfer=node --transfer-info=@json:@stdin:
```

#### <a id="aoccargo"></a>Receive new packages only (Cargo)

It is possible to automatically download new packages, like using Aspera Cargo:

```bash
ascli aoc packages recv --id=ALL --once-only=yes --lock-port=12345
```

* `--id=ALL` (case sensitive) will download all packages
* `--once-only=yes` keeps memory of any downloaded package in persistency files located in the configuration folder
* `--lock-port=12345` ensures that only one instance is started at the same time, to avoid running two downloads in parallel

Typically, one would execute this command on a regular basis, using the method of your choice:

* Windows: [Task Scheduler](https://docs.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-start-page)
* Linux/Unix: [cron](https://www.man7.org/linux/man-pages/man5/crontab.5.html)
* etc...

### Files

Folder sharing app.

#### Download Files

Download of files is straightforward using command: `aoc files download`

#### Shared folders

Shared folder by users are managed through **permissions**.
For creation, parameters are the same as for node api [permissions](https://developer.ibm.com/apis/catalog/aspera--aspera-node-api/api/API--aspera--node-api#post960739960).
`ascli` expects the same payload for creation, but it will automatically populated required tags if needed.
Also, the pseudo key `with` is added: it will lookup the name in the contacts and fill the proper type and id.
The pseudo parameter `link_name` allows changing default "shared as" name.

* List permissions on a shared folder as user

```bash
ascli aoc files file --path=/shared_folder_test1 perm list
```

* Share a personal folder with other users

```bash
ascli aoc files file --path=/shared_folder_test1 perm create @json:'{"with":"laurent"}'
```

* Revoke shared access

```bash
ascli aoc files file --path=/shared_folder_test1 perm delete 6161
```

* List shared folders in node

```bash
ascli aoc admin res node --id=8669 shared_folders
```

* List shared folders in workspace

```bash
ascli aoc admin res workspace --id=10818 shared_folders
```

* List members of shared folder

```bash
ascli aoc admin res node --id=8669 v4 perm 82 show
```

#### Cross Organization transfers

It is possible to transfer files directly between organizations without having to first download locally and then upload...

Although optional, the creation of [option preset](#lprt) is recommended to avoid placing all parameters in the command line.

Procedure to send a file from org1 to org2:

* Get access to Organization 1 and create a [option preset](#lprt): e.g. `org1`, for instance, use the [Wizard](#aocwizard)
* Check that access works and locate the source file e.g. `mysourcefile`, e.g. using command `files browse`
* Get access to Organization 2 and create a [option preset](#lprt): e.g. `org2`
* Check that access works and locate the destination folder `mydestfolder`
* execute the following:

```bash
ascli -Porg1 aoc files node_info /mydestfolder --format=json --display=data | ascli -Porg2 aoc files upload mysourcefile --transfer=node --transfer-info=@json:@stdin:
```

Explanation:

* `-Porg1 aoc` use Aspera on Cloud plugin and load credentials for `org1`
* `files node_info /mydestfolder` generate transfer information including node api credential and root id, suitable for the next command
* `--format=json` format the output in JSON (instead of default text table)
* `--display=data` display only the result, and remove other information, such as workspace name
* `|` the standard output of the first command is fed into the second one
* `-Porg2 aoc` use Aspera on Cloud plugin and load credentials for `org2`
* `files upload mysourcefile` upload the file named `mysourcefile` (located in `org1`)
* `--transfer=node` use transfer agent type `node` instead of default [`direct`](#agt_direct)
* `--transfer-info=@json:@stdin:` provide `node` transfer agent information, i.e. node API credentials, those are expected in JSON format and read from standard input

#### Find Files

The command `aoc files find [--value=expression]` will recursively scan storage to find files matching the expression criteria. It works also on node resource using the v4 command. (see examples)

The expression can be of 3 formats:

* empty (default) : all files, equivalent to value: `exec:true`
* not starting with `exec:` : the expression is a regular expression, using [Ruby Regex](https://ruby-doc.org/core/Regexp.html) syntax. equivalent to value: `exec:f['name'].match(/expression/)`

For instance, to find files with a special extension, use `--value='\.myext$'`

* starting with `exec:` : the Ruby code after the prefix is executed for each entry found. The entry variable name is `f`. The file is displayed if the result of the expression is true;

Examples of expressions: (using like this: `--value=exec:'<expression>'`)

* Find files more recent than 100 days

```bash
f["type"].eql?("file") and (DateTime.now-DateTime.parse(f["modified_time"]))<100
```

* Find files older than 1 year on a given node and store in file list

```bash
ascli aoc admin res node --name='my node name' --secret='_secret_here_' v4 find / --fields=path --value='exec:f["type"].eql?("file") and (DateTime.now-DateTime.parse(f["modified_time"]))<100' --format=csv > my_file_list.txt
```

* Delete the files, one by one

```bash
cat my_file_list.txt|while read path;do echo ascli aoc admin res node --name='my node name' --secret='_secret_here_' v4 delete "$path" ;done
```

* Delete the files in bulk

```bash
cat my_file_list.txt | ascli aoc admin res node --name='my node name' --secret='_secret_here_' v3 delete @lines:@stdin:
```

### AoC sample commands

```bash
aoc -N remind --username=my_aoc_user_email
aoc -N servers
aoc admin analytics transfers --query=@json:'{"status":"completed","direction":"receive"}' --notif-to=my_recipient_email --notif-template=@ruby:'%Q{From: <%=from_name%> <<%=from_email%>>\nTo: <<%=to%>>\nSubject: <%=ev["files_completed"]%> files received\n\n<%=ev.to_yaml%>}'
aoc admin ats access_key create --cloud=aws --region=my_aws_bucket_region --params=@json:'{"id":"ak_aws","name":"my test key AWS","storage":{"type":"aws_s3","bucket":"my_aws_bucket_name","credentials":{"access_key_id":"my_aws_bucket_key","secret_access_key":"my_aws_bucket_secret"},"path":"/"}}'
aoc admin ats access_key create --cloud=softlayer --region=my_icos_bucket_region --params=@json:'{"id":"akibmcloud","secret":"somesecret","name":"my test key","storage":{"type":"ibm-s3","bucket":"my_icos_bucket_name","credentials":{"access_key_id":"my_icos_bucket_key","secret_access_key":"my_icos_bucket_secret"},"path":"/"}}'
aoc admin ats access_key delete akibmcloud
aoc admin ats access_key list --fields=name,id
aoc admin ats access_key node akibmcloud --secret=somesecret browse /
aoc admin ats cluster clouds
aoc admin ats cluster list
aoc admin ats cluster show --cloud=aws --region=eu-west-1
aoc admin ats cluster show 1f412ae7-869a-445c-9c05-02ad16813be2
aoc admin res application list
aoc admin res client list
aoc admin res client_access_key list
aoc admin res client_registration_token create @json:'{"data":{"name":"test_client_reg1","client_subject_scopes":["alee","aejd"],"client_subject_enabled":true}}'
aoc admin res client_registration_token delete my_clt_reg_id
aoc admin res client_registration_token list
aoc admin res contact list
aoc admin res dropbox list
aoc admin res dropbox_membership list
aoc admin res group list
aoc admin res kms_profile list
aoc admin res node list
aoc admin res operation list
aoc admin res organization show
aoc admin res package list --http-options=@json:'{"read_timeout":120.0}'
aoc admin res saml_configuration list
aoc admin res self show
aoc admin res short_link list
aoc admin res user list
aoc admin res workspace_membership list
aoc admin resource node --name=my_aoc_ak_name --secret=my_aoc_ak_secret v3 access_key create --value=@json:'{"id":"testsub1","storage":{"path":"/folder1"}}'
aoc admin resource node --name=my_aoc_ak_name --secret=my_aoc_ak_secret v3 events
aoc admin resource node --name=my_aoc_ak_name --secret=my_aoc_ak_secret v4 browse /
aoc admin resource node --name=my_aoc_ak_name --secret=my_aoc_ak_secret v4 delete /folder1
aoc admin resource node --name=my_aoc_ak_name --secret=my_aoc_ak_secret v4 mkdir /folder1
aoc admin resource node v3 name my_aoc_ak_name --secret=my_aoc_ak_secret access_key delete testsub1
aoc admin resource workspace list
aoc admin resource workspace_membership list --fields=ALL --query=@json:'{"page":1,"per_page":50,"embed":"member","inherited":false,"workspace_id":11363,"sort":"name"}'
aoc automation workflow action my_wf_id create --value=@json:'{"name":"toto"}'
aoc automation workflow create --value=@json:'{"name":"test_workflow"}'
aoc automation workflow delete my_wf_id
aoc automation workflow list
aoc automation workflow list --select=@json:'{"name":"test_workflow"}' --fields=id --format=csv --display=data
aoc automation workflow list --value=@json:'{"show_org_workflows":"true"}' --scope=admin:all
aoc bearer_token --display=data --scope=user:all
aoc faspex
aoc files bearer /
aoc files bearer_token_node / --cache-tokens=no
aoc files browse /
aoc files browse / -N --link=my_aoc_publink_folder
aoc files delete /testsrc
aoc files download --transfer=connect /200KB.1
aoc files file permission --path=/ascli_test list
aoc files file show --path=/200KB.1
aoc files file show my_file_id
aoc files find / --value='\.partial$'
aoc files http_node_download --to-folder=. /200KB.1
aoc files mkdir /testsrc
aoc files rename /somefolder testdst
aoc files short_link create --to-folder=/testdst --value=private
aoc files short_link create --to-folder=/testdst --value=public
aoc files short_link list --value=@json:'{"purpose":"shared_folder_auth_link"}'
aoc files transfer --from-folder=/testsrc --to-folder=/testdst testfile.bin
aoc files upload --to-folder=/testsrc testfile.bin
aoc files upload -N --to-folder=/ testfile.bin --link=my_aoc_publink_folder
aoc files upload Test.pdf --transfer=node --transfer-info=@json:@stdin:
aoc files v3 info
aoc org -N --link=my_aoc_publink_recv_from_aocuser
aoc organization
aoc packages browse "my_package_id" /contents
aoc packages list
aoc packages list --query=@json:'{"dropbox_name":"my_aoc_shbx_name","sort":"-received_at","archived":false,"received":true,"has_content":true,"exclude_dropbox_packages":false}'
aoc packages recv "my_package_id" --to-folder=.
aoc packages recv ALL --to-folder=. --once-only=yes --lock-port=12345
aoc packages send --value=@json:'{"name":"Important files delivery","recipients":["my_email_external_user"]}' --new-user-option=@json:'{"package_contact":true}' testfile.bin
aoc packages send --value=@json:'{"name":"Important files delivery","recipients":["my_email_internal_user"],"note":"my note"}' testfile.bin
aoc packages send --workspace="my_aoc_shbx_ws" --value=@json:'{"name":"Important files delivery","recipients":["my_aoc_shbx_name"],"metadata":[{"input_type":"single-text","name":"Project Id","values":["123"]},{"input_type":"single-dropdown","name":"Type","values":["Opt2"]},{"input_type":"multiple-checkbox","name":"CheckThose","values":["Check1","Check2"]},{"input_type":"date","name":"Optional Date","values":["2021-01-13T15:02:00.000Z"]}]}' testfile.bin
aoc packages send --workspace="my_aoc_shbx_ws" --value=@json:'{"name":"Important files delivery","recipients":["my_aoc_shbx_name"],"metadata":{"Project Id":"456","Type":"Opt2","CheckThose":["Check1","Check2"],"Optional Date":"2021-01-13T15:02:00.000Z"}}' testfile.bin
aoc packages send --workspace="my_aoc_shbx_ws" --value=@json:'{"name":"Important files delivery","recipients":["my_aoc_shbx_name"]}' testfile.bin
aoc packages send -N --value=@json:'{"name":"Important files delivery"}' testfile.bin --link=my_aoc_publink_send_aoc_user --password=my_aoc_publink_send_use_pass
aoc packages send -N --value=@json:'{"name":"Important files delivery"}' testfile.bin --link=my_aoc_publink_send_shd_inbox
aoc packages shared_inboxes list
aoc user profile modify @json:'{"name":"dummy change"}'
aoc user profile show
aoc user workspaces current
aoc user workspaces list
```

## <a id="ats"></a>Plugin: Aspera Transfer Service

ATS is usable either :

* from an AoC subscription : ascli aoc admin ats : use AoC authentication

* or from an IBM Cloud subscription : ascli ats : use IBM Cloud API key authentication

### IBM Cloud ATS : creation of api key

This section is about using ATS with an IBM cloud subscription.
If you are using ATS as part of AoC, then authentication is thropugh AoC, not IBM Cloud.

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
API Key       my_secret_api_key_here_8f8d9fdakjhfsashjk678
Locked        false
UUID          ApiKey-05b8fadf-e7fe-4bc4-93a9-6fd348c5ab1f
```

References:

* [https://console.bluemix.net/docs/iam/userid_keys.html#userapikey](https://console.bluemix.net/docs/iam/userid_keys.html#userapikey)
* [https://ibm.ibmaspera.com/helpcenter/transfer-service](https://ibm.ibmaspera.com/helpcenter/transfer-service)

Then, to register the key by default for the ats plugin, create a preset. Execute:

```bash
ascli config preset update my_ibm_ats --ibm-api-key=my_secret_api_key_here_8f8d9fdakjhfsashjk678
```

```bash
ascli config preset set default ats my_ibm_ats
```

```bash
ascli ats api_key instances
```

```output
+--------------------------------------+
| instance                             |
+--------------------------------------+
| aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee |
+--------------------------------------+
```

```bash
ascli config preset update my_ibm_ats --instance=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
```

```bash
ascli ats api_key create
```

```output
+--------+----------------------------------------------+
| key    | value                                        |
+--------+----------------------------------------------+
| id     | ats_XXXXXXXXXXXXXXXXXXXXXXXX                 |
| secret | YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY |
+--------+----------------------------------------------+
ascli config preset update my_ibm_ats --ats-key=ats_XXXXXXXXXXXXXXXXXXXXXXXX --ats-secret=YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY
```

### <a id="ats_params"></a>ATS Access key creation parameters

When creating an ATS access key, the option `params` must contain an extended value with the creation parameters. Those asre directly the parameters expected by the [ATS API](https://developer.ibm.com/apis/catalog?search=%22Aspera%20ATS%20API%22).

### Misc. Examples

Example: create access key on IBM Cloud (softlayer):

```javascript
ascli ats access_key create --cloud=softlayer --region=ams --params=@json:'{"storage":{"type":"softlayer_swift","container":"_container_name_","credentials":{"api_key":"_secret_here_","username":"_name_:_usr_name_"},"path":"/"},"id":"_optional_id_","name":"_optional_name_"}'
```

Example: create access key on AWS:

```javascript
ascli ats access_key create --cloud=aws --region=eu-west-1 --params=@json:'{"id":"testkey3","name":"laurent key AWS","storage":{"type":"aws_s3","bucket":"my-bucket","credentials":{"access_key_id":"AKIA_MY_API_KEY","secret_access_key":"_secret_here_"},"path":"/laurent"}}'
```

Example: create access key on Azure SAS:

```javascript
ascli ats access_key create --cloud=azure --region=eastus --params=@json:'{"id":"testkeyazure","name":"laurent key azure","storage":{"type":"azure_sas","credentials":{"shared_access_signature":"https://containername.blob.core.windows.net/blobname?sr=c&..."},"path":"/"}}'
```

(Note that the blob name is mandatory after server address and before parameters. and that parameter sr=c is mandatory.)

Example: create access key on Azure:

```javascript
ascli ats access_key create --cloud=azure --region=eastus --params=@json:'{"id":"testkeyazure","name":"laurent key azure","storage":{"type":"azure","credentials":{"account":"myaccount","key":"myaccesskey","storage_endpoint":"myblob"},"path":"/"}}'
```

delete all my access keys:

```bash
for k in $(ascli ats access_key list --field=id --format=csv);do ascli ats access_key id $k delete;done
```

The parameters provided to ATS for access key creation are the ones of [ATS API](https://developer.ibm.com/apis/catalog?search=%22aspera%20ats%22) for the `POST /access_keys` endpoint.

### ATS sample commands

```bash
ats access_key cluster akibmcloud --secret=somesecret
ats access_key create --cloud=aws --region=my_aws_bucket_region --params=@json:'{"id":"ak_aws","name":"my test key AWS","storage":{"type":"aws_s3","bucket":"my_aws_bucket_name","credentials":{"access_key_id":"my_aws_bucket_key","secret_access_key":"my_aws_bucket_secret"},"path":"/"}}'
ats access_key create --cloud=softlayer --region=my_icos_bucket_region --params=@json:'{"id":"akibmcloud","secret":"somesecret","name":"my test key","storage":{"type":"ibm-s3","bucket":"my_icos_bucket_name","credentials":{"access_key_id":"my_icos_bucket_key","secret_access_key":"my_icos_bucket_secret"},"path":"/"}}'
ats access_key delete ak_aws
ats access_key delete akibmcloud
ats access_key list --fields=name,id
ats access_key node akibmcloud browse / --secret=somesecret
ats api_key create
ats api_key instances
ats api_key list
ats cluster clouds
ats cluster list
ats cluster show --cloud=aws --region=eu-west-1
ats cluster show 1f412ae7-869a-445c-9c05-02ad16813be2
```

## Plugin: IBM Aspera High Speed Transfer Server (transfer)

This plugin uses SSH as a session protocol (using commands `ascp` and `ascmd`) and does not use the node API.
It is the legacy way of accessing an Aspera Server, often used for server to server transfers.
Modern mode is to use the node API and transfer tokens.

### Server sample commands

```bash
server -N -Ptst_server_bykey -Plocal_user br /
server browse /
server browse folder_1/target_hot
server cp NEW_SERVER_FOLDER/testfile.bin folder_1/200KB.2
server delete NEW_SERVER_FOLDER
server delete folder_1/target_hot
server delete folder_1/to.delete
server df
server download NEW_SERVER_FOLDER/testfile.bin --to-folder=. --transfer-info=@json:'{"wss":false,"resume":{"iter_max":1}}'
server download NEW_SERVER_FOLDER/testfile.bin --to-folder=folder_1 --transfer=node
server du /
server health transfer --to-folder=folder_1 --format=nagios 
server info
server md5sum NEW_SERVER_FOLDER/testfile.bin
server mkdir NEW_SERVER_FOLDER --logger=stdout
server mkdir folder_1/target_hot
server mv folder_1/200KB.2 folder_1/to.delete
server upload --sources=@ts --ts=@json:'{"EX_ascp_args":["--file-list","'"filelist.txt"'"]}' --to-folder=NEW_SERVER_FOLDER 
server upload --sources=@ts --ts=@json:'{"EX_ascp_args":["--file-pair-list","'"filepairlist.txt"'"]}'
server upload --sources=@ts --ts=@json:'{"EX_file_list":"'"filelist.txt"'"}' --to-folder=NEW_SERVER_FOLDER
server upload --sources=@ts --ts=@json:'{"EX_file_pair_list":"'"filepairlist.txt"'"}'
server upload --sources=@ts --ts=@json:'{"paths":[{"source":"testfile.bin","destination":"NEW_SERVER_FOLDER/othername"}]}'
server upload --src-type=pair --sources=@json:'["testfile.bin","NEW_SERVER_FOLDER/othername"]'
server upload --src-type=pair testfile.bin NEW_SERVER_FOLDER/othername --notif-to=my_recipient_email
server upload --src-type=pair testfile.bin folder_1/with_options --ts=@json:'{"cipher":"aes-192-gcm","content_protection":"encrypt","content_protection_password":"_secret_here_","cookie":"biscuit","create_dir":true,"delete_before_transfer":false,"delete_source":false,"exclude_newer_than":1,"exclude_older_than":10000,"fasp_port":33001,"http_fallback":false,"multi_session":0,"overwrite":"diff+older","precalculate_job_size":true,"preserve_access_time":true,"preserve_creation_time":true,"rate_policy":"fair","resume_policy":"sparse_csum","symlink_policy":"follow"}'
server upload --to-folder=folder_1/target_hot --lock-port=12345 --ts=@json:'{"EX_ascp_args":["--remove-after-transfer","--remove-empty-directories","--exclude-newer-than=-8","--src-base","source_hot"]}' source_hot
server upload testfile.bin --to-folder=NEW_SERVER_FOLDER --ts=@json:'{"multi_session":3,"multi_session_threshold":1,"resume_policy":"none","target_rate_kbps":1500}' --transfer-info=@json:'{"spawn_delay_sec":2.5}' --progress=multi
```

### Authentication on Server with SSH session

If SSH is the session control protocol (i.e. not WSS), then following session authentication methods are supported:

* SSH password
* SSH keys (Multiple SSH key paths can be provided.)

If username is not provided, the default transfer user `xfer` is used.

If no SSH password or key is provided and a transfer token is provided in transfer spec (option `ts`), then standard SSH bypass keys are used. Example:

```javascript
ascli server --url=ssh://... --ts=@json:'{"token":"Basic abc123"}'
```

> Note: If you need to use the Aspera public keys, then specify an empty token: `--ts=@json:'{"token":""}'` : Aspera public SSH keys will be used, but the protocol will ignore the empty token.

The value of the `ssh_keys` option can be a single value or an array.
Each value is a **path** to a private key and is expanded (`~` is replaced with the user's home folder).

Examples:

```bash
ascli server --ssh-keys=~/.ssh/id_rsa
ascli server --ssh-keys=@list:,~/.ssh/id_rsa
ascli server --ssh-keys=@json:'["~/.ssh/id_rsa"]'
```

For non-transfer related command (browse, delete), the ruby SSH client library `Net::SSH` is used and provides several options settable using option `ssh_options`.
For a list of SSH client options, refer to the ruby documentation of [Net::SSH](http://net-ssh.github.io/net-ssh/Net/SSH.html).

By default the SSH library expect that a local ssh-agent is running.

On Linux, if you get an error message such as:

```bash
ERROR -- net.ssh.authentication.agent: could not connect to ssh-agent: Agent not configured
```

or on Windows:

```bash
ERROR -- net.ssh.authentication.agent: could not connect to ssh-agent: pageant process not running
```

This means that you don't have such an SSH agent running, then:

* check env var: `SSH_AGENT_SOCK`
* check if the SSH key is protected with a passphrase (then, use the `passphrase` SSH option)
* [check the manual](https://net-ssh.github.io/ssh/v1/chapter-2.html#s2)
* To disable the use of `ssh-agent`, use the option `ssh_options` like this:

```bash
ascli server --ssh-options=@ruby:'{use_agent: false}' ...
```

This can also be set as default using a global preset.

### Example

One can test the `server` application using the well known demo server:

```bash
ascli config initdemo
ascli server browse /aspera-test-dir-large
ascli server download /aspera-test-dir-large/200MB
```

`initdemo` creates a [option preset](#lprt) `demoserver` and set it as default for plugin `server`.

## Plugin: IBM Aspera High Speed Transfer Server (node)

This plugin gives access to capabilities provided by HSTS node API.

### File Operations

It is possible to:

* browse
* transfer (upload / download)
* ...

For transfers, it is possible to control how transfer is authorized using option: `token_type`:

* `aspera` : api `<upload|download>_setup` is called to create the transfer spec including the Aspera token, used as is.
* `hybrid` : same as `aspera`, but token is replaced with basic token like `basic`
* `basic` : transfer spec is created like this:

```javascript
{
  "remote_host": address of node url,
  "remote_user": "xfer",
  "ssh_port": 33001,
  "token": "Basic <base 64 encoded user/pass>",
  "direction": send/receive
}
```

Note that the port is assumed to be the default SSH port `33001` and transfer user is assumed to be `xfer`.

### Central

The central subcommand uses the "reliable query" API (session and file). It allows listing transfer sessions and transferred files.

Filtering can be applied:

```bash
ascli node central file list
```

by providing the `validator` option, offline transfer validation can be done.

### FASP Stream

It is possible to start a FASPStream session using the node API:

Use the "node stream create" command, then arguments are provided as a [*transfer-spec*](#transferspec).

```javascript
ascli node stream create --ts=@json:'{"direction":"send","source":"udp://233.3.3.4:3000?loopback=1&ttl=2","destination":"udp://233.3.3.3:3001/","remote_host":"localhost","remote_user":"stream","remote_password":"_pass_here_"}' --preset=stream
```

### Watchfolder

Refer to [Aspera documentation](https://download.asperasoft.com/download/docs/entsrv/3.7.4/es_admin_linux/webhelp/index.html#watchfolder_external/dita/json_conf.html) for watch folder creation.

`ascli` supports remote operations through the node API. Operations are:

* Start watchd and watchfolderd services running as a system user having access to files
* configure a watchfolder to define automated transfers

```javascript
ascli node service create @json:'{"id":"mywatchd","type":"WATCHD","run_as":{"user":"user1"}}'
ascli node service create @json:'{"id":"mywatchfolderd","type":"WATCHFOLDERD","run_as":{"user":"user1"}}'
ascli node watch_folder create @json:'{"id":"mywfolder","source_dir":"/watch1","target_dir":"/","transport":{"host":"10.25.0.4","user":"user1","pass":"mypassword"}}'
```

### Out of Transfer File Validation

Follow the Aspera Transfer Server configuration to activate this feature.

```javascript
ascli node central file list --validator=ascli --data=@json:'{"file_transfer_filter":{"max_result":1}}'
```

```output
:..............:..............:............:......................................:
: session_uuid :    file_id   :   status   :              path                    :
:..............:..............:............:......................................:
: 1a74444c-... : 084fb181-... : validating : /home/xfer.../PKG - my title/200KB.1 :
:..............:..............:............:......................................:
```

```javascript
ascli node central file update --validator=ascli --data=@json:'{"files":[{"session_uuid": "1a74444c-...","file_id": "084fb181-...","status": "completed"}]}'
```

```output
updated
```

### Example: SHOD to ATS

Scenario: Access to a "Shares on Demand" (SHOD) server on AWS is provided by a partner.
We need to transfer files from this third party SHOD instance into our Azure BLOB storage.
Simply create an "Aspera Transfer Service" instance, which provides access to the node API.
Then create a configuration for the "SHOD" instance in the configuration file: in section "shares", a configuration named: awsshod.
Create another configuration for the Azure ATS instance: in section "node", named azureats.
Then execute the following command:

```bash
ascli node download /share/sourcefile --to-folder=/destinationfolder --preset=awsshod --transfer=node --transfer-info=@preset:azureats
```

This will get transfer information from the SHOD instance and tell the Azure ATS instance to download files.

### Create access key

```javascript
ascli node access_key create --value=@json:'{"id":"eudemo-sedemo","secret":"mystrongsecret","storage":{"type":"local","path":"/data/asperafiles"}}'
```

### Node sample commands

```bash
node -N -Ptst_node_preview access_key create --value=@json:'{"id":"aoc_1","storage":{"type":"local","path":"/"}}'
node -N -Ptst_node_preview access_key delete aoc_1
node -Pnode_srv access_key do my_aoc_ak_name br /
node -Pnode_srv access_key list
node -Pnode_srv service create @json:'{"id":"service1","type":"WATCHD","run_as":{"user":"user1"}}'
node -Pnode_srv service delete service1
node -Pnode_srv service list
node api_details
node async bandwidth 1
node async counters 1
node async files 1
node async list
node async show 1
node async show ALL
node basic_token
node browse / -r
node delete /todelete
node delete @list:,/todelete,/tdlink,/delfile
node delete folder_1/10MB.1
node delete testfile.bin
node download testfile.bin --to-folder=.
node download testfile.bin --to-folder=. --token-type=hybrid
node health
node info --fpac='function FindProxyForURL(url,host){return "DIRECT"}'
node license
node mkdir /todelete
node mkfile /delfile1 "hello world"
node mklink /todelete /tdlink
node rename / delfile1 delfile
node search / --value=@json:'{"sort":"mtime"}'
node space /
node transfer list --value=@json:'{"active_only":true}'
node upload --to-folder="folder_1" --sources=@ts --ts=@json:'{"paths":[{"source":"/aspera-test-dir-small/10MB.1"}],"precalculate_job_size":true}' --transfer=node --transfer-info=@json:'{"url":"my_node_url","username":"my_node_user","password":"my_node_pass"}'
node upload --username=my_aoc_ak_name --password=my_aoc_ak_secret testfile.bin --token-type=basic
node upload testfile.bin --to-folder=folder_1 --ts=@json:'{"target_rate_cap_kbps":10000}'
node upload testfile.bin --to-folder=folder_1 --ts=@json:'{"target_rate_cap_kbps":10000}' --token-type=hybrid
```

## Plugin: IBM Aspera Faspex5

This is currently in beta, limited operations are supported.

This was tested with version Beta 5.

The API is listed in [Faspex 5 API Reference](https://developer.ibm.com/apis/catalog/?search=faspex) under "IBM Aspera Faspex API".

### Faspex 5 authentication

3 authentication methods are supported:

* jwt
* web
* boot

#### Faspex 5 using JWT

This is the preferred method to use.

For `jwt`, create an API client in Faspex with JWT support:

* Select a private key file: if you don't have any refer to section [Private Key](#private_key)
* Navigate to the web UI: Admin &rarr; Configurations &rarr; API Clients &rarr; Create
* Activate JWT
* Paste public key in the appropriate section
* Click on Create Button
* Take note of Client Id (and Client Secret, but not used in current version)

Then use these options:

```text
--auth=jwt
--client-id=xxx
--client-secret=xxx
--username=xxx
--private-key=@file:.../path/to/key.pem
```

#### Faspex 5 using web browser

For `web` method, create an API client in Faspex without JWT:

* Navigate to the web UI: Admin &rarr; Configurations &rarr; API Clients &rarr; Create
* Do not Activate JWT
* enter `https://127.0.0.1:8888` in the redirect URI
* Click on Create Button
* Take note of Client Id (and Client Secret, but not used in current version)

Then use options:

```text
--auth=web
--client-id=xxx
--client-secret=xxx
--redirect-uri=https://127.0.0.1:8888
```

#### Faspex 5 using bootstrap

For `boot` method: (will be removed in future)

* open a browser
* start developer mode
* login to faspex 5
* find the first API call with `Authorization` token, and copy it (kind of base64 long string)

Use it as password and use `--auth=boot`.

```bash
ascli conf id f5boot update --url=https://localhost/aspera/faspex --auth=boot --password=ABC.DEF.GHI...
```

### Faspex 5 sample commands

```bash
faspex5 admin res accounts list
faspex5 admin res contacts list
faspex5 admin res jobs list
faspex5 admin res node list --value=@json:'{"type":"received","subtype":"mypackages"}'
faspex5 admin res oauth_clients list
faspex5 admin res registrations list
faspex5 admin res saml_configs list
faspex5 admin res shared_inboxes list
faspex5 admin res workgroups list
faspex5 bearer_token
faspex5 health
faspex5 package list --value=@json:'{"mailbox":"inbox","state":["released"]}'
faspex5 package receive "my_package_id" --to-folder=.  --ts=@json:'{"content_protection_password":"abc123_yo"}'
faspex5 package send --value=@json:'{"title":"test title","recipients":[{"name":"my_f5_user"}]}' testfile.bin --ts=@json:'{"content_protection_password":"_content_prot_here_"}'
```

### Faspex 5 other examples

* List all shared inboxes

```javascript
ascli faspex5 admin res shared list --value=@json:'{"all":true}' --fields=id,name
```

* Create Metadata profile

```javascript
ascli faspex5 admin res metadata_profiles create --value=@json:'{"name":"the profile","default":false,"title":{"max_length":200,"illegal_chars":[]},"note":{"max_length":400,"illegal_chars":[],"enabled":false},"fields":[{"ordering":0,"name":"field1","type":"text_area","require":true,"illegal_chars":[],"max_length":100},{"ordering":1,"name":"fff2","type":"option_list","require":false,"choices":["opt1","opt2"]}]}'
```

* Create a Shared inbox with specific metadata profile

```javascript
ascli faspex5 admin res shared create --value=@json:'{"name":"the shared inbox","metadata_profile_id":1}'
```

## Plugin: IBM Aspera Faspex (4.x)

Notes:

* The command "v4" requires the use of APIv4, refer to the Faspex Admin manual on how to activate.
* For full details on Faspex API, refer to: [Reference on Developer Site](https://developer.ibm.com/apis/catalog/?search=faspex)

### Listing Packages

Command: `faspex package list`

#### Option `box`

By default it looks in box `inbox`, but the following boxes are also supported: `archive` and `sent`, selected with option `box`.

#### Option `recipient`

A user can receive a package because the recipient is:

* the user himself (default)
* the user is member of a dropbox/workgroup: filter using option `recipient` set with value `*<name of dropbox/workgroup>`

#### Option `query`

As inboxes may be large, it is possible to use the following query parameters:

* `count` : (native) number items in one API call (default=0, equivalent to 10)
* `page` : (native) id of page in call (default=0)
* `startIndex` : (native) index of item to start, default=0, oldest index=0
* `max` : maximum number of items
* `pmax` : maximum number of pages

(SQL query is `LIMIT <startIndex>, <count>`)

The API is listed in [Faspex 4 API Reference](https://developer.ibm.com/apis/catalog/?search=faspex) under "Services (API v.3)".

If no parameter `max` or `pmax` is provided, then all packages will be listed in the inbox, which result in paged API calls (using parameter: `count` and `page`). By default page is `0` (`10`), it can be increased to have less calls.

#### Example: list packages in dropbox

```javascript
ascli faspex package list --box=inbox --recipient='*my_dropbox' --query=@json:'{"max":20,"pmax":2,"count":20}'
```

List a maximum of 20 items grouped by pages of 20, with maximum 2 pages in received box (inbox) when received in dropbox `*my_dropbox`.

### Receiving a Package

The command is `package recv`, possible methods are:

* provide a package id with option `id`
* provide a public link with option `link`
* provide a `faspe:` URI with option `link`

```bash
ascli faspex package recv --id=12345
ascli faspex package recv --link=faspe://...
```

If the package is in a specific **dropbox**/**workgroup**, add option `recipient` for both the `list` and `recv` commands.

```bash
ascli faspex package list --recipient='*thedropboxname'
ascli faspex package recv 125 --recipient='*thedropboxname'
```

if `id` is set to `ALL`, then all packages are downloaded, and if option `once_only`is used, then a persistency file is created to keep track of already downloaded packages.

### Sending a Package

The command is `faspex package send`. Package information (title, note, metadata, options) is provided in option `delivery_info`.
The contents of `delivery_info` is directly the contents of the `send` v3 [API of Faspex 4](https://developer.ibm.com/apis/catalog/aspera--aspera-faspex-client-sdk/API%20v.3:%20Send%20Packages), consult it for extended supported parameters.

Example:

```javascript
ascli faspex package send --delivery-info=@json:'{"title":"my title","recipients":["laurent.martin.aspera@fr.ibm.com"]}' --url=https://faspex.corp.com/aspera/faspex --username=foo --password=bar /tmp/file1 /home/bar/file2
```

If the recipient is a dropbox or workgroup: provide the name of the dropbox or workgroup preceded with `*` in the `recipients` field of the `delivery_info` option:
`"recipients":["*MyDropboxName"]`

Additional optional parameters in `delivery_info`:

* Package Note: : `"note":"note this and that"`
* Package Metadata: `"metadata":{"Meta1":"Val1","Meta2":"Val2"}`

### Email notification on transfer

Like for any transfer, a notification can be sent by email using parameters: `notif_to` and `notif_template` .

Example:

```javascript
ascli faspex package send --delivery-info=@json:'{"title":"test pkg 1","recipients":["aspera.user1@gmail.com"]}' ~/Documents/Samples/200KB.1 --notif-to=aspera.user1@gmail.com --notif-template=@ruby:'%Q{From: <%=from_name%> <<%=from_email%>>\nTo: <<%=to%>>\nSubject: Package sent: <%=ts["tags"]["aspera"]["faspex"]["metadata"]["_pkg_name"]%> files received\n\nTo user: <%=ts["tags"]["aspera"]["faspex"]["recipients"].first["email"]%>}'
```

In this example the notification template is directly provided on command line. Package information placed in the message are directly taken from the tags in transfer spec. The template can be placed in a file using modifier: `@file:`

### Operation on dropboxes

Example:

```javascript
ascli faspex v4 dropbox create --value=@json:'{"dropbox":{"e_wg_name":"test1","e_wg_desc":"test1"}}'
ascli faspex v4 dropbox list
ascli faspex v4 dropbox delete --id=36
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
    testlaurent:
      node: "@preset:my_faspex_node"
      path: /myfiles
my_faspex_node:
  url: https://10.25.0.3:9092
  username: node_faspex
  password: MyNodePassword
```

In this example, a faspex storage named "testlaurent" exists in Faspex, and is located
under the docroot in "/myfiles" (this must be the same as configured in Faspex).
The node configuration name is "my_faspex_node" here.

Note: the v4 API provides an API for nodes and shares.

### Automated package download (cargo)

It is possible to tell `ascli` to download newly received packages, much like the official
cargo client, or drive. Refer to the [same section](#aoccargo) in the Aspera on Cloud plugin:

```bash
ascli faspex packages recv --id=ALL --once-only=yes --lock-port=12345
```

### Faspex 4 sample commands

```bash
faspex address_book
faspex dropbox list --recipient="*my_faspex_dbx"
faspex dropbox list --recipient="*my_faspex_wkg"
faspex health
faspex login_methods
faspex me
faspex package list
faspex package list --box=sent --fields=package_id --format=csv --display=data --query=@json:'{"max":1}'
faspex package list --fields=package_id --format=csv --display=data --query=@json:'{"max":1}'
faspex package list --recipient="*my_faspex_dbx" --format=csv --fields=package_id --query=@json:'{"max":1}'
faspex package list --recipient="*my_faspex_wkg" --format=csv --fields=package_id --query=@json:'{"max":1}'
faspex package recv "my_package_id" --to-folder=.
faspex package recv "my_package_id" --to-folder=. --box=sent
faspex package recv --to-folder=. --link="my_faspex_publink_recv_from_fxuser"
faspex package recv ALL --to-folder=. --once-only=yes
faspex package recv my_pkgid --recipient="*my_faspex_dbx" --to-folder=.
faspex package recv my_pkgid --recipient="*my_faspex_wkg" --to-folder=.
faspex package send --delivery-info=@json:'{"title":"Important files delivery","recipients":["*my_faspex_dbx"]}' testfile.bin
faspex package send --delivery-info=@json:'{"title":"Important files delivery","recipients":["*my_faspex_wkg"]}' testfile.bin
faspex package send --delivery-info=@json:'{"title":"Important files delivery","recipients":["my_email_internal_user","my_faspex_username"]}' testfile.bin
faspex package send --link="my_faspex_publink_send_to_dropbox" --delivery-info=@json:'{"title":"Important files delivery"}' testfile.bin
faspex package send --link="my_faspex_publink_send_to_fxuser" --delivery-info=@json:'{"title":"Important files delivery"}' testfile.bin
faspex source list
faspex source name "my_source_name" info
faspex source name "my_source_name" node br /
faspex v4 dmembership list
faspex v4 dropbox list
faspex v4 metadata_profile list
faspex v4 user list
faspex v4 wmembership list
faspex v4 workgroup list
```

## Plugin: IBM Aspera Shares

Aspera Shares supports the "node API" for the file transfer part. (Shares 1 and 2)

### Shares 1 sample commands

```bash
shares admin share list
shares admin share user_permissions 1
shares admin user app_authorizations 1
shares admin user list
shares admin user share_permissions 1
shares repository browse /
shares repository delete my_shares_upload/testfile.bin
shares repository download --to-folder=. my_shares_upload/testfile.bin
shares repository download --to-folder=. my_shares_upload/testfile.bin --transfer=httpgw --transfer-info=@json:'{"url":"https://my_http_gw_fqdn/aspera/http-gwy"}'
shares repository upload --to-folder=my_shares_upload testfile.bin
shares repository upload --to-folder=my_shares_upload testfile.bin --transfer=httpgw --transfer-info=@json:'{"url":"https://my_http_gw_fqdn/aspera/http-gwy"}'
```

## Plugin: Console

### Console sample commands

```bash
console transfer current list 
console transfer smart list 
console transfer smart sub my_job_id @json:'{"source":{"paths":["my_file_name"]},"source_type":"user_selected"}'
```

## Plugin: Orchestrator

### Orchestrator sample commands

```bash
orchestrator info
orchestrator plugins
orchestrator processes
orchestrator workflow details my_orch_workflow_id
orchestrator workflow export my_orch_workflow_id
orchestrator workflow inputs my_orch_workflow_id
orchestrator workflow list
orchestrator workflow start my_orch_workflow_id --params=@json:'{"Param":"world !"}'
orchestrator workflow start my_orch_workflow_id --params=@json:'{"Param":"world !"}' --result=ResultStep:Complete_status_message
orchestrator workflow status ALL
orchestrator workflow status my_orch_workflow_id
```

## Plugin: IBM Cloud Object Storage

The IBM Cloud Object Storage provides the possibility to execute transfers using FASP.
It uses the same transfer service as Aspera on Cloud, called Aspera Transfer Service (ATS).
Available ATS regions: [https://status.aspera.io](https://status.aspera.io)

There are two possibilities to provide credentials. If you already have the endpoint, apikey and CRN, use the first method. If you don't have credentials but have access to the IBM Cloud console, then use the second method.

### Using endpoint, apikey and Resource Instance ID (CRN)

If you have those parameters already, then following options shall be provided:

* `bucket` bucket name
* `endpoint` storage endpoint url, e.g. `https://s3.hkg02.cloud-object-storage.appdomain.cloud`
* `apikey` API Key
* `crn` resource instance id

For example, let us create a default configuration:

```bash
ascli conf id mycos update --bucket=mybucket --endpoint=https://s3.us-east.cloud-object-storage.appdomain.cloud --apikey=abcdefgh --crn=crn:v1:bluemix:public:iam-identity::a/xxxxxxx
ascli conf id default set cos mycos
```

Then, jump to the transfer example.

### Using service credential file

If you are the COS administrator and don't have yet the credential: Service credentials are directly created using the IBM cloud web ui. Navigate to:

Navigation Menu &rarr; Resource List &rarr; Storage &rarr; Cloud Object Storage &rarr; Service Credentials &rarr; &lt;select or create credentials&gt; &rarr; view credentials &rarr; copy

Then save the copied value to a file, e.g. : `$HOME/cos_service_creds.json`

or using the IBM Cloud CLI:

```bash
ibmcloud resource service-keys
ibmcloud resource service-key aoclaurent --output JSON|jq '.[0].credentials'>$HOME/service_creds.json
```

(if you don't have `jq` installed, extract the structure as follows)

It consists in the following structure:

```javascript
{
  "apikey": "_api_key_here_",
  "cos_hmac_keys": {
    "access_key_id": "_access_key_here_",
    "secret_access_key": "_secret_here_"
  },
  "endpoints": "https://control.cloud-object-storage.cloud.ibm.com/v2/endpoints",
  "iam_apikey_description": "my description _here_ ...",
  "iam_apikey_name": "my key name _here_",
  "iam_role_crn": "crn:v1:bluemix:public:iam::::serviceRole:Writer",
  "iam_serviceid_crn": "crn:v1:bluemix:public:iam-identity::a/xxxxxxx.....",
  "resource_instance_id": "crn:v1:bluemix:public:cloud-object-storage:global:a/xxxxxxx....."
}
```

The field `resource_instance_id` is for option `crn`

The field `apikey` is for option `apikey`

(If needed: endpoints for regions can be found by querying the `endpoints` URL.)

The required options for this method are:

* `bucket` bucket name
* `region` bucket region, e.g. eu-de
* `service_credentials` see below

For example, let us create a default configuration:

```bash
ascli conf id mycos update --bucket=laurent --service-credentials=@val:@json:@file:~/service_creds.json --region=us-south
ascli conf id default set cos mycos
```

### Operations, transfers

Let's assume you created a default configuration from once of the two previous steps (else specify the access options on command lines).

A subset of `node` plugin operations are supported, basically node API:

```bash
ascli cos node info
ascli cos node upload 'faux:///sample1G?1g'
```

Note: we generate a dummy file `sample1G` of size 2GB using the `faux` PVCL (man ascp and section above), but you can of course send a real file by specifying a real file instead.

### COS sample commands

```bash
cos -N --bucket=my_icos_bucket_name --endpoint=my_icos_bucket_endpoint --apikey=my_icos_bucket_apikey --crn=my_icos_resource_instance_id node info
cos -N --bucket=my_icos_bucket_name --region=my_icos_bucket_region --service-credentials=@json:@file:service_creds.json node info
cos node access_key show self
cos node download testfile.bin --to-folder=.
cos node info
cos node upload testfile.bin
```

## Plugin: IBM Aspera Sync

A basic plugin to start an "async" using `ascli`.
The main advantage is the possibility to start from ma configuration file, using `ascli` standard options.

### Sync sample commands

```bash
sync start --parameters=@json:'{"sessions":[{"name":"test","reset":true,"remote_dir":"/sync_test","local_dir":"contents","host":"my_remote_host","tcp_port":33001,"user":"my_remote_user","private_key_path":"my_local_user_key"}]}'
```

## Plugin: Preview

The `preview` generates thumbnails (office, images, video) and video previews on storage for use primarily in the Aspera on Cloud application.
It uses the **node API** of Aspera HSTS and requires use of Access Keys and it's **storage root**.
Several parameters can be used to tune several aspects:

* Methods for detection of new files needing generation
* Methods for generation of video preview
* Parameters for video handling

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

If another folder is configured on the HSTS, then specify it to `ascli` using the option `previews_folder`.

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

* ImageMagick : `convert` `composite`
* OptiPNG : `optipng`
* FFmpeg : `ffmpeg` `ffprobe`
* Libreoffice : `libreoffice`

Here shown on Redhat/CentOS.

Other OSes should work as well, but are note tested.

To check if all tools are found properly, execute:

```bash
ascli preview check
```

#### Image: ImageMagick and optipng

```bash
yum install -y ImageMagick optipng
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

* CentOS 8

```bash
dnf install unoconv
```

* Amazon Linux

```bash
amazon-linux-extras enable libreoffice
yum clean metadata
yum install libreoffice-core libreoffice-calc libreoffice-opensymbol-fonts libreoffice-ure libreoffice-writer libreoffice-pyuno libreoffice-impress
wget https://raw.githubusercontent.com/unoconv/unoconv/master/unoconv
mv unoconv /usr/bin
chmod a+x /usr/bin/unoconv
```

### Configuration

The preview generator is run as a user, preferably a regular user (not root). When using object storage, any user can be used, but when using local storage it is usually better to use the user `xfer`, as uploaded files are under this identity: this ensures proper access rights. (we will assume this)

Like any `ascli` commands, parameters can be passed on command line or using a configuration [option preset](#lprt).  The configuration file must be created with the same user used to run so that it is properly used on runtime.

Note that the `xfer` user has a special protected shell: `aspshell`, so changing identity requires specification of alternate shell:

```bash
su -s /bin/bash - xfer

ascli config preset update previewconf --url=https://localhost:9092 --username=my_access_key --password=my_secret --skip-types=office --lock-port=12346

ascli config preset set default preview previewconf
```

Here we assume that Office file generation is disabled, else remove this option.
`lock_port` prevents concurrent execution of generation when using a scheduler.

One can check if the access key is well configured using:

```bash
ascli -Ppreviewconf node browse /
```

This shall list the contents of the storage root of the access key.

### Execution

The tool intentionally supports only a "one shot" mode (no infinite loop) in order to avoid having a hanging process or using too many resources (calling REST api too quickly during the scan or event method).
It needs to be run on a regular basis to create or update preview files. For that use your best
reliable scheduler. For instance use "CRON" on Linux or Task Scheduler on Windows.

Typically, for "Access key" access, the system/transfer is `xfer`. So, in order to be consistent have generate the appropriate access rights, the generation process should be run as user `xfer`.

Lets do a one shot test, using the configuration previously created:

```bash
su -s /bin/bash - xfer

ascli preview scan --overwrite=always
```

When the preview generator is first executed it will create a file: `.aspera_access_key`
in the previews folder which contains the access key used.
On subsequent run it reads this file and check that previews are generated for the same access key, else it fails. This is to prevent clash of different access keys using the same root.

### Configuration for Execution in scheduler

Here is an example of configuration for use with cron on Linux.
Adapt the scripts to your own preference.

We assume here that a configuration preset was created as shown previously.

Lets first setup a script that will be used in the scheduler and sets up the environment.

Example of startup script `cron_ascli`, which sets the Ruby environment and adds some timeout protection:

```bash
 #!/bin/bash
 # set a timeout protection, just in case
case "$*" in *trev*) tmout=10m ;; *) tmout=30m ;; esac
. /etc/profile.d/rvm.sh
rvm use 2.6 --quiet
exec timeout ${tmout} ascli "${@}"
```

Here the cronjob is created for user `xfer`.

```bash
crontab<<EOF
0    * * * *  /home/xfer/cron_ascli preview scan --logger=syslog --display=error
2-59 * * * *  /home/xfer/cron_ascli preview trev --logger=syslog --display=error
EOF
```

Note that the logging options are kept in the cronfile instead of conf file to allow execution on command line with output on command line.

### Candidate detection for creation or update (or deletion)

The tool generates preview files using those commands:

* `trevents` : only recently uploaded files will be tested (transfer events)
* `events` : only recently uploaded files will be tested (file events: not working)
* `scan` : recursively scan all files under the access key&apos;s "storage root"
* `test` : test using a local file

Once candidate are selected, once candidates are selected,
a preview is always generated if it does not exist already,
else if a preview already exist, it will be generated
using one of three values for the `overwrite` option:

* `always` : preview is always generated, even if it already exists and is newer than original
* `never` : preview is generated only if it does not exist already
* `mtime` : preview is generated only if the original file is newer than the existing

Deletion of preview for deleted source files: not implemented yet (TODO).

If the `scan` or `events` detection method is used, then the option : `skip_folders` can be used to skip some folders. It expects a list of path relative to the storage root (docroot) starting with slash, use the `@json:` notation, example:

```bash
ascli preview scan --skip-folders=@json:'["/not_here"]'
```

The option `folder_reset_cache` forces the node service to refresh folder contents using various methods.

When scanning the option `value` has the same behavior as for the `node find` command.

For instance to filter out files beginning with `._` do:

```bash
... --value='exec:!f["name"].start_with?("._") or f["name"].eql?(".DS_Store")'
```

### Preview File types

Two types of preview can be generated:

* png: thumbnail
* mp4: video preview (only for video)

Use option `skip_format` to skip generation of a format.

### Supported input Files types

The preview generator supports rendering of those file categories:

* image
* pdf
* plaintext
* office
* video

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

* any OS:

  * Examine the error message
  * Download the file: <https://gitlab.freedesktop.org/xdg/shared-mime-info/-/raw/master/data/freedesktop.org.xml.in>
  * move and rename this file to one of the locations expected by mimemagic as specified in the error message

* Windows:

  * Download the file: <https://gitlab.freedesktop.org/xdg/shared-mime-info/-/raw/master/data/freedesktop.org.xml.in>
  * Place this file in the root of Ruby (or elsewhere): `C:\RubyVV-x64\freedesktop.org.xml.in`
  * Set a global variable using `SystemPropertiesAdvanced.exe` or using `cmd` (replace `VV` with version) to the exact path of this file:

  ```cmd
  SETX FREEDESKTOP_MIME_TYPES_PATH C:\RubyVV-x64\freedesktop.org.xml.in
  ```

  * Close the `cmd` and restart a new one if needed to get refreshed env vars

* Linux:

```bash
yum install shared-mime-info
```

* macOS:

```bash
brew install shared-mime-info
```

### Access to original files and preview creation

Standard open source tools are used to create thumbnails and video previews.
Those tools require that original files are accessible in the local file system and also write generated files on the local file system.
The tool provides 2 ways to read and write files with the option: `file_access`

If the preview generator is run on a system that has direct access to the file system, then the value `local` can be used. In this case, no transfer happen, source files are directly read from the storage, and preview files
are directly written to the storage.

If the preview generator does not have access to files on the file system (it is remote, no mount, or is an object storage), then the original file is first downloaded, then the result is uploaded, use method `remote`.

### Preview sample commands

```bash
preview check --skip-types=office
preview folder 1 --skip-types=office --log-level=info --file-access=remote --ts=@json:'{"target_rate_kbps":1000000}'
preview scan --skip-types=office --log-level=info
preview test --case=test mp4 my_file_mxf --video-conversion=blend --log-level=debug
preview test --case=test mp4 my_file_mxf --video-conversion=clips --log-level=debug
preview test --case=test mp4 my_file_mxf --video-conversion=reencode --log-level=debug
preview test --case=test png my_file_dcm --log-level=debug
preview test --case=test png my_file_docx --log-level=debug
preview test --case=test png my_file_mxf --video-png-conv=animated --log-level=debug
preview test --case=test png my_file_mxf --video-png-conv=fixed --log-level=debug
preview test --case=test png my_file_pdf --log-level=debug
preview trevents --once-only=yes --skip-types=office --log-level=info
```

## SMTP for email notifications

Aspera CLI can send email, for that setup SMTP configuration. This is done with option `smtp`.

The `smtp` option is a hash table (extended value) with the following fields:
<table>
<tr><th>field</th><th>default</th><th>example</th><th>description</th></tr>
<tr><td>`server`</td><td>-</td><td>smtp.gmail.com</td><td>SMTP server address</td></tr>
<tr><td>`tls`</td><td>true</td><td>false</td><td>use of TLS</td></tr>
<tr><td>`port`</td><td>587 for tls<br/>25 else</td><td>587</td><td>port for service</td></tr>
<tr><td>`domain`</td><td>domain of server</td><td>gmail.com</td><td>email domain of user</td></tr>
<tr><td>`username`</td><td>-</td><td>john@example.com</td><td>user to authenticate on SMTP server, leave empty for open auth.</td></tr>
<tr><td>`password`</td><td>-</td><td>MyP@ssword</td><td>password for above username</td></tr>
<tr><td>`from_email`</td><td>username if defined</td><td>laurent.martin.l@gmail.com</td><td>address used if received replies</td></tr>
<tr><td>`from_name`</td><td>same as email</td><td>John Wayne</td><td>display name of sender</td></tr>
</table>

### Example of configuration

```bash
ascli config preset set smtp_google server smtp.google.com
ascli config preset set smtp_google username john@gmail.com
ascli config preset set smtp_google password _pass_here_
```

or

```javascript
ascli config preset init smtp_google @json:'{"server":"smtp.google.com","username":"john@gmail.com","password":"_pass_here_"}'
```

or

```bash
ascli config preset update smtp_google --server=smtp.google.com --username=john@gmail.com --password=_pass_here_
```

Set this configuration as global default, for instance:

```bash
ascli config preset set cli_default smtp @val:@preset:smtp_google
ascli config preset set default config cli_default
```

### Email templates

Sent emails are built using a template that uses the [ERB](https://www.tutorialspoint.com/ruby/eruby.htm) syntax.

The template is the full SMTP message, including headers.

The following variables are defined by default:

* from_name
* from_email
* to

Other variables are defined depending on context.

### Test

Check settings with `smtp_settings` command. Send test email with `email_test`.

```bash
ascli config --smtp=@preset:smtp_google smtp
ascli config --smtp=@preset:smtp_google email --notif-to=sample.dest@example.com
```

### Notifications for transfer status

An e-mail notification can be sent upon transfer success and failure (one email per transfer job, one job being possibly multi session, and possibly after retry).

To activate, use option `notif_to`.

A default e-mail template is used, but it can be overridden with option `notif_template`.

The environment provided contains the following additional variables:

* subject
* body
* global_transfer_status
* ts

Example of template:

```text
From: <%=from_name%> <<%=from_email%>>
To: <<%=to%>>
Subject: <%=subject%>

Transfer is: <%=global_transfer_status%>
```

## Tool: `asession`

This gem comes with a second executable tool providing a simplified standardized interface to start a FASP session: `asession`.

It aims at simplifying the startup of a FASP session from a programmatic stand point as formatting a [*transfer-spec*](#transferspec) is:

* common to Aspera Node API (HTTP POST /ops/transfer)
* common to Aspera Connect API (browser javascript startTransfer)
* easy to generate by using any third party language specific JSON library

Hopefully, IBM integrates this diectly in `ascp`, and this tool is made redundant.

This makes it easy to integrate with any language provided that one can spawn a sub process, write to its STDIN, read from STDOUT, generate and parse JSON.

The tool expect one single argument: a [*transfer-spec*](#transferspec).

If no argument is provided, it assumes a value of: `@json:@stdin:`, i.e. a JSON formatted [*transfer-spec*](#transferspec) on stdin.

Note that if JSON is the format, one has to specify `@json:` to tell the tool to decode the hash using JSON.

During execution, it generates all low level events, one per line, in JSON format on stdout.

Note that there are special "extended" [*transfer-spec*](#transferspec) parameters supported by `asession`:

* `EX_loglevel` to change log level of the tool
* `EX_file_list_folder` to set the folder used to store (exclusively, because of garbage collection) generated file lists. By default it is `[system tmp folder]/[username]_asession_filelists`

Note that in addition, many "EX_" [*transfer-spec*](#transferspec) parameters are supported for the [`direct`](#agt_direct) transfer agent (used by `asession`), refer to section [*transfer-spec*](#transferspec).

### Comparison of interfaces

<table>
<tr><th>feature/tool</th><th>asession</th><th>ascp</th><th>FaspManager</th><th>Transfer SDK</th></tr>
<tr><td>language integration</td><td>any</td><td>any</td><td>C/C++<br/>C#/.net<br/>Go<br/>Python<br/>java<br/></td><td>many</td></tr>
<tr><td>required additional components to ascp</td><td>Ruby<br/>Aspera</td><td>-</td><td>library<br/>(headers)</td><td>daemon</td></tr>
<tr><td>startup</td><td>JSON on stdin<br/>(standard APIs:<br/>JSON.generate<br/>Process.spawn)</td><td>command line arguments</td><td>API</td><td>daemon</td></tr>
<tr><td>events</td><td>JSON on stdout</td><td>none by default<br/>or need to open management port<br/>and proprietary text syntax</td><td>callback</td><td>callback</td></tr>
<tr><td>platforms</td><td>any with ruby and ascp</td><td>any with ascp (and SDK if compiled)</td><td>any with ascp</td><td>any with ascp and transfer daemon</td></tr></table>

### Simple session

Create a file `session.json` with:

```json
{"remote_host":"demo.asperasoft.com","remote_user":"asperaweb","ssh_port":33001,"remote_password":"_pass_here_","direction":"receive","destination_root":"./test.dir","paths":[{"source":"/aspera-test-dir-tiny/200KB.1"}],"resume_level":"none"}
````

Then start the session:

```
asession < session.json
```

### Asynchronous commands and Persistent session

`asession` also supports asynchronous commands (on the management port). Instead of the traditional text protocol as described in ascp manual, the format for commands is: one single line per command, formatted in JSON, where parameters shall be "snake" style, for example: `LongParameter` -&gt; `long_parameter`

This is particularly useful for a persistent session ( with the [*transfer-spec*](#transferspec) parameter: `"keepalive":true` )

```javascript
asession
{"remote_host":"demo.asperasoft.com","ssh_port":33001,"remote_user":"asperaweb","remote_password":"_pass_here_","direction":"receive","destination_root":".","keepalive":true,"resume_level":"none"}
{"type":"START","source":"/aspera-test-dir-tiny/200KB.2"}
{"type":"DONE"}
```

(events from FASP are not shown in above example. They would appear after each command)

### Example of language wrapper

Nodejs: [https://www.npmjs.com/package/aspera](https://www.npmjs.com/package/aspera)

### Help

```bash
asession -h
USAGE
    asession
    asession -h|--help
    asession <transfer spec extended value>
    
    If no argument is provided, default will be used: @json:@stdin
    -h, --help display this message
    <transfer spec extended value> a JSON value for transfer_spec, using the prefix: @json:
    The value can be either:
       the JSON description itself, e.g. @json:'{"xx":"yy",...}'
       @json:@stdin, if the JSON is provided from stdin
       @json:@file:<path>, if the JSON is provided from a file
    Asynchronous commands can be provided on STDIN, examples:
       {"type":"START","source":"/aspera-test-dir-tiny/200KB.2"}
       {"type":"START","source":"xx","destination":"yy"}
       {"type":"DONE"}
Note: debug information can be placed on STDERR, using the "EX_loglevel" parameter in transfer spec (debug=0)
EXAMPLES
    asession @json:'{"remote_host":"demo.asperasoft.com","remote_user":"asperaweb","ssh_port":33001,"remote_password":"demoaspera","direction":"receive","destination_root":"./test.dir","paths":[{"source":"/aspera-test-dir-tiny/200KB.1"}]}'
    echo '{"remote_host":...}'|asession @json:@stdin

```

## Hot folder

### Requirements

`ascli` maybe used as a simple hot folder engine.
A hot folder being defined as a tool that:

* locally (or remotely) detects new files in a top folder
* send detected files to a remote (respectively, local) repository
* only sends new files, do not re-send already sent files
* optionally: sends only files that are not still "growing"
* optionally: after transfer of files, deletes or moves to an archive

In addition: the detection should be made "continuously" or on specific time/date.

### Setup procedure

The general idea is to rely on :

* existing `ascp` features for detection and transfer
* take advantage of `ascli` configuration capabilities and server side knowledge
* the OS scheduler for reliability and continuous operation

#### ascp features

Interesting ascp features are found in its arguments: (see ascp manual):

* `ascp` already takes care of sending only "new" files: option `-k 1,2,3` (`resume_policy`)
* `ascp` has some options to remove or move files after transfer: `--remove-after-transfer`, `--move-after-transfer`, `--remove-empty-directories` (`remove_after_transfer`, `move_after_transfer`, `remove_empty_directories`)
* `ascp` has an option to send only files not modified since the last X seconds: `--exclude-newer-than`, `--exclude-older-than` (`exclude_newer_than`,`exclude_older_than`)
* `--src-base` (`src_base`) if top level folder name shall not be created on destination

Note that:

* `ascli` takes transfer parameters exclusively as a [*transfer-spec*](#transferspec), with `--ts` parameter.
* most, but not all, native `ascp` arguments are available as standard [*transfer-spec*](#transferspec) parameters
* native ascp arguments can be provided with the [*transfer-spec*](#transferspec) parameter: `EX_ascp_args` (array), only for the [`direct`](#agt_direct) transfer agent (not others, like connect or node)

#### server side and configuration

Virtually any transfer on a "repository" on a regular basis might emulate a hot folder.
> file detection is not based on events (inotify, etc...), but on a simple folder scan on source side.

> parameters may be saved in a [option preset](#lprt) and used with `-P`.

#### Scheduling

Once `ascli` parameters are defined, run the command using the OS native scheduler, e.g. every minutes, or 5 minutes, etc...
Refer to section [Scheduling](#scheduling). (on use of option `lock_port`)

### Example: upload hot folder

```javascript
ascli server upload source_hot --to-folder=/Upload/target_hot --lock-port=12345 --ts=@json:'{"remove_after_transfer":true,"remove_empty_directories":true,"exclude_newer_than:-8,"src_base":"source_hot"}'
```

The local folder (here, relative path: `source_hot`) is sent (upload) to an aspera server.
Source files are deleted after transfer.
Growing files will be sent only once they don't grow anymore (based on an 8-second cooloff period).
If a transfer takes more than the execution period, then the subsequent execution is skipped (`lock_port`) preventing multiple concurrent runs.

### Example: unidirectional synchronization

```javascript
ascli server upload source_sync --to-folder=/Upload/target_sync --lock-port=12345 --ts=@json:'{"resume_policy":"sparse_csum","exclude_newer_than:-8,"src_base":"source_sync"}'
```
## Health check and Nagios

Most plugin provide a `health` command that will check the health status of the application. Example:

```bash
ascli console health
```

```output
+--------+-------------+------------+
| status | component   | message    |
+--------+-------------+------------+
| ok     | console api | accessible |
+--------+-------------+------------+
```

Typically, the health check uses the REST API of the application with the following exception: the `server` plugin allows checking health by:

* issuing a transfer to the server
* checking web app status with `asctl all:status`
* checking daemons process status

`ascli` can be called by Nagios to check the health status of an Aspera server. The output can be made compatible to Nagios with option `--format=nagios` :

```bash
ascli server health transfer --to-folder=/Upload --format=nagios --progress=none
```

```output
OK - [transfer:ok]
```

```bash
ascli server health asctlstatus --cmd_prefix='sudo ' --format=nagios
```

```output
OK - [NP:running, MySQL:running, Mongrels:running, Background:running, DS:running, DB:running, Email:running, Apache:running]
```

## Ruby Module: `Aspera`

Main components:

* `Aspera` generic classes for REST and OAuth
* `Aspera::Fasp`: starting and monitoring transfers. It can be considered as a FASPManager class for Ruby.
* `Aspera::Cli`: `ascli`.

A working example can be found in the gem, example:

```bash
ascli config gem path
```

```bash
cat $(ascli config gem path)/../examples/transfer.rb
```

This sample code shows some example of use of the API as well as REST API.
Note: although nice, it's probably a good idea to use RestClient for REST.

Example of use of the API of Aspera on Cloud:

```ruby
require 'aspera/aoc'

aoc=Aspera::AoC.new(url: 'https://sedemo.ibmaspera.com',auth: :jwt, scope: 'user:all', private_key: File.read(File.expand_path('~/.aspera/ascli/aspera_on_cloud_key')),username: 'laurent.martin.aspera@fr.ibm.com',subpath: 'api/v1')

aoc.read('self')
```

<https://github.com/IBM/aspera-cli/blob/main/examples/aoc.rb>

## Changes (Release notes)

See <CHANGELOG.md>

## History

When I joined Aspera, there was only one CLI: `ascp`, which is the implementation of the FASP protocol, but there was no CLI to access the various existing products (Server, Faspex, Shares). Once, Serban (founder) provided a shell script able to create a Faspex Package using Faspex REST API. Since all products relate to file transfers using FASP (ascp), I thought it would be interesting to have a unified CLI for transfers using FASP. Also, because there was already the `ascp` tool, I thought of an extended tool : `eascp.pl` which was accepting all `ascp` options for transfer but was also able to transfer to Faspex and Shares (destination was a kind of URI for the applications).

There were a few pitfalls:

* The tool was written in the aging `perl` language while most Aspera application products (but the Transfer Server) are written in `ruby`.
* The tool was only for transfers, but not able to call other products APIs

So, it evolved into `ascli`:

* portable: works on platforms supporting `ruby` (and `ascp`)
* easy to install with the `gem` utility
* supports transfers with multiple [Transfer Agents](#agents), that&apos;s why transfer parameters moved from ascp command line to [*transfer-spec*](#transferspec) (more reliable , more standard)
* `ruby` is consistent with other Aspera products

## Common problems

### Error: "Remote host is not who we expected"

Cause: `ascp` >= 4.x checks fingerprint of highest server host key, including ECDSA. `ascp` < 4.0 (3.9.6 and earlier) support only to RSA level (and ignore ECDSA presented by server). `aspera.conf` supports a single fingerprint.

Workaround on client side: To ignore the certificate (SSH fingerprint) add option on client side (this option can also be added permanently to the config file):

```javascript
--ts=@json:'{"sshfp":null}'
```

Workaround on server side: Either remove the fingerprint from `aspera.conf`, or keep only RSA host keys in `sshd_config`.

References: ES-1944 in release notes of 4.1 and to [HSTS admin manual section "Configuring Transfer Server Authentication With a Host-Key Fingerprint"](https://www.ibm.com/docs/en/ahts/4.2?topic=upgrades-configuring-ssh-server).

### Error "can't find header files for ruby"

Some Ruby gems dependencies require compilation of native parts (C).
This also requires Ruby header files.
If Ruby was installed as a Linux Packages, then also install ruby dev elopment package:
`ruby-dev` ir `ruby-devel`, depending on distribution.

### ED255519 key not supported

ED25519 keys are deactivated since version 0.9.24 so this type of key will just be ignored.

Without this deactivation, if such key was present the following error was generated:

```output
OpenSSH keys only supported if ED25519 is available
```

Which meant that you do not have ruby support for ED25519 SSH keys.
You may either install the suggested Gems, or remove your ed25519 key from your `.ssh` folder to solve the issue.
