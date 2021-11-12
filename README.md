[comment1]: # (Do not edit this README.md, edit docs/README.erb.md, for details, read docs/README.md)
<font size="+12"><center>`ascli` : Command Line Interface for IBM Aspera products</center></font>

Version : 4.4.0.pre

_Laurent/2016-2021_

This gem provides the `ascli` Command Line Interface to IBM Aspera software.

`ascli` is a also great tool to learn Aspera APIs.

Ruby Gem: [https://rubygems.org/gems/aspera-cli](https://rubygems.org/gems/aspera-cli)

Ruby Doc: [https://www.rubydoc.info/gems/aspera-cli](https://www.rubydoc.info/gems/aspera-cli)

Required Ruby version: > 2.4

# <a name="when_to_use"></a>When to use and when not to use

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
* Transfer SDK : with gRPC interface and laguage stubs (C, C++, Python, .NET/C#, java, ruby, etc...)

Using APIs (application REST API and transfer SDK) will prove to be easier to develop and maintain.

For scripting and ad'hoc command line operations, `ascli` is perfect.

# Notations

In examples, command line operations (starting with `$`) are shown using a standard shell: `bash` or `zsh`.
Prompt `# ` refers to user `root`, prompt `xfer$ ` refer to user `xfer`.

Command line parameters in examples beginning with `my_`, like `my_param_value` are user-provided value and not fixed value commands.

# <a name="parsing"></a>Shell and Command line parsing

`ascli` is typically executed in a shell, either interactively or in a script. `ascli` receives its arguments from this shell.

On Linux and Unix environments, this is typically a POSIX shell (bash, zsh, ksh, sh). In this environment shell command line parsing applies before `ascli` (Ruby) is executed, e.g. [bash shell operation](https://www.gnu.org/software/bash/manual/bash.html#Shell-Operation). Ruby receives a list parameters and gives it to `ascli`. So special character handling (quotes, spaces, env vars, ...) is done in the shell.

On Windows, `cmd.exe` is typically used. Windows process creation does not receive the list of arguments but just the whole line. It's up to the program to parse arguments. Ruby follows the Microsoft C/C++ parameter parsing rules.

* [Windows: How Command Line Parameters Are Parsed](https://daviddeley.com/autohotkey/parameters/parameters.htm#RUBY)
* [Understand Quoting and Escaping of Windows Command Line Arguments](http://www.windowsinspired.com/understanding-the-command-line-string-and-arguments-received-by-a-windows-program/)

In case of doubt of argument values after parsing test like this:

```
$ ascli conf echo "Hello World" arg2 3
"Hello World"
ERROR: Argument: unprocessed values: ["arg2", "3"]
```

`echo` displays the value of the first argument using ruby syntax (strings get double quotes) after command line parsing (shell) and extended value parsing (ascli), next command line arguments are shown in the error message.

# Quick Start

This section guides you from installation, first use and advanced use.

First, follow the section: [Installation](#installation) (Ruby, Gem, FASP) to start using `ascli`.

Once the gem is installed, `ascli` shall be accessible:

```
$ ascli --version
4.4.0.pre
```

## First use

Once installation is completed, you can proceed to the first use with a demo server:

If you want to test with Aspera on Cloud, jump to section: [Wizard](#aocwizard)

To test with Aspera demo transfer server, setup the environment and then test:

```
$ ascli config initdemo
$ ascli server browse /
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

```
$ ascli config id myserver update --url=ssh://demo.asperasoft.com:33001 --username=asperaweb --password=_demo_pass_
updated: myserver
$ ascli config id default set server myserver
updated: default&rarr;server to myserver
$ ascli server browse /aspera-test-dir-large
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
$ ascli server download /aspera-test-dir-large/200MB
Time: 00:00:02 ========================================================================================================== 100% 100 Mbps Time: 00:00:00
complete
```

## Going further

Get familiar with configuration, options, commands : [Command Line Interface](#cli).

Then, follow the section relative to the product you want to interact with ( Aspera on Cloud, Faspex, ...) : [Application Plugins](plugins)

# <a name="installation"></a>Installation

It is possible to install *either* directly on the host operating system (Linux, Windows, Macos) or as a docker container.

The direct installation is recommended and consists in installing:

* [Ruby](#ruby) version > 2.4
* [aspera-cli](#the_gem)
* [Aspera SDK (ascp)](#fasp_prot)

The following sections provide information on the various installation methods.

An internet connection is required for the installation. If you dont have internet for the installation, refer to section [Installation without internet access](#offline_install).

## Docker container

Use this method only if you know what you do, else use the standard recommended method as described here above.

This method installs a docker image that contains: Ruby, ascli and the FASP sdk.

The image is: [https://hub.docker.com/r/martinlaurent/ascli](https://hub.docker.com/r/martinlaurent/ascli)

Ensure that you have Docker installed.

```
$ docker --version
```

Download the wrapping script:

```
$ curl -o ascli https://raw.githubusercontent.com/IBM/aspera-cli/develop/bin/dascli
$ chmod a+x ascli
```

Install the container image:

```
$ ./ascli install
```

Start using it !

Note that the tool is run in the container, so transfers are also executed in the container, not calling host.

The wrapping script maps the container folder `/usr/src/app/config` to configuration folder `$HOME/.aspera/ascli` on host.

To transfer to/from the native host, you will need to map a volume in docker or use the config folder (already mapped).
To add local storage as a volume edit the script: ascli and add a `--volume` stanza.

## <a name="ruby"></a>Ruby

Use this method to install on the native host.

A ruby interpreter is required to run the tool or to use the gem and tool.

Required Ruby version: > 2.4. Ruby version 3 is also supported.

*Ruby can be installed using any method* : rpm, yum, dnf, rvm, brew, windows installer, ... .

Refer to the following sections for a proposed method for specific operating systems.

The recommended installation method is `rvm` for systems with "bash-like" shell (Linux, Macos, Windows with cygwin, etc...).
If the generic install is not suitable (e.g. Windows, no cygwin), you can use one of OS-specific install method.
If you have a simpler better way to install Ruby version > 2.4 : use it !

### Generic: RVM: single user installation (not root)

Use this method which provides more flexibility.

Install "rvm": follow [https://rvm.io/](https://rvm.io/) :

Install the 2 keys

```
$ gpg2 --keyserver hkp://pool.sks-keyservers.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
```

Execute the shell/curl command. As regular user, it install in the user's home: `~/.rvm` .

```
$ \curl -sSL https://get.rvm.io | bash -s stable
```

If you keep the same terminal (ont needed if re-login):

```
$ source ~/.rvm/scripts/rvm
```

It is advised to get one of the pre-compiled ruby version, you can list with:

```
$ rvm list --remote
```

Install the chosen pre-compiled Ruby version:

```
$ rvm install 2.7.2 --binary
```

Ruby is now installed for the user, go on to Gem installation.

### Generic: RVM: global installation (as root)

Follow the same method as single user install, but execute as "root".

As root, it installs by default in /usr/local/rvm for all users and creates `/etc/profile.d/rvm.sh`.
One can install in another location with :

```
# curl -sSL https://get.rvm.io | bash -s -- --path /usr/local
```

As root, make sure this will not collide with other application using Ruby (e.g. Faspex).
If so, one can rename the login script: `mv /etc/profile.d/rvm.sh /etc/profile.d/rvm.sh.ok`.
To activate ruby (and ascli) later, source it:

```
# source /etc/profile.d/rvm.sh.ok
# rvm version
```

### Windows: Installer

Install Latest stable Ruby using [https://rubyinstaller.org/](https://rubyinstaller.org/) :

* Go to "Downloads".
* Select the Ruby 2 version "without devkit", x64 corresponding to the one recommended "with devkit". Devkit is not needed.
* At the end of the installer uncheck the box to skip the installation of "MSys2": not needed.

### macOS: pre-installed or `brew`

MacOS 10.13+ (High Sierra) comes with a recent Ruby. So you can use it directly. You will need to install aspera-cli using `sudo` :

```
$ sudo gem install aspera-cli --pre
```

Alternatively, if you use [Homebrew](https://brew.sh/) already you can install Ruby with it:

```
$ brew install ruby
```

### Linux: package

If your Linux distribution provides a standard ruby package, you can use it provided that the version is compatible (check at beginning of section).

Example:

```
# yum install -y ruby rubygems ruby-json
```

One can cleanup the whole yum-installed ruby environment like this to uninstall:

```
gem uninstall $(ls $(gem env gemdir)/gems/|sed -e 's/-[^-]*$//'|sort -u)
yum remove -y ruby ruby-libs
```

### Other Unixes: Aix, etc...

If your unix do not provide a pre-built ruby, you can get it using one of those
[methods](https://www.ruby-lang.org/en/documentation/installation/)

For instance to build from source, and install in `/opt/ruby` :

```
# wget https://cache.ruby-lang.org/pub/ruby/2.7/ruby-2.7.2.tar.gz
# gzip -d ruby-2.7.2.tar.gz
# tar xvf ruby-2.7.2.tar
# cd ruby-2.7.2
# ./configure --prefix=/opt/ruby
# make ruby.imp
# make
# make install
```

### <a name="offline_install"></a>Installation without internet access

Note that currently no pre-packaged version exist yet.
A method to build one provided here:

On a server with the same OS version and with internet access follow the "Generic single user installation" method.

Then create an archive:

```
$ cd
$ tar zcvf rvm-ascli.tgz .rvm
```

Get the Aspera SDK. Execute:

```
$ ascli conf --show-config|grep sdk_url
```

Then download the SDK archive from that URL.

Another method for the SDK is to install the SDK (`ascli conf ascp install`) on the first system, and archive `$HOME/.aspera`.

Transfer those 2 archives to the target system without internet access.

On the target system:

* Extract the RVM archive either in a global location, or in a user's home folder : `path_to_rvm_root`
* in the user's `.profile` add this line: (replace `path_to_rvm_root` with the actual location)

```
source path_to_rvm_root/scripts/rvm
rvm use 2.7.2
```

For the SDK, either install from archive:

```
$ ascli conf ascp install --sdk-url=file:///SDK.zip
```

or restore the `$HOME/.aspera` folder for the user.

## <a name="the_gem"></a>`aspera-cli` gem

Once you have Ruby and rights to install gems: Install the gem and its dependencies:

```
# gem install aspera-cli --pre
```

To upgrade to the latest version:

```
# gem update aspera-cli
```

`ascli` checks every week if a new version is available and notify the user in a WARN log. To de-activate this feature set the option `version_check_days` to `0`, or specify a different period in days.

To check manually:

```
# ascli conf check_update
```



## <a name="fasp_prot"></a>FASP Protocol

Most file transfers will be done using the FASP protocol, using `ascp`.
Only two additional files are required to perform an Aspera Transfer, which are part of Aspera SDK:

* ascp
* aspera-license (in same folder, or ../etc)

This can be installed either be installing an Aspera transfer sofware, or using an embedded command:

```
$ ascli conf ascp install
```

If a local SDK installation is prefered instead of fetching from internet: one can specify the location of the SDK file:

```
$ curl -Lso SDK.zip https://ibm.biz/aspera_sdk
$ ascli conf ascp install --sdk-url=file:///SDK.zip
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
Use of a local client ([`direct`](#direct) transfer agent) is one of them, but other methods are available. Refer to section: [Transfer Agents](#agents)

## <a name="offline_install"></a>Offline Installation (without internet)

The procedure consists in:

* Follow the non-root installation procedure with RVM, including gem
* archive (zip, tar) the main RVM folder (includes ascli):

```
$ cd ~
$ tar zcvf rvm_ascli.tgz .rvm
```

* retrieve the SDK:

```
$ curl -Lso SDK.zip https://ibm.biz/aspera_sdk
```

* on the system without internet access:

```
$ cd ~
$ tar zxvf rvm_ascli.tgz
$ source ~/.rvm/scripts/rvm
$ ascli conf ascp install --sdk-url=file:///SDK.zip
```

# <a name="cli"></a>Command Line Interface: `ascli`

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
* Transfer parameters can be altered by modification of _transfer-spec_, this includes requiring multi-session
* Allows transfers from products to products, essentially at node level (using the node transfer agent)
* Supports FaspStream creation (using Node API)
* Supports Watchfolder creation (using Node API)
* Additional command plugins can be written by the user
* Supports download of faspex and Aspera on Cloud "external" links
* Supports "legacy" ssh based FASP transfers and remote commands (ascmd)

Basic usage is displayed by executing:

```
$ ascli -h
```

Refer to sections: [Usage](#usage) and [Sample Commands](#commands).

Not all `ascli` features are fully documented here, the user may explore commands on the command line.

## Arguments : Commands and options

Arguments are the units of command line, as parsed by the shell, typically separated by spaces (and called "argv").

There are two types of arguments: Commands and Options. Example :

```
$ ascli command --option-name=VAL1 VAL2
```

* executes _command_: `command`
* with one _option_: `option_name`
* this option has a _value_ of: `VAL1`
* the command has one additional _argument_: `VAL2`

When the value of a command, option or argument is constrained by a fixed list of values, it is possible to use the first letters of the value only, provided that it uniquely identifies a value. For example `ascli conf ov` is the same as `ascli config overview`.

The value of options and arguments is evaluated with the [Extended Value Syntax](#extended).

### Options

All options, e.g. `--log-level=debug`, are command line arguments that:

* start with `--`
* have a name, in lowercase, using `-` as word separator in name  (e.g. `--log-level=debug`)
* have a value, separated from name with a `=`
* can be used by prefix, provided that it is unique. E.g. `--log-l=debug` is the same as `--log-level=debug`

Exceptions:

* some options accept a short form, e.g. `-Ptoto` is equivalent to `--preset=toto`, refer to the manual or `-h`.
* some options (flags) don't take a value, e.g. `-r`
* the special option `--` stops option processing and is ignored, following command line arguments are taken as arguments, including the ones starting with a `-`. Example:

```
$ ascli config echo -- --sample
"--sample"
```

Note that `--sample` is taken as an argument, and not option.

Options can be optional or mandatory, with or without (hardcoded) default value. Options can be placed anywhere on comand line and evaluated in order.

The value for _any_ options can come from the following locations (in this order, last value evaluated overrides previous value):

* [Configuration file](#configfile).
* Environment variable
* Command line

Environment variable starting with prefix: ASCLI_ are taken as option values,
e.g. `ASCLI_OPTION_NAME` is for `--option-name`.

Options values can be displayed for a given command by providing the `--show-config` option: `ascli node --show-config`

### Commands and Arguments

Command line arguments that are not options are either commands or arguments. If an argument must begin with `-`, then either use the `@val:` syntax (see [Extended Values](#extended)), or use the `--` separator (see above).

## Interactive Input

Some options and parameters are mandatory and other optional. By default, the tool will ask for missing mandatory options or parameters for interactive execution.

The behaviour can be controlled with:

* --interactive=&lt;yes|no&gt; (default=yes if STDIN is a terminal, else no)
   * yes : missing mandatory parameters/options are asked to the user
   * no : missing mandatory parameters/options raise an error message
* --ask-options=&lt;yes|no&gt; (default=no)
   * optional parameters/options are asked to user

## Output

Command execution will result in output (terminal, stdout/stderr).
The information displayed depends on the action.

### Types of output data

Depending on action, the output will contain:

* `single_object` : displayed as a 2 dimensional table: one line per attribute, first column is attribute name, and second is atteribute value. Nested hashes are collapsed.
* `object_list` : displayed as a 2 dimensional table: one line per item, one colum per attribute.
* `value_list` : a table with one column.
* `empty` : nothing
* `status` : a message
* `other_struct` : a complex structure that cannot be displayed as an array

### Format of output

By default, result of type single_object and object_list are displayed using format `table`.
The table style can be customized with parameter: `table_style` (horizontal, vertical and intersection characters) and is `:.:` by default.

In a table format, when displaying "objects" (single, or list), by default, sub object are
flatten (option flat_hash). So, object {"user":{"id":1,"name":"toto"}} will have attributes: user.id and user.name. Setting `flat_hash` to `false` will only display one
field: "user" and value is the sub hash table. When in flatten mode, it is possible to
filter fields by "dotted" field name.

The style of output can be set using the `format` parameter, supporting:

* `table` : Text table
* `ruby` : Ruby code
* `json` : JSON code
* `jsonpp` : JSON pretty printed
* `yaml` : YAML
* `csv` : Comma Separated Values

### <a name="option_select"></a>Option: `select`: Filter on columns values for `object_list`

Table output can be filtered using the `select` parameter. Example:

```
$ ascli aoc admin res user list --fields=name,email,ats_admin --query=@json:'{"sort":"name"}' --select=@json:'{"ats_admin":true}'
:...............................:..................................:...........:
:             name              :              email               : ats_admin :
:...............................:..................................:...........:
: John Custis                   : john@example.com                 : true      :
: Laurent Martin                : laurent@example.com              : true      :
:...............................:..................................:...........:
```

Note that `select` filters selected elements from the result of API calls, while the `query` parameters gives filtering parameters to the API when listing elements.

### Verbosity of output

Outpout messages are categorized in 3 types:

* `info` output contain additional information, such as number of elements in a table
* `data` output contain the actual output of the command (object, or list of objects)
* `error`output contain error messages

The option `display` controls the level of output:

* `info` displays all messages
* `data` display `data` and `error` messages
* `error` display only error messages.

### Selection of output object properties

By default, a table output will display one line per entry, and columns for each entries. Depending on the command, columns may include by default all properties, or only some selected properties. It is possible to define specific colums to be displayed, by setting the `fields` option to one of the following value:

* DEF : default display of columns (that's the default, when not set)
* ALL : all columns available
* a,b,c : the list of attributes specified by the comma separated list
* Array extended value: for instance, @json:'["a","b","c"]' same as above
* +a,b,c : add selected properties to the default selection.
* -a,b,c : remove selected properties from the default selection.

## <a name="extended"></a>Extended Value Syntax

Usually, values of options and arguments are specified by a simple string. But sometime it is convenient to read a value from a file, or decode it, or have a value more complex than a string (e.g. Hash table).

The extended value syntax is:

```
<0 or more decoders><0 or 1 reader><nothing or some text value>
```

The difference between reader and decoder is order and ordinality. Both act like a function of value on right hand side. Decoders are at the beginning of the value, followed by a single optional reader, followed by the optional value.

The following "readers" are supported (returns value in []):

* @val:VALUE : [String] prevent further special prefix processing, e.g. `--username=@val:laurent` sets the option `username` to value `laurent`.
* @file:PATH : [String] read value from a file (prefix "~/" is replaced with the users home folder), e.g. --key=@file:~/.ssh/mykey
* @path:PATH : [String] performs path expansion (prefix "~/" is replaced with the users home folder), e.g. --config-file=@path:~/sample_config.yml
* @env:ENVVAR : [String] read from a named env var, e.g.--password=@env:MYPASSVAR
* @stdin: : [String] read from stdin (no value on right)
* @preset:NAME : [Hash] get whole option preset value by name

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

```
$ ascli config echo @zlib:@base64:@file:myfile.dat
```

Example: create a value as a hash, with one key and the value is read from a file:

```
$ ascli config echo @ruby:'{"token_verification_key"=>File.read("pubkey.txt")}'
```

Example: read a csv file and create a list of hash for bulk provisioning:

```
$ cat test.csv
name,email
lolo,laurent@example.com
toto,titi@tutu.tata
$ ascli config echo @csvt:@file:test.csv
:......:.....................:
: name :        email        :
:......:.....................:
: lolo : laurent@example.com :
: toto : titi@tutu.tata      :
:......:.....................:
```

Example: create a hash and include values from preset named "config" of config file in this hash

```
$ ascli config echo @incps:@json:'{"hello":true,"incps":["config"]}'
{"version"=>"0.9", "hello"=>true}
```

Note that `@incps:@json:'{"incps":["config"]}'` or `@incps:@ruby:'{"incps"=>["config"]}'` is equivalent to: `@preset:config`

## <a name="native"></a>Structured Value

Some options and parameters expect a _Structured Value_, i.e. a value more complex than a simple string. This is usually a Hash table or an Array, which could also contain sub structures.

For instance, a [_transfer-spec_](#transferspec) is expected to be a _Structured Value_.

Structured values shall be described using the [Extended Value Syntax](#extended).
A convenient way to specify a _Structured Value_ is to use the `@json:` decoder, and describe the value in JSON format. The `@ruby:` decoder can also be used. For an array of hash tables, the `@csvt:` decoder can be used.

It is also possible to provide a _Structured Value_ in a file using `@json:@file:<path>`

## <a name="conffolder"></a>Configuration and Persistency Folder

`ascli` configuration and other runtime files (token cache, file lists, persistency files, SDK) are stored in folder `[User's home folder]/.aspera/ascli`.

Note: `[User's home folder]` is found using ruby's `Dir.home` (`rb_w32_home_dir`).
It uses the `HOME` env var primarily, and on MS Windows it also looks at `%HOMEDRIVE%%HOMEPATH%` and `%USERPROFILE%`. `ascli` sets the env var `%HOME%` to the value of `%USERPROFILE%` if set and exists. So, on Windows `%USERPROFILE%` is used as it is more reliable than `%HOMEDRIVE%%HOMEPATH%`.

The main folder can be displayed using :

```
$ ascli config folder
/Users/kenji/.aspera/ascli
```

It can be overriden using the envinonment variable `ASCLI_HOME`.

Example (Windows):

```
$ set ASCLI_HOME=C:\Users\Kenji\.aspera\ascli
$ ascli config folder
C:\Users\Kenji\.aspera\ascli
```

## <a name="configfile"></a>Configuration file

On the first execution of `ascli`, an empty configuration file is created in the configuration folder.
Nevertheless, there is no mandatory information required in this file, the use of it is optional as any option can be provided on the command line.

Although the file is a standard YAML file, `ascli` provides commands to read and modify it using the `config` command.

All options for `ascli` can be set on command line, or by env vars, or using [option presets](#lprt) in the configuratin file.

A configuration file provides a way to define default values, especially for authentication parameters, thus avoiding to always having to specify those parameters on the command line.

The default configuration file is: `$HOME/.aspera/ascli/config.yaml` (this can be overriden with option `--config-file=path` or equivalent env var).

The configuration file is simply a catalog of pre-defined lists of options, called: [option presets](#lprt). Then, instead of specifying some common options on the command line (e.g. address, credentials), it is possible to invoke the ones of a [option preset](#lprt) (e.g. `mypreset`) using the option: `-Pmypreset` or `--preset=mypreset`.

### <a name="lprt"></a>Option preset

A [option preset](#lprt) is simply a collection of parameters and their associated values in a named section in the configuration file.

A named [option preset](#lprt) can be modified directly using `ascli`, which will update the configuration file :

```
$ ascli config id <option preset> set|delete|show|initialize|update
```

The command `update` allows the easy creation of [option preset](#lprt) by simply providing the options in their command line format, e.g. :

```
$ ascli config id demo_server update --url=ssh://demo.asperasoft.com:33001 --username=asperaweb --password=_demo_pass_ --ts=@json:'{"precalculate_job_size":true}'
```

* This creates a [option preset](#lprt) `demo_server` with all provided options.

The command `set` allows setting individual options in a [option preset](#lprt).

```
$ ascli config id demo_server set password _demo_pass_
```

The command `initialize`, like `update` allows to set several parameters at once, but it deletes an existing configuration instead of updating it, and expects a _[Structured Value](#native)_.

```
$ ascli config id demo_server initialize @json:'{"url":"ssh://demo.asperasoft.com:33001","username":"asperaweb","password":"_demo_pass_","ts":{"precalculate_job_size":true}}'
```

A good practice is to not manually edit the configuration file and use modification commands instead.
If necessary, the configuration file can be edited (or simply consulted) with:

```
$ ascli config open
```

A full terminal based overview of the configuration can be displayed using:

```
$ ascli config over
```

A list of [option preset](#lprt) can be displayed using:

```
$ ascli config list
```

### <a name="lprtconf"></a>Special Option preset: config

This preset name is reserved and contains a single key: `version`. This is the version of `ascli` which created the file.

### <a name="lprtdef"></a>Special Option preset: default

This preset name is reserved and contains an array of key-value , where the key is the name of a plugin, and the value is the name of another preset.

When a plugin is invoked, the preset associated with the name of the plugin is loaded, unless the option --no-default (or -N) is used.

Note that special plugin name: `config` can be associated with a preset that is loaded initially, typically used for default values.

Operations on this preset are done using regular `config` operations:

```
$ ascli config id default set _plugin_name_ _default_preset_for_plugin_
$ ascli config id default get _plugin_name_
"_default_preset_for_plugin_"
```

### <a name="lprtdef"></a>Special Plugin: config

Plugin `config` (not to be confused with Option preset config) is used to configure `ascli` but it also contains global options.

When `ascli` starts, it lookjs for the `default` Option preset and if there is a value for `config`, if so, it loads the option values for any plugin used.

If no global default is set by the user, the tool will use `global_common_defaults` when setting global parameters (e.g. `conf ascp use`)

### Format of file

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
  password: _demo_pass_
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

Note: if the user wants to use the [Extended Value Syntax](#extended) inside the configuration file, using the `config id update` command, the user shall use the `@val:` prefix. Example:

```
$ ascli config id my_aoc_org set private_key @val:@file:"$HOME/.aspera/ascli/aocapikey"
```

This creates the [option preset](#lprt):

```
...
my_aoc_org:
  private_key: @file:"/Users/laurent/.aspera/ascli/aocapikey"
...
```

So, the key file will be read only at execution time, but not be embedded in the configuration file.

### Options evaluation order

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

```
$ ascli config id cli_default set interactive no
$ ascli config id default set config cli_default
```

A [option preset](#lprt) value can be removed with `unset`:

```
$ ascli config id cli_default unset interactive
```

Example: Define options using command line:

```
$ ascli -N --url=x --password=y --username=y node --show-config
```

Example: Define options using a hash:

```
$ ascli -N --preset=@json:'{"url":"x","password":"y","username":"y"}' node --show-config
```

### Examples

For Faspex, Shares, Node (including ATS, Aspera Transfer Service), Console,
only username/password and url are required (either on command line, or from config file).
Those can usually be provided on the command line:

```
$ ascli shares repo browse / --url=https://10.25.0.6 --username=john --password=4sp3ra
```

This can also be provisioned in a config file:

```
1$ ascli config id shares06 set url https://10.25.0.6
2$ ascli config id shares06 set username john
3$ ascli config id shares06 set password 4sp3ra
4$ ascli config id default set shares shares06
5$ ascli config overview
6$ ascli shares repo browse /
```

The three first commands build a [option preset](#lprt).
Note that this can also be done with one single command:

```
$ ascli config id shares06 init @json:'{"url":"https://10.25.0.6","username":"john","password":"4sp3ra"}'
```

The fourth command defines this [option preset](#lprt) as the default [option preset](#lprt) for the
specified application ("shares"). The 5th command displays the content of configuration file in table format.
Alternative [option presets](#lprt) can be used with option "-P&lt;[option preset](#lprt)&gt;"
(or --preset=&lt;[option preset](#lprt)&gt;)

Eventually, the last command shows a call to the shares application using default parameters.


## Plugins

The CLI tool uses a plugin mechanism. The first level command (just after `ascli` on the command line) is the name of the concerned plugin which will execute the command. Each plugin usually represent commands sent to a specific application.
For instance, the plugin "faspex" allows operations on the application "Aspera Faspex".

### Create your own plugin
```
$ mkdir -p ~/.aspera/ascli/plugins
$ cat<<EOF>~/.aspera/ascli/plugins/test.rb
require 'aspera/cli/plugin'
module Aspera
  module Cli
    module Plugins
      class Test < Plugin
        ACTIONS=[]
        def execute_action; puts "Hello World!"; end
      end # Test
    end # Plugins
  end # Cli
end # Aspera
EOF
```

## Debugging

The gem is equipped with traces. By default logging level is "warn". To increase debug level, use parameter `log_level`, so either command line `--log-level=xx` or env var `ASCLI_LOG_LEVEL`.

It is also possible to activate traces before initialisation using env var `AS_LOG_LEVEL`.

## Learning Aspera Product APIs (REST)

This CLI uses REST APIs.
To display HTTP calls, use argument `-r` or `--rest-debug`, this is useful to display
exact content or HTTP requests and responses.

In order to get traces of execution, use argument : `--log-level=debug`

## <a name="graphical"></a>Graphical Interactions: Browser and Text Editor

Some actions may require the use of a graphical tool:

* a browser for Aspera on Cloud authentication (web auth method)
* a text editor for configuration file edition

By default the CLI will assume that a graphical environment is available on windows,
and on other systems, rely on the presence of the "DISPLAY" environment variable.
It is also possible to force the graphical mode with option --ui :

* `--ui=graphical` forces a graphical environment, a browser will be opened for URLs or
a text editor for file edition.
* `--ui=text` forces a text environment, the URL or file path to open is displayed on
terminal.

## HTTP proxy for REST

To specify a HTTP proxy, set the HTTP_PROXY environment variable (or HTTPS_PROXY), those are honoured by Ruby when calling REST APIs.

## Proxy auto config

The `fpac` option allows specification of a Proxy Auto Configuration (PAC) file, by its URL for local FASP agent. Supported schemes are : http:, https: and file:.

The PAC file can be tested with command: `config proxy_check` , example:

```
$ ascli config proxy_check --fpac=file:///./proxy.pac http://www.example.com
PROXY proxy.example.com:8080
```

This is not yet implemented to specify http proxy, so use `http_proxy` env vars.

## <a name="client"></a>FASP configuration

The `config` plugin also allows specification for the use of a local FASP client. It provides the following commands for `ascp` subcommand:

* `show` : shows the path of ascp used
* `use` : list,download connect client versions available on internet
* `products` : list Aspera transfer products available locally
* `connect` : list,download connect client versions available on internet

### Show path of currently used `ascp`

```
$ ascli config ascp show
/Users/laurent/.aspera/ascli/sdk/ascp
$ ascli config ascp info
+--------------------+-----------------------------------------------------------+
| key                | value                                                     |
+--------------------+-----------------------------------------------------------+
| ascp               | /Users/laurent/.aspera/ascli/sdk/ascp                     |
...
```

### Selection of `ascp` location for [`direct`](#direct) agent

By default, `ascli` uses any found local product with ascp, including SDK.

To temporarily use an alternate ascp path use option `ascp_path` (`--ascp-path=`)

For a permanent change, the command `config ascp use` sets the same parameter for the global default.

Using a POSIX shell:

```
$ ascli config ascp use '/Users/laurent/Applications/Aspera CLI/bin/ascp'
ascp version: 4.0.0.182279
Updated: global_common_defaults: ascp_path <- /Users/laurent/Applications/Aspera CLI/bin/ascp
Saved to default global preset global_common_defaults
```

Windows:

```
$ ascli config ascp use C:\Users\admin\.aspera\ascli\sdk\ascp.exe
ascp version: 4.0.0.182279
Updated: global_common_defaults: ascp_path <- C:\Users\admin\.aspera\ascli\sdk\ascp.exe
Saved to default global preset global_common_defaults
```

If the path has spaces, read section: [Shell and Command line parsing](#parsing).

### List locally installed Aspera Transfer products

Locally installed Aspera products can be listed with:

```
$ ascli config ascp products list
:.........................................:................................................:
:                  name                   :                    app_root                    :
:.........................................:................................................:
: Aspera Connect                          : /Users/laurent/Applications/Aspera Connect.app :
: IBM Aspera CLI                          : /Users/laurent/Applications/Aspera CLI         :
: IBM Aspera High-Speed Transfer Endpoint : /Library/Aspera                                :
: Aspera Drive                            : /Applications/Aspera Drive.app                 :
:.........................................:................................................:
```

### Selection of local client for `ascp` for [`direct`](#direct) agent

If no ascp is selected, this is equivalent to using option: `--use-product=FIRST`.

Using the option use_product finds the ascp binary of the selected product.

To permanently use the ascp of a product:

```
$ ascli config ascp products use 'Aspera Connect'
saved to default global preset /Users/laurent/Applications/Aspera Connect.app/Contents/Resources/ascp
```

### Installation of Connect Client on command line

```
$ ascli config ascp connect list
:...............................................:......................................:..............:
:                      id                       :                title                 :   version    :
:...............................................:......................................:..............:
: urn:uuid:589F9EE5-0489-4F73-9982-A612FAC70C4E : Aspera Connect for Windows           : 3.7.0.138427 :
: urn:uuid:A3820D20-083E-11E2-892E-0800200C9A66 : Aspera Connect for Windows 64-bit    : 3.7.0.138427 :
: urn:uuid:589F9EE5-0489-4F73-9982-A612FAC70C4E : Aspera Connect for Windows XP        : 3.7.0.138427 :
: urn:uuid:55425020-083E-11E2-892E-0800200C9A66 : Aspera Connect for Windows XP 64-bit : 3.7.0.138427 :
: urn:uuid:D8629AD2-6898-4811-A46F-2AF386531BFF : Aspera Connect for Mac Intel 10.6    : 3.6.1.111259 :
: urn:uuid:D8629AD2-6898-4811-A46F-2AF386531BFF : Aspera Connect for Mac Intel         : 3.7.0.138427 :
: urn:uuid:213C9370-22B1-11E2-81C1-0800200C9A66 : Aspera Connect for Linux 32          : 3.6.2.117442 :
: urn:uuid:97F94DF0-22B1-11E2-81C1-0800200C9A66 : Aspera Connect for Linux 64          : 3.7.2.141527 :
:...............................................:......................................:..............:
$ ascli config ascp connect id 'Aspera Connect for Mac Intel 10.6' links list
:.............................................:..........................:.......................................................................:..........:...............:
:                    title                    :           type           :                                 href                                  : hreflang :      rel      :
:.............................................:..........................:.......................................................................:..........:...............:
: Mac Intel Installer                         : application/octet-stream : bin/AsperaConnect-3.6.1.111259-mac-intel-10.6.dmg                     : en       : enclosure     :
: Aspera Connect for Mac HTML Documentation   : text/html                :                                                                       : en       : documentation :
: Aspera Connect PDF Documentation for Mac OS : application/pdf          : docs/user/osx/ja-jp/pdf/Connect_User_3.7.0_OSX_ja-jp.pdf              : ja-jp    : documentation :
: Aspera Connect PDF Documentation for Mac OS : application/pdf          : docs/user/osx/en/pdf/Connect_User_3.7.0_OSX.pdf                       : en       : documentation :
: Aspera Connect PDF Documentation for Mac OS : application/pdf          : docs/user/osx/es-es/pdf/Connect_User_3.7.0_OSX_es-es.pdf              : es-es    : documentation :
: Aspera Connect PDF Documentation for Mac OS : application/pdf          : docs/user/osx/fr-fr/pdf/Connect_User_3.7.0_OSX_fr-fr.pdf              : fr-fr    : documentation :
: Aspera Connect PDF Documentation for Mac OS : application/pdf          : docs/user/osx/zh-cn/pdf/Connect_User_3.7.0_OSX_zh-cn.pdf              : zh-cn    : documentation :
: Aspera Connect for Mac Release Notes        : text/html                : http://www.asperasoft.com/en/release_notes/default_1/release_notes_54 : en       : release-notes :
:.............................................:..........................:.......................................................................:..........:...............:
$ ascli config ascp connect id 'Aspera Connect for Mac Intel 10.6' links id 'Mac Intel Installer' download --to-folder=.
downloaded: AsperaConnect-3.6.1.111259-mac-intel-10.6.dmg
```

## <a name="agents"></a>Transfer Agents

Some of the actions on Aspera Applications lead to file transfers (upload and download) using the FASP protocol (`ascp`).

When a transfer needs to be started, a [_transfer-spec_](#transferspec) has been internally prepared.
This [_transfer-spec_](#transferspec) will be executed by a transfer client, here called "Transfer Agent".

There are currently 3 agents:

* [`direct`](#direct) : a local execution of `ascp`
* `connect` : use of a local Connect Client
* `node` : use of an Aspera Transfer Node (potentially _remote_).
* `httpgw` : use of an Aspera HTTP Gateway

Note that all transfer operation are seen from the point of view of the agent.
For instance, a node agent making an "upload", or "package send" operation,
will effectively push files to the related server from the agent node.

`ascli` standadizes on the use of a [_transfer-spec_](#transferspec) instead of _raw_ ascp options to provide parameters for a transfer session, as a common method for those three Transfer Agents.


### <a name="direct"></a>Direct (local ascp execution)

By default `ascli` uses a local ascp, equivalent to specifying `--transfer=direct`.
`ascli` will detect locally installed Aspera products.
Refer to section [FASP](#client).

To specify a FASP proxy (only supported with the `direct` agent), set the appropriate [_transfer-spec_](#transferspec) parameter:

* `EX_fasp_proxy_url`
* `EX_http_proxy_url` (proxy for legacy http fallback)
* `EX_ascp_args`

The `transfer-info` accepts the following optional parameters:

<table>
<tr><th>Name</th><th>Type</th><th>Default</th><th>Feature</th><th>Description</th></tr>
<tr><td>spawn_timeout_sec</td><td>Float</td><td>3</td><td>Multi session</td><td>Verification time that ascp is running</td></tr>
<tr><td>spawn_delay_sec</td><td>Float</td><td>2</td><td>Multi session</td><td>Delay between startup of sessions</td></tr>
<tr><td>wss</td><td>Bool</td><td>false</td><td>Web Socket Session</td><td>Enable use of web socket session in case it is available</td></tr>
<tr><td>multi_incr_udp</td><td>Bool</td><td>true</td><td>Multi Session</td><td>Increment UDP port on multi-session<br/>If true, each session will have a different UDP port starting at `fasp_port` (or default 33001)<br/>Else, each session will use `fasp_port` (or `ascp` default)</td></tr>
<tr><td>resume</td><td>Hash</td><td>nil</td><td>Resumer parameters</td><td>See below</td></tr>
</table>

Resume parameters:

In case of transfer interruption, the agent will resume a transfer up to `iter_max` time.
Sleep between iteration is:

```
max( sleep_max , sleep_initial * sleep_factor ^ (iter_index-1) )
```

<table>
<tr><th>Name</th><th>Type</th><th>Default</th><th>Feature</th><th>Description</th></tr>
<tr><td>iter_max</td><td>int</td><td>7</td><td>Resume</td><td>Max number of retry on error</td></tr>
<tr><td>sleep_initial</td><td>int</td><td>2</td><td>Resume</td><td>First Sleep before retry</td></tr>
<tr><td>sleep_factor</td><td>int</td><td>2</td><td>Resume</td><td>Multiplier of Sleep</td></tr>
<tr><td>sleep_max</td><td>int</td><td>60</td><td>Resume</td><td>Maximum sleep</td></tr>
</table>

Examples:

```
$ ascli ... --transfer-info=@json:'{"wss":true,"resume":{"iter_max":10}}'
$ ascli ... --transfer-info=@json:'{"spawn_delay_sec":2.5,"multi_incr_udp":false}'
```

### IBM Aspera Connect Client GUI

By specifying option: `--transfer=connect`, `ascli` will start transfers
using the locally installed Aspera Connect Client.

### Aspera Node API : Node to node transfers

By specifying option: `--transfer=node`, the CLI will start transfers in an Aspera
Transfer Server using the Node API, either on a local or remote node.

If a default node has been configured
in the configuration file, then this node is used by default else the parameter
`--transfer-info` is required. The node specification shall be a hash table with
three keys: url, username and password, corresponding to the URL of the node API
and associated credentials (node user or access key).

The `--transfer-info` parameter can directly specify a pre-configured [option preset](#lprt) :
`--transfer-info=@preset:<psetname>` or specified using the option syntax :
`--transfer-info=@json:'{"url":"https://...","username":"theuser","password":"thepass"}'`

### <a name="trinfoaoc"></a>Aspera on cloud

By specifying option: `--transfer=aoc`, WORK IN PROGRESS

### <a name="httpgw"></a>HTTP Gateway

If it possible to send using a HTTP gateway, in case FASP is not allowed.

Example:

```
$ ascli faspex package recv --id=323 --transfer=httpgw --transfer-info=@json:'{"url":"https://asperagw.example.com:9443/aspera/http-gwy/v1"}'
```

Note that the gateway only supports transfers authorized with a token.

## <a name="transferspec"></a>Transfer Specification

Some commands lead to file transfer (upload/download), all parameters necessary for this transfer
is described in a _transfer-spec_ (Transfer Specification), such as:

* server address
* transfer user name
* credentials
* file list
* etc...

`ascli` builds a default _transfer-spec_ internally, so it is not necessary to provide additional parameters on the command line for this transfer.

If needed, it is possible to modify or add any of the supported _transfer-spec_ parameter using the `ts` option. The `ts` option accepts a [Structured Value](#native) containing one or several _transfer-spec_ parameters. Multiple `ts` options on command line are cummulative.

It is possible to specify ascp options when the `transfer` option is set to [`direct`](#direct) using the special [_transfer-spec_](#transferspec) parameter: `EX_ascp_args`. Example: `--ts=@json:'{"EX_ascp_args":["-l","100m"]}'`. This is espacially useful for ascp command line parameters not supported yet in the transfer spec.

The use of a _transfer-spec_ instead of `ascp` parameters has the advantage of:

* common to all [Transfer Agent](#agents)
* not dependent on command line limitations (special characters...)

A [_transfer-spec_](#transferspec) is a Hash table, so it is described on the command line with the [Extended Value Syntax](#extended).

## <a name="transferparams"></a>Transfer Parameters

All standard _transfer-spec_ parameters can be speficied.
[_transfer-spec_](#transferspec) can also be saved/overridden in the config file.

References:

* [Aspera Node API Documentation](https://developer.ibm.com/apis/catalog?search=%22aspera%20node%20api%22)&rarr;/opt/transfers
* [Aspera Transfer SDK Documentation](https://developer.ibm.com/apis/catalog?search=%22aspera%20transfer%20sdk%22)&rarr;Guides&rarr;API Ref&rarr;Transfer Spec V1

Parameters can be displayed with commands:

```
$ ascli config ascp spec
$ ascli config ascp spec --select=@json:'{"f":"Y"}' --fields=-f,n,c
```

Columns:

* D=Direct (local `ascp` execution)
* N=Node API
* C=Connect Client
* arg=`ascp` argument or environment variable

Fields with EX_ prefix are extensions to transfer agent [`direct`](#direct). (only in `ascli`).

<table><tr><th>Field</th><th>Type</th><th>D</th><th>N</th><th>C</th><th>Description</th></tr><tr><td>cipher</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>In transit encryption type.<br/>none, aes-128, aes-256<br/>Allowed values: aes128, aes192, aes256, aes128cfb, aes192cfb, aes256cfb, aes128gcm, aes192gcm, aes256gcm<br/>(-c)</td></tr><tr><td>content_protection</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Enable client-side content protection. (encryption at rest)<br/>Allowed values: encrypt, decrypt</td></tr><tr><td>content_protection_password</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Specifies CSEAR password.</td></tr><tr><td>cookie</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Metadata for transfer (older,string)<br/>(env:ASPERA_SCP_COOKIE)</td></tr><tr><td>create_dir</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>Specifies whether to create new directories.<br/>(-d)</td></tr><tr><td>delete_before_transfer</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>(--delete-before-transfer)</td></tr><tr><td>delete_source</td><td>bool</td><td>&nbsp;</td><td>Y</td><td>&nbsp;</td><td>Remove SRC files after transfer success</td></tr><tr><td>direction</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Direction of transfer (on client side)<br/>Allowed values: send, receive<br/>(--mode)</td></tr><tr><td>exclude_newer_than</td><td>int</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>skip src files with mtime > arg<br/>(--exclude-newer-than)</td></tr><tr><td>exclude_older_than</td><td>int</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>skip src files with mtime < arg<br/>(--exclude-older-than)</td></tr><tr><td>fasp_port</td><td>int</td><td>Y</td><td>Y</td><td>Y</td><td>Specifies fasp (UDP) port.<br/>(-O)</td></tr><tr><td>http_fallback</td><td>string<br/>bool</td><td>Y</td><td>Y</td><td>Y</td><td>When true(1), attempts to perform an HTTP transfer if a fasp transfer cannot be performed.<br/>(-y)</td></tr><tr><td>http_fallback_port</td><td>int</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Specifies http port.<br/>(-t)</td></tr><tr><td>https_fallback_port</td><td>int</td><td>Y</td><td>Y</td><td>Y</td><td>Specifies https port.</td></tr><tr><td>move_after_transfer</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>(--move-after-transfer)</td></tr><tr><td>multi_session</td><td>int</td><td>Y</td><td>Y</td><td>Y</td><td>Use multi-session transfer. max 128.<br/> Each participant on one host needs an independent UDP (-O) port.<br/> Large files are split between sessions only when transferring with resume_policy=none.</td></tr><tr><td>multi_session_threshold</td><td>int</td><td>Y</td><td>Y</td><td>&nbsp;</td><td>in bytes<br/>(--multi-session-threshold)</td></tr><tr><td>overwrite</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Overwrite destination files with the source files of the same name.<br/>Allowed values: never, always, diff, older, diff+older<br/>(--overwrite)</td></tr><tr><td>paths</td><td>array</td><td>Y</td><td>Y</td><td>Y</td><td>Required. Contains a path to the source (required) and a path to the destination.</td></tr><tr><td>precalculate_job_size</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>Specifies whether to precalculate the job size.<br/>(--precalculate-job-size)</td></tr><tr><td>preserve_access_time</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>(--preserve-access-time)</td></tr><tr><td>preserve_creation_time</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>(--preserve-creation-time)</td></tr><tr><td>preserve_modification_time</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>(--preserve-modification-time)</td></tr><tr><td>preserve_times</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>(--preserve-times)</td></tr><tr><td>rate_policy</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>The transfer rate policy to use when sharing bandwidth.<br/>Allowed values: low, fair, high, fixed<br/>(--policy)</td></tr><tr><td>remote_access_key</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Node only?</td></tr><tr><td>remote_host</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>IP or fully qualified domain name of the remote server<br/>(--host)</td></tr><tr><td>remote_user</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Remote user. Default value is "xfer" on node or connect.<br/>(--user)</td></tr><tr><td>remote_password</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>SSH session password<br/>(env:ASPERA_SCP_PASS)</td></tr><tr><td>remove_after_transfer</td><td>bool</td><td>Y</td><td>Y</td><td>&nbsp;</td><td>Remove SRC files after transfer success<br/>(--remove-after-transfer)</td></tr><tr><td>remove_empty_directories</td><td>bool</td><td>Y</td><td>Y</td><td>&nbsp;</td><td>Specifies whether to remove empty directories.<br/>(--remove-empty-directories)</td></tr><tr><td>proxy</td><td>string</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Specify the address of the Aspera high-speed proxy server.<br/> dnat(s)://[user[:password]@]server:port<br/> Default ports for DNAT and DNATS protocols are 9091 and 9092.<br/> Password, if specified here, overrides the value of environment variable ASPERA_PROXY_PASS.<br/>(--proxy)</td></tr><tr><td>resume_policy</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>If a transfer is interrupted or fails to finish, resume without re-transferring the whole files.<br/>Allowed values: none, attrs, sparse_csum, full_csum<br/>(-k)</td></tr><tr><td>retry_duration</td><td>string<br/>int</td><td>&nbsp;</td><td>Y</td><td>Y</td><td>Specifies how long to wait before retrying transfer. (e.g. "5min")</td></tr><tr><td>ssh_port</td><td>int</td><td>Y</td><td>Y</td><td>Y</td><td>Specifies ssh (TCP) port. Default: local:22, other:33001<br/>(-P)</td></tr><tr><td>ssh_private_key</td><td>string</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Private key used for SSH authentication.<br/> Shall look like: -----BEGIN RSA PRIVATE KEY-----\nMII...<br/> Note the JSON encoding: \n for newlines.<br/>(env:ASPERA_SCP_KEY)</td></tr><tr><td>symlink_policy</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Handle source side symbolic links by:<br/> following the link (follow),<br/> copying the link itself (copy),<br/> skipping (skip),<br/> or forcibly copying the link itself (copy+force).<br/> Default: follow<br/>Allowed values: follow, copy, copy+force, skip<br/>(--symbolic-links)</td></tr><tr><td>tags</td><td>hash</td><td>Y</td><td>Y</td><td>Y</td><td>Metadata for transfer<br/>(--tags64)</td></tr><tr><td>target_rate_cap_kbps</td><td>int</td><td>&nbsp;</td><td>&nbsp;</td><td>Y</td><td>Returned by upload/download_setup node api.</td></tr><tr><td>target_rate_kbps</td><td>int</td><td>Y</td><td>Y</td><td>Y</td><td>Specifies desired speed for the transfer.<br/>(-l)</td></tr><tr><td>title</td><td>string</td><td>&nbsp;</td><td>Y</td><td>Y</td><td>Title of the transfer</td></tr><tr><td>token</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Authorization token: Bearer, Basic or ATM (Also arg -W)<br/>(env:ASPERA_SCP_TOKEN)</td></tr><tr><td>use_ascp4</td><td>bool</td><td>Y</td><td>Y</td><td>&nbsp;</td><td>specify version of protocol</td></tr><tr><td>destination_root</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Destination root directory.</td></tr><tr><td>source_root</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Path to be prepended to each source path.<br/> This is either a conventional path or it can be a URI but only if there is no root defined.<br/>(--source-prefix64)</td></tr><tr><td>min_rate_cap_kbps</td><td>int</td><td>Y</td><td>Y</td><td>Y</td><td>&nbsp;</td></tr><tr><td>lock_rate_policy</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>&nbsp;</td></tr><tr><td>lock_target_rate_kbps</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>&nbsp;</td></tr><tr><td>lock_min_rate_kbps</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>&nbsp;</td></tr><tr><td>apply_local_docroot</td><td>bool</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>(--apply-local-docroot)</td></tr><tr><td>preserve_acls</td><td>string</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Preserve access control lists.<br/>Allowable values: none, native, metafile<br/>(--preserve-acls)</td></tr><tr><td>remove_empty_source_directory</td><td>bool</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>TODO: check node, sdk<br/>(--remove-empty-source-directory)</td></tr><tr><td>EX_at_rest_password</td><td>string</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Passphrase used for at rest encryption or decryption<br/>(env:ASPERA_SCP_FILEPASS)</td></tr><tr><td>EX_proxy_password</td><td>string</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Password used for Aspera proxy server authentication.<br/> May be overridden by password in URL EX_fasp_proxy_url.<br/>(env:ASPERA_PROXY_PASS)</td></tr><tr><td>EX_license_text</td><td>string</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>License file text override.<br/>By default ascp looks for license file near executable.<br/>(env:ASPERA_SCP_LICENSE)</td></tr><tr><td>dgram_size</td><td>int</td><td>Y</td><td>Y</td><td>Y</td><td>in bytes<br/>(-Z)</td></tr><tr><td>min_rate_kbps</td><td>int</td><td>Y</td><td>Y</td><td>Y</td><td>Set the minimum transfer rate in kilobits per second.<br/>(-m)</td></tr><tr><td>sshfp</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>Check it against server SSH host key fingerprint<br/>(--check-sshfp)</td></tr><tr><td>EX_http_proxy_url</td><td>string</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Specify the proxy server address used by HTTP Fallback<br/>(-x)</td></tr><tr><td>EX_ssh_key_paths</td><td>array</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Use public key authentication for SSH and specify the private key file paths<br/>(-i)</td></tr><tr><td>EX_http_transfer_jpeg</td><td>int</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>HTTP transfers as JPEG file<br/>(-j)</td></tr><tr><td>EX_no_read</td><td>bool</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>no read source<br/>(--no-read)</td></tr><tr><td>EX_no_write</td><td>bool</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>no write on destination<br/>(--no-write)</td></tr><tr><td>target_rate_percentage</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>&nbsp;</td></tr><tr><td>rate_policy_allowed</td><td>string</td><td>&nbsp;</td><td>&nbsp;</td><td>Y</td><td>Specifies most aggressive rate policy that is allowed.<br/> Returned by node API.<br/>Allowed values: low, fair, high, fixed</td></tr><tr><td>lock_min_rate</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>&nbsp;</td></tr><tr><td>lock_target_rate</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>&nbsp;</td></tr><tr><td>authentication</td><td>string</td><td>&nbsp;</td><td>&nbsp;</td><td>Y</td><td>value=token for SSH bypass keys, else password asked if not provided.</td></tr><tr><td>cipher_allowed</td><td>string</td><td>Y</td><td>Y</td><td>Y</td><td>returned by node API. Valid literals include "aes-128" and "none".</td></tr><tr><td>EX_file_list</td><td>string</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>source file list</td></tr><tr><td>EX_file_pair_list</td><td>string</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>source file pair list</td></tr><tr><td>EX_ascp_args</td><td>array</td><td>Y</td><td>&nbsp;</td><td>&nbsp;</td><td>Add command line arguments to ascp</td></tr><tr><td>wss_enabled</td><td>bool</td><td>Y</td><td>Y</td><td>Y</td><td>&nbsp;</td></tr><tr><td>wss_port</td><td>int</td><td>Y</td><td>Y</td><td>Y</td><td>&nbsp;</td></tr></table>

### Destination folder for transfers

The destination folder is set by `ascli` by default to:

* `.` for downloads
* `/` for uploads

It is specified by the [_transfer-spec_](#transferspec) parameter `destination_root`.
As such, it can be modified with option: `--ts=@json:'{"destination_root":"<path>"}'`.
The option `to_folder` provides an equivalent and convenient way to change this parameter:
`--to-folder=<path>` .

### List of files for transfers

When uploading, downloading or sending files, the user must specify the list of files to transfer. The option to specify the list of files (Extensed value) is `sources`, the default value is `@args`, which means: take remain non used arguments (not starting with `-` as list of files.
So, by default, the list of files to transfer will be simply specified on the command line:

```
$ ascli server upload ~/mysample.file secondfile
```

This is equivalent to:

```
$ ascli server upload --sources=@args ~/mysample.file secondfile
```

More advanced options are provided to adapt to various cases. In fact, list of files to transfer are normally conveyed using the [_transfer-spec_](#transferspec) using the field: "paths" which is a list (array) of pairs of "source" (mandatory) and "destination" (optional).

Note that this is different from the "ascp" command line. The paradigm used by `ascli` is:
all transfer parameters are kept in [_transfer-spec_](#transferspec) so that execution of a transfer is independent of the transfer agent. Note that other IBM Aspera interfaces use this: connect, node, transfer sdk.

For ease of use and flexibility, the list of files to transfer is specified by the option `sources`. Accepted values are:

* `@args` : (default value) the list of files is directly provided at the end of the command line (see at the beginning of this section).

* an [Extended Value](#extended) holding an *Array of String*. Examples:

```
--sources=@json:'["file1","file2"]'
--sources=@lines:@stdin:
--sources=@ruby:'File.read("myfilelist").split("\n")'
```

* `@ts` : the user provides the list of files directly in the `ts` option, in its `paths` field. Example:

```
--sources=@ts --ts=@json:'{"paths":[{"source":"file1"},{"source":"file2"}]}'
```

* Not recommended: It is possible to specify bare ascp arguments using the pseudo [_transfer-spec_](#transferspec) parameter `EX_ascp_args`.

```
--sources=@ts --ts=@json:'{"paths":[{"source":"dummy"}],"EX_ascp_args":["--file-list","myfilelist"]}'
```

This method avoids creating a copy of the file list, but has drawbacks: it applies *only* to the [`direct`](#direct) transfer agent (i.e. bare ascp) and not for Aspera on Cloud. One must specify a dummy list in the [_transfer-spec_](#transferspec), which will be overriden by the bare ascp command line provided. (TODO) In next version, dummy source paths can be removed.

In case the file list is provided on the command line i.e. using `--sources=@args` or `--sources=<Array>` (but not `--sources=@ts`), then the list of files will be used either as a simple file list or a file pair list depending on the value of the option: `src_type`:

* `list` : (default) the path of destination is the same as source
* `pair` : in that case, the first element is the first source, the second element is the first destination, and so on.

Example:

```
$ ascli server upload --src-type=pair ~/Documents/Samples/200KB.1 /Upload/sample1
```

Internally, when transfer agent [`direct`](#direct) is used, a temporary file list (or pair) file is generated and provided to ascp, unless `--file-list` or `--file-pait-list` is provided in `ts` in `EX_ascp_args`.

Note the special case when the source files are located on "Aspera on Cloud", i.e. using access keys and the `file id` API:

* All files must be in the same source folder.
* If there is a single file : specify the full path
* For multiple files, specify the source folder as first item in the list followed by the list of file names.

Source files are located on "Aspera on cloud", when :

* the server is Aspera on Cloud, and making a download / recv
* the agent is Aspera on Cloud, and making an upload / send

### <a name="multisession"></a>Support of multi-session

Multi session, i.e. starting a transfer of a file set using multiple sessions (one ascp process per session) is supported on "direct" and "node" agents, not yet on connect.

* when agent=node :

```
--ts=@json:'{"multi_session":10,"multi_session_threshold":1}'
```

Multi-session is directly supported by the node daemon.

* when agent=direct :

```
--ts=@json:'{"multi_session":5,"multi_session_threshold":1,"resume_policy":"none"}'
```

Note: resume policy of "attr" may cause problems. "none" or "sparse_csum"
shall be preferred.

Multi-session spawn is done by `ascli`.

When multi-session is used, one separate UDP port is used per session (refer to `ascp` manual page).

### Examples

* Change target rate

```
--ts=@json:'{"target_rate_kbps":500000}'
```

* Override the FASP SSH port to a specific TCP port:

```
--ts=@json:'{"ssh_port":33002}'
```

* Force http fallback mode:

```
--ts=@json:'{"http_fallback":"force"}'
```

* Activate progress when not activated by default on server

```
--ts=@json:'{"precalculate_job_size":true}'
```



## <a name="scheduling"></a>Lock for exclusive execution

In some conditions, it may be desirable to ensure that `ascli` is not executed several times in parallel.

For instance when `ascli` is executed automatically on a schedule basis, one generally desire that a new execution is not started if a previous execution is still running because an on-going operation may last longer than the scheduling period:

* Executing instances may pile-up and kill the system
* The same file may be transfered by multiple instances at the same time.
* `preview` may generate the same files in multiple instances.

Usually the OS native scheduler already provides some sort of protection against parallel execution:

* The Windows scheduler does this by default
* Linux cron can leverage the utility [`flock`](https://linux.die.net/man/1/flock) to do the same:

```
/usr/bin/flock -w 0 /var/cron.lock ascli ...
```

`ascli` natively supports a locking mechanism with option `lock_port`.
(Technically, this opens a local TCP server port, and fails if this port is already used, providing a local lock. Lock is released when process exits).

Example:

Run this same command in two separate terminals within less than 30 seconds:

```
ascli config echo @ruby:'sleep(30)' --lock-port=12345
```

The first instance will sleep 30 seconds, the second one will immediately exit like this:

```
WARN -- : Another instance is already running (Address already in use - bind(2) for "127.0.0.1" port 12345).
```

## "Proven&ccedil;ale"

`ascp`, the underlying executable implementing Aspera file transfer using FASP, has a capability to not only access the local file system (using system's `open`,`read`,`write`,`close` primitives), but also to do the same operations on other data storage such as S3, Hadoop and others. This mechanism is call *PVCL*. Several *PVCL* adapters are available, some are embedded in `ascp`
, some are provided om shared libraries and must be activated. (e.g. using `trapd`)

The list of supported *PVCL* adapters can be retried with command:

```
$ ascli conf ascp info
+--------------------+-----------------------------------------------------------+
| key                | value                                                     |
+--------------------+-----------------------------------------------------------+
-----8<----snip---------
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

```
<adapter>:///<sub file path>?<arg1>=<val1>&...
```

One of the adapters, used in this manual, for testing, is `faux`. It is a pseudo file system allowing generation of file data without actual storage (on source or destination).

## <a name="faux_testing"></a>`faux:` for testing

This is an extract of the man page of `ascp`. This feature is a feature of `ascp`, not `ascli`

This adapter can be used to simulate a file or a directory.

To send uninitialized data in place of an actual source file, the source file is replaced with an argument of the form `faux:///fname?fsize` where:

* `fname` is the name that will be assigned to the file on the destination
* `fsize` is the number of bytes that will be sent (in decimal).

Note that the character `?` is a special shell character (wildcard), so `faux` file specification on command line shall be protected (using `\?` and `\&` or using quotes). If not, the shell may give error: `no matches found` or equivalent.

For all sizes, a suffix can be added (case insensitive) to the size: k,m,g,t,p,e (values are power of 2, e.g. 1M is 2^20, i.e. 1 mebibyte, not megabyte). The maximum allowed value is 8*2^60. Very large `faux` file sizes (petabyte range and above) will likely fail due to lack of system memory unless `faux://`.

To send uninitialized data in place of a source directory, the source argument is replaced with an argument of the form:

```
faux:///dirname?<arg1>=<val1>&...
```

`dirname` is the folder name and can contain `/` to specify a subfolder.

Supported arguments are:

<table>
<tr><th>name</th><th>type</th><th>default</th><th>description</th></tr>
<tr><td>count</td><td>int</td><td>mandatory</td><td>number of files</td></tr>
<tr><td>file</td><td>string</td><td>file</td><td>basename for files</td></tr>
<tr><td>size</td><td>int</td><td>0</td><td>size of first file.</td></tr>
<tr><td>inc</td><td>int</td><td>0</td><td>increment applied to determine next file size</td></tr>
<tr><td>seq</td><td>sequential<br/>random</td><td>sequential</td><td>sequence in determining next file size</td></tr>
<tr><td>buf_init</td><td>none<br/>zero<br/>random</td><td>zero</td><td>how source data initialized.<br/>Option 'none' is not allowed for downloads.</td></tr>
</table>


The sequence parameter is applied as follows:

* If `seq` is `random` then each file size is:

  * size +/- (inc * rand())
  * Where rand is a random number between 0 and 1
  * Note that file size must not be negative, inc will be set to size if it is greater than size
  * Similarly, overall file size must be less than 8 * 2^60. If size + inc is greater, inc will be reduced to limit size + inc to 7 * 2^60.

* If `seq` is `sequential` then each file size is:

  * size + ((fileindex - 1) * inc)
  * Where first file is index 1
  * So file1 is size bytes, file2 is size + inc bytes, file3 is size + inc * 2 bytes, etc.
  * As with random, inc will be adjusted if size + (count * inc) is not less then 8 ^ 2^60.

Filenames generated are of the form: `<file>_<00000 . . . count>_<filesize>`

To discard data at the destination, the destination argument is set to `faux://` .

Examples:

* Upload 20 gigabytes of random data to file myfile to directory /Upload

```
$ ascli server upload faux:///myfile\?20g --to-folder=/Upload
```

* Upload a file /tmp/sample but do not save results to disk (no docroot on destination)

```
$ ascli server upload /tmp/sample --to-folder=faux://
```

* Upload a faux directory `mydir` containing 1 million files, sequentially with sizes ranging from 0 to 2 M - 2 bytes, with the basename of each file being `testfile` to /Upload

```
$ ascli server upload "faux:///mydir?file=testfile&count=1m&size=0&inc=2&seq=sequential" --to-folder=/Upload
```

## <a name="commands"></a>Sample Commands

A non complete list of commands used in unit tests:

```
ascli
ascli -h
ascli aoc -N remind --username=my_aoc_user_email
ascli aoc -N servers
ascli aoc admin analytics transfers --query=@json:'{"status":"completed","direction":"receive"}' --notif-to=my_recipient_email --notif-template=@ruby:'%Q{From: <%=from_name%> <<%=from_email%>>\nTo: <<%=to%>>\nSubject: <%=ev["files_completed"]%> files received\n\n<%=ev.to_yaml%>}'
ascli aoc admin ats access_key --id=akibmcloud --secret=somesecret node browse /
ascli aoc admin ats access_key --id=akibmcloud delete
ascli aoc admin ats access_key create --cloud=aws --region=my_aws_bucket_region --params=@json:'{"id":"ak_aws","name":"my test key AWS","storage":{"type":"aws_s3","bucket":"my_aws_bucket_name","credentials":{"access_key_id":"my_aws_bucket_key","secret_access_key":"my_aws_bucket_secret"},"path":"/"}}'
ascli aoc admin ats access_key create --cloud=softlayer --region=my_icos_bucket_region --params=@json:'{"id":"akibmcloud","secret":"somesecret","name":"my test key","storage":{"type":"ibm-s3","bucket":"my_icos_bucket_name","credentials":{"access_key_id":"my_icos_bucket_key","secret_access_key":"my_icos_bucket_secret"},"path":"/"}}'
ascli aoc admin ats access_key list --fields=name,id
ascli aoc admin ats cluster clouds
ascli aoc admin ats cluster list
ascli aoc admin ats cluster show --cloud=aws --region=eu-west-1
ascli aoc admin ats cluster show --id=1f412ae7-869a-445c-9c05-02ad16813be2
ascli aoc admin res application list
ascli aoc admin res client list
ascli aoc admin res client_access_key list
ascli aoc admin res client_registration_token --id=my_clt_reg_id delete
ascli aoc admin res client_registration_token create @json:'{"data":{"name":"test_client_reg1","client_subject_scopes":["alee","aejd"],"client_subject_enabled":true}}'
ascli aoc admin res client_registration_token list
ascli aoc admin res contact list
ascli aoc admin res dropbox list
ascli aoc admin res dropbox_membership list
ascli aoc admin res group list
ascli aoc admin res kms_profile list
ascli aoc admin res node list
ascli aoc admin res operation list
ascli aoc admin res organization show
ascli aoc admin res package list
ascli aoc admin res saml_configuration list
ascli aoc admin res self show
ascli aoc admin res short_link list
ascli aoc admin res user list
ascli aoc admin res workspace_membership list
ascli aoc admin resource node --name=AOC_NODE1_NAME --secret=AOC_NODE1_SECRET v3 access_key create --value=@json:'{"id":"testsub1","storage":{"path":"/folder1"}}'
ascli aoc admin resource node --name=AOC_NODE1_NAME --secret=AOC_NODE1_SECRET v3 access_key delete --id=testsub1
ascli aoc admin resource node --name=AOC_NODE1_NAME --secret=AOC_NODE1_SECRET v3 events
ascli aoc admin resource node --name=AOC_NODE1_NAME --secret=AOC_NODE1_SECRET v4 browse /
ascli aoc admin resource node --name=AOC_NODE1_NAME --secret=AOC_NODE1_SECRET v4 delete /folder1
ascli aoc admin resource node --name=AOC_NODE1_NAME --secret=AOC_NODE1_SECRET v4 mkdir /folder1
ascli aoc admin resource workspace list
ascli aoc admin resource workspace_membership list --fields=ALL --query=@json:'{"page":1,"per_page":50,"embed":"member","inherited":false,"workspace_id":11363,"sort":"name"}'
ascli aoc automation workflow --id="my_wf_id" action create --value=@json:'{"name":"toto"}' | tee action.info
ascli aoc automation workflow create --value=@json:'{"name":"test_workflow"}'
ascli aoc automation workflow delete --id="my_wf_id"
ascli aoc automation workflow list
ascli aoc automation workflow list --select=@json:'{"name":"test_workflow"}' --fields=id --format=csv --display=data > test
ascli aoc automation workflow list --value=@json:'{"show_org_workflows":"true"}' --scope=admin:all
ascli aoc bearer_token --display=data --scope=user:all
ascli aoc faspex
ascli aoc files bearer /
ascli aoc files bearer_token_node /
ascli aoc files browse /
ascli aoc files browse / -N --link=my_aoc_publink_folder
ascli aoc files delete /testsrc
ascli aoc files download --transfer=connect /200KB.1
ascli aoc files file --id=my_file_id show
ascli aoc files find / --value='\.partial$'
ascli aoc files http_node_download --to-folder=. /200KB.1
ascli aoc files mkdir /testsrc
ascli aoc files rename /somefolder testdst
ascli aoc files short_link create --to-folder=/testdst --value=private
ascli aoc files short_link create --to-folder=/testdst --value=public
ascli aoc files short_link list --value=@json:'{"purpose":"shared_folder_auth_link"}'
ascli aoc files transfer --from-folder=/testsrc --to-folder=/testdst testfile.bin
ascli aoc files upload --to-folder=/testsrc testfile.bin
ascli aoc files upload -N --to-folder=/ testfile.bin --link=my_aoc_publink_folder
ascli aoc files upload Test.pdf --transfer=node --transfer-info=@json:@stdin:
ascli aoc files v3 info
ascli aoc org -N --link=my_aoc_publink_recv_from_aocuser
ascli aoc organization
ascli aoc packages list
ascli aoc packages list --query=@json:'{"dropbox_id":"my_shbxid","sort":"-received_at","archived":false,"received":true,"has_content":true,"exclude_dropbox_packages":false}'
ascli aoc packages recv --id="my_package_id" --to-folder=.
ascli aoc packages recv --id=ALL --to-folder=. --once-only=yes --lock-port=12345
ascli aoc packages send --value=@json:'{"name":"Important files delivery","recipients":["external.user@example.com"]}' --new-user-option=@json:'{"package_contact":true}' testfile.bin
ascli aoc packages send --value=@json:'{"name":"Important files delivery","recipients":["internal.user@example.com"],"note":"my note"}' testfile.bin
ascli aoc packages send --workspace="my_aoc_shbx_ws" --value=@json:'{"name":"Important files delivery","recipients":["my_aoc_shbx_name"]}' testfile.bin
ascli aoc packages send -N --value=@json:'{"name":"Important files delivery"}' testfile.bin --link=my_aoc_publink_send_aoc_user --password=my_aoc_publink_send_use_pass
ascli aoc packages send -N --value=@json:'{"name":"Important files delivery"}' testfile.bin --link=my_aoc_publink_send_shd_inbox
ascli aoc user info modify @json:'{"name":"dummy change"}'
ascli aoc user info show
ascli aoc user shared_inboxes
ascli aoc user workspaces
ascli aoc workspace
ascli ats access_key --id=ak_aws delete
ascli ats access_key --id=akibmcloud --secret=somesecret cluster
ascli ats access_key --id=akibmcloud --secret=somesecret node browse /
ascli ats access_key --id=akibmcloud delete
ascli ats access_key create --cloud=aws --region=my_aws_bucket_region --params=@json:'{"id":"ak_aws","name":"my test key AWS","storage":{"type":"aws_s3","bucket":"my_aws_bucket_name","credentials":{"access_key_id":"my_aws_bucket_key","secret_access_key":"my_aws_bucket_secret"},"path":"/"}}'
ascli ats access_key create --cloud=softlayer --region=my_icos_bucket_region --params=@json:'{"id":"akibmcloud","secret":"somesecret","name":"my test key","storage":{"type":"ibm-s3","bucket":"my_icos_bucket_name","credentials":{"access_key_id":"my_icos_bucket_key","secret_access_key":"my_icos_bucket_secret"},"path":"/"}}'
ascli ats access_key list --fields=name,id
ascli ats api_key create
ascli ats api_key instances
ascli ats api_key list
ascli ats cluster clouds
ascli ats cluster list
ascli ats cluster show --cloud=aws --region=eu-west-1
ascli ats cluster show --id=1f412ae7-869a-445c-9c05-02ad16813be2
ascli conf flush_tokens
ascli conf wiz --url=https://my_aoc_org.ibmaspera.com --config-file=SAMPLE_CONFIG_FILE --pkeypath='' --username=my_aoc_user_email --test-mode=yes
ascli conf wiz --url=https://my_aoc_org.ibmaspera.com --config-file=SAMPLE_CONFIG_FILE --pkeypath='' --username=my_aoc_user_email --test-mode=yes --use-generic-client=yes
ascli config ascp connect id 'Aspera Connect for Windows' info
ascli config ascp connect id 'Aspera Connect for Windows' links id 'Windows Installer' download --to-folder=.
ascli config ascp connect id 'Aspera Connect for Windows' links list
ascli config ascp connect list
ascli config ascp info
ascli config ascp install
ascli config ascp products list
ascli config ascp show
ascli config ascp spec
ascli config check_update
ascli config doc
ascli config doc transfer-parameters
ascli config email_test --notif-to=my_recipient_email
ascli config export
ascli config genkey mykey
ascli config plugins
ascli config proxy_check --fpac=file:///examples/proxy.pac https://eudemo.asperademo.com
ascli console transfer current list 
ascli console transfer smart list 
ascli console transfer smart sub my_job_id @json:'{"source":{"paths":["my_file_name"]},"source_type":"user_selected"}'
ascli cos -N --bucket=my_icos_bucket_name --endpoint=my_icos_bucket_endpoint --apikey=my_icos_bucket_apikey --crn=my_icos_resource_instance_id node info
ascli cos -N --bucket=my_icos_bucket_name --region=my_icos_bucket_region --service-credentials=@json:@file:service_creds.json node info
ascli cos node access_key --id=self show
ascli cos node download testfile.bin --to-folder=.
ascli cos node info
ascli cos node upload testfile.bin
ascli faspex health
ascli faspex package list
ascli faspex package list --box=sent --fields=package_id --format=csv --display=data|tail -n 1);\
ascli faspex package list --fields=package_id --format=csv --display=data|tail -n 1);\
ascli faspex package recv --to-folder=. --box=sent --id="my_package_id"
ascli faspex package recv --to-folder=. --id="my_package_id"
ascli faspex package recv --to-folder=. --id=ALL --once-only=yes
ascli faspex package recv --to-folder=. --link="my_faspex_publink_recv_from_fxuser"
ascli faspex package send --delivery-info=@json:'{"title":"Important files delivery","recipients":["internal.user@example.com","FASPEX_USERNAME"]}' testfile.bin
ascli faspex package send --link="my_faspex_publink_send_to_dropbox" --delivery-info=@json:'{"title":"Important files delivery"}' testfile.bin
ascli faspex package send --link="my_faspex_publink_send_to_fxuser" --delivery-info=@json:'{"title":"Important files delivery"}' testfile.bin
ascli faspex source name "Server Files" node br /
ascli faspex5 node list --value=@json:'{"type":"received","subtype":"mypackages"}'
ascli faspex5 package list --value=@json:'{"mailbox":"inbox","state":["released"]}'
ascli faspex5 package receive --id="my_package_id" --to-folder=.
ascli faspex5 package send --value=@json:'{"title":"test title","recipients":[{"name":"${f5_user}"}]}' testfile.bin
ascli node -N -Ptst_node_preview access_key create --value=@json:'{"id":"aoc_1","storage":{"type":"local","path":"/"}}'
ascli node -N -Ptst_node_preview access_key delete --id=aoc_1
ascli node async --id=1 bandwidth 
ascli node async --id=1 counters 
ascli node async --id=1 files 
ascli node async list
ascli node async show --id=1
ascli node async show --id=ALL
ascli node basic_token
ascli node browse / -r
ascli node delete folder_1/10MB.1
ascli node delete folder_1/testfile.bin
ascli node download --to-folder=. folder_1/testfile.bin
ascli node health
ascli node info
ascli node search / --value=@json:'{"sort":"mtime"}'
ascli node service --id=service1 delete
ascli node service create @json:'{"id":"service1","type":"WATCHD","run_as":{"user":"user1"}}'
ascli node service list
ascli node transfer list --value=@json:'{"active_only":true}'
ascli node upload --to-folder="folder_1" --sources=@ts --ts=@json:'{"paths":[{"source":"/aspera-test-dir-small/10MB.1"}],"precalculate_job_size":true}' --transfer=node --transfer-info=@json:'{"url":"my_node_url","username":"my_node_user","password":"my_node_pass"}'
ascli node upload --to-folder=folder_1 --ts=@json:'{"target_rate_cap_kbps":10000}' testfile.bin
ascli orchestrator info
ascli orchestrator plugins
ascli orchestrator processes
ascli orchestrator workflow --id=ORCH_WORKFLOW_ID inputs
ascli orchestrator workflow --id=ORCH_WORKFLOW_ID start --params=@json:'{"Param":"world !"}'
ascli orchestrator workflow --id=ORCH_WORKFLOW_ID start --params=@json:'{"Param":"world !"}' --result=ResultStep:Complete_status_message
ascli orchestrator workflow --id=ORCH_WORKFLOW_ID status
ascli orchestrator workflow list
ascli orchestrator workflow status
ascli preview check --skip-types=office
ascli preview folder 1 --skip-types=office --log-level=info --file-access=remote --ts=@json:'{"target_rate_kbps":1000000}'
ascli preview scan --skip-types=office --log-level=info
ascli preview test --case=test mp4 "TSTFILE_MXF" --video-conversion=blend --log-level=debug
ascli preview test --case=test mp4 "TSTFILE_MXF" --video-conversion=clips --log-level=debug
ascli preview test --case=test mp4 "TSTFILE_MXF" --video-conversion=reencode --log-level=debug
ascli preview test --case=test png "TSTFILE_DCM" --log-level=debug
ascli preview test --case=test png "TSTFILE_DOCX" --log-level=debug
ascli preview test --case=test png "TSTFILE_MXF" --video-png-conv=animated --log-level=debug
ascli preview test --case=test png "TSTFILE_MXF" --video-png-conv=fixed --log-level=debug
ascli preview test --case=test png "TSTFILE_PDF" --log-level=debug
ascli preview trevents --once-only=yes --skip-types=office --log-level=info
ascli server -N -Ptst_hstsfaspex_ssh -Plocal_user ctl all:status
ascli server -N -Ptst_hstsfaspex_ssh -Plocal_user health app_services --format=nagios
ascli server -N -Ptst_hstsfaspex_ssh -Plocal_user health asctlstatus --format=nagios --cmd-prefix='sudo '
ascli server -N -Ptst_hstsfaspex_ssh -Plocal_user nodeadmin -- -l
ascli server -N -Ptst_server_bykey -Plocal_user br /
ascli server browse /
ascli server browse folder_1/target_hot
ascli server cp NEW_SERVER_FOLDER/testfile.bin folder_1/200KB.2
ascli server delete NEW_SERVER_FOLDER
ascli server delete folder_1/target_hot
ascli server delete folder_1/to.delete
ascli server df
ascli server download NEW_SERVER_FOLDER/testfile.bin --to-folder=. --transfer-info=@json:'{"wss":false,"resume":{"iter_max":1}}'
ascli server download NEW_SERVER_FOLDER/testfile.bin --to-folder=folder_1 --transfer=node
ascli server du /
ascli server health transfer --to-folder=folder_1 --format=nagios 
ascli server info
ascli server md5sum NEW_SERVER_FOLDER/testfile.bin
ascli server mkdir NEW_SERVER_FOLDER --logger=stdout
ascli server mkdir folder_1/target_hot
ascli server mv folder_1/200KB.2 folder_1/to.delete
ascli server upload --sources=@ts --ts=@json:'{"paths":[{"source":"testfile.bin","destination":"NEW_SERVER_FOLDER/othername"}]}'
ascli server upload --src-type=pair --sources=@json:'["testfile.bin","NEW_SERVER_FOLDER/othername"]'
ascli server upload --src-type=pair testfile.bin NEW_SERVER_FOLDER/othername --notif-to=my_recipient_email
ascli server upload --to-folder=folder_1/target_hot --lock-port=12345 --ts=@json:'{"EX_ascp_args":["--remove-after-transfer","--remove-empty-directories","--exclude-newer-than=-8","--src-base","source_hot"]}' source_hot
ascli server upload testfile.bin --to-folder=NEW_SERVER_FOLDER --ts=@json:'{"multi_session":3,"multi_session_threshold":1,"resume_policy":"none","target_rate_kbps":1500}' --transfer-info=@json:'{"spawn_delay_sec":2.5}' --progress=multi
ascli shares admin share list
ascli shares repository browse /
ascli shares repository delete /SHARES_UPLOAD/testfile.bin
ascli shares repository download --to-folder=. /SHARES_UPLOAD/testfile.bin
ascli shares repository download --to-folder=. /SHARES_UPLOAD/testfile.bin --transfer=httpgw --transfer-info=@json:'{"url":"https://HTTP_GW_FQDN/aspera/http-gwy/v1"}'
ascli shares repository upload --to-folder=/SHARES_UPLOAD testfile.bin
ascli shares repository upload --to-folder=/SHARES_UPLOAD testfile.bin --transfer=httpgw --transfer-info=@json:'{"url":"https://HTTP_GW_FQDN/aspera/http-gwy/v1"}'
ascli shares2 appinfo
ascli shares2 organization list
ascli shares2 project list --organization=Sport
ascli shares2 repository browse /
ascli shares2 userinfo
ascli sync start --parameters=@json:'{"sessions":[{"name":"test","reset":true,"remote_dir":"/sync_test","local_dir":"contents","host":"my_remote_host","tcp_port":33001,"user":"my_remote_user","private_key_path":"my_local_user_key"}]}'

...and more
```

## <a name="usage"></a>Usage

```
$ ascli -h
NAME
	ascli -- a command line tool for Aspera Applications (v4.4.0.pre)

SYNOPSIS
	ascli COMMANDS [OPTIONS] [ARGS]

DESCRIPTION
	Use Aspera application to perform operations on command line.
	Documentation and examples: https://rubygems.org/gems/aspera-cli
	execute: ascli conf doc
	or visit: http://www.rubydoc.info/gems/aspera-cli

ENVIRONMENT VARIABLES
	ASCLI_HOME  config folder, default: $HOME/.aspera/ascli
	#any option can be set as an environment variable, refer to the manual

COMMANDS
	To list first level commands, execute: ascli
	Note that commands can be written shortened (provided it is unique).

OPTIONS
	Options begin with a '-' (minus), and value is provided on command line.
	Special values are supported beginning with special prefix, like: @base64: @json: @zlib: @ruby: @csvt: @lines: @list: @val: @file: @path: @env: @stdin:.
	Dates format is 'DD-MM-YY HH:MM:SS', or 'now' or '-<num>h'

ARGS
	Some commands require mandatory arguments, e.g. a path.

OPTIONS: global
        --interactive=ENUM           use interactive input of missing params: yes, no
        --ask-options=ENUM           ask even optional options: yes, no
        --format=ENUM                output format: table, ruby, json, jsonpp, yaml, csv, nagios
        --display=ENUM               output only some information: info, data, error
        --fields=VALUE               comma separated list of fields, or ALL, or DEF
        --select=VALUE               select only some items in lists, extended value: hash (column, value)
        --table-style=VALUE          table display style
        --flat-hash=ENUM             display hash values as additional keys: yes, no
    -h, --help                       Show this message.
        --bash-comp                  generate bash completion for command
        --show-config                Display parameters used for the provided action.
    -r, --rest-debug                 more debug for HTTP calls
    -v, --version                    display version
    -w, --warnings                   check for language warnings
        --ui=ENUM                    method to start browser: text, graphical
        --log-level=ENUM             Log level: debug, info, warn, error, fatal, unknown
        --logger=ENUM                log method: stderr, stdout, syslog
        --lock-port=VALUE            prevent dual execution of a command, e.g. in cron
        --query=VALUE                additional filter for API calls (extended value) (some commands)
        --insecure=ENUM              do not validate HTTPS certificate: yes, no
        --once-only=ENUM             process only new items (some commands): yes, no

COMMAND: config
SUBCOMMANDS: gem_path genkey plugins flush_tokens list overview open echo id documentation wizard export_to_cli detect coffee ascp email_test smtp_settings proxy_check folder file check_update initdemo
OPTIONS:
        --value=VALUE                extended value for create, update, list filter
        --property=VALUE             name of property to set
        --id=VALUE                   resource identifier (modify,delete,show)
        --config-file=VALUE          read parameters from file in YAML format, current=/Users/FooBar/.aspera/ascli/config.yaml
    -N, --no-default                 do not load default configuration for plugin
        --override=ENUM              Wizard: override existing value: yes, no
        --use-generic-client=ENUM    Wizard: AoC: use global or org specific jwt client id: yes, no
        --default=ENUM               Wizard: set as default configuration for specified plugin (also: update): yes, no
        --test-mode=ENUM             Wizard: skip private key check step: yes, no
        --pkeypath=VALUE             Wizard: path to private key for JWT
        --ascp-path=VALUE            path to ascp
        --use-product=VALUE          use ascp from specified product
        --smtp=VALUE                 smtp configuration (extended value: hash)
        --fpac=VALUE                 proxy auto configuration URL
    -P, --presetVALUE                load the named option preset from current config file
        --secret=VALUE               default secret
        --secrets=VALUE              secret repository (Hash)
        --sdk-url=VALUE              URL to get SDK
        --sdk-folder=VALUE           SDK folder path
        --notif-to=VALUE             email recipient for notification of transfers
        --notif-template=VALUE       email ERB template for notification of transfers
        --version-check-days=VALUE   period in days to check new version (zero to disable)
        --ts=VALUE                   override transfer spec values (Hash, use @json: prefix), current={"create_dir"=>true}
        --local-resume=VALUE         set resume policy (Hash, use @json: prefix), current=
        --to-folder=VALUE            destination folder for downloaded files
        --sources=VALUE              list of source files (see doc)
        --transfer-info=VALUE        parameters for transfer agent
        --src-type=ENUM              type of file list: list, pair
        --transfer=ENUM              type of transfer agent: direct, httpgw, connect, node
        --progress=ENUM              type of progress bar: none, native, multi


COMMAND: shares
SUBCOMMANDS: repository admin
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
        --name=VALUE                 sync name
        --token-type=ENUM            Type of token used for transfers: aspera, basic, hybrid


COMMAND: orchestrator
SUBCOMMANDS: info workflow plugins processes
OPTIONS:
        --url=VALUE                  URL of application, e.g. https://org.asperafiles.com
        --username=VALUE             username to log in
        --password=VALUE             user's password
        --params=VALUE               parameters hash table, use @json:{"param":"value"}
        --result=VALUE               specify result value as: 'work step:parameter'
        --synchronous=ENUM           work step:parameter expected as result: yes, no
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
SUBCOMMANDS: node package auth_client jobs
OPTIONS:
        --url=VALUE                  URL of application, e.g. https://org.asperafiles.com
        --username=VALUE             username to log in
        --password=VALUE             user's password
        --client-id=VALUE            API client identifier in application
        --client-secret=VALUE        API client secret in application
        --redirect-uri=VALUE         API client redirect URI
        --auth=ENUM                  type of Oauth authentication: body_userpass, header_userpass, web, jwt, url_token, ibm_apikey, boot
        --private-key=VALUE          RSA private key PEM value for JWT (prefix file path with @val:@file:)


COMMAND: cos
SUBCOMMANDS: node
OPTIONS:
        --bucket=VALUE               IBM Cloud Object storage bucket
        --endpoint=VALUE             storage endpoint url
        --apikey=VALUE               storage API key
        --crn=VALUE                  ressource instance id
        --service-credentials=VALUE  IBM Cloud service credentials (Hash)
        --region=VALUE               IBM Cloud Object storage region


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


COMMAND: shares2
SUBCOMMANDS: repository organization project team share appinfo userinfo admin
OPTIONS:
        --url=VALUE                  URL of application, e.g. https://org.asperafiles.com
        --username=VALUE             username to log in
        --password=VALUE             user's password
        --organization=VALUE         organization
        --project=VALUE              project
        --share=VALUE                share


COMMAND: preview
SUBCOMMANDS: scan events trevents check test
OPTIONS:
        --url=VALUE                  URL of application, e.g. https://org.asperafiles.com
        --username=VALUE             username to log in
        --password=VALUE             user's password
        --skip-format=ENUM           skip this preview format (multiple possible): png, mp4
        --folder-reset-cache=ENUM    force detection of generated preview by refresh cache: no, header, read
        --skip-types=VALUE           skip types in comma separated list
        --previews-folder=VALUE      preview folder in storage root
        --temp-folder=VALUE          path to temp folder
        --skip-folders=VALUE         list of folder to skip
        --case=VALUE                 basename of output for for test
        --scan-path=VALUE            subpath in folder id to start scan in (default=/)
        --scan-id=VALUE              forder id in storage to start scan in, default is access key main folder id
        --mimemagic=ENUM             use Mime type detection of gem mimemagic: yes, no
        --overwrite=ENUM             when to overwrite result file: always, never, mtime
        --file-access=ENUM           how to read and write files in repository: local, remote
        --max-size=VALUE             maximum size (in bytes) of preview file
        --thumb-vid-scale=VALUE      png: video: size (ffmpeg scale argument)
        --thumb-vid-fraction=VALUE   png: video: position of snapshot
        --thumb-img-size=VALUE       png: non-video: height (and width)
        --video-conversion=ENUM      mp4: method for preview generation: reencode, blend, clips
        --video-png-conv=ENUM        mp4: method for thumbnail generation: fixed, animated
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
SUBCOMMANDS: reminder bearer_token organization tier_restrictions user workspace packages files gateway admin automation servers
OPTIONS:
        --url=VALUE                  URL of application, e.g. https://org.asperafiles.com
        --username=VALUE             username to log in
        --password=VALUE             user's password
        --auth=ENUM                  OAuth type of authentication: body_userpass, header_userpass, web, jwt, url_token, ibm_apikey
        --operation=ENUM             client operation for transfers: push, pull
        --client-id=VALUE            OAuth API client identifier in application
        --client-secret=VALUE        OAuth API client passcode
        --redirect-uri=VALUE         OAuth API client redirect URI
        --private-key=VALUE          OAuth JWT RSA private key PEM value (prefix file path with @val:@file:)
        --workspace=VALUE            name of workspace
        --name=VALUE                 resource name
        --path=VALUE                 file or folder path
        --link=VALUE                 public link to shared resource
        --new-user-option=VALUE      new user creation option
        --from-folder=VALUE          share to share source folder
        --scope=VALUE                OAuth scope for AoC API calls
        --bulk=ENUM                  bulk operation: yes, no
        --default-ports=ENUM         use standard FASP ports or get from node api: yes, no


COMMAND: server
SUBCOMMANDS: health nodeadmin userdata configurator ctl download upload browse delete rename ls rm mv du info mkdir cp df md5sum
OPTIONS:
        --url=VALUE                  URL of application, e.g. https://org.asperafiles.com
        --username=VALUE             username to log in
        --password=VALUE             user's password
        --ssh-keys=VALUE             ssh key path list (Array or single)
        --ssh-options=VALUE          ssh options (Hash)
        --cmd-prefix=VALUE           prefix to add for as cmd execution, e.g. sudo or /opt/aspera/bin 


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

# <a name="plugins"></a>Plugins: Application URL and Authentication

`ascli` comes with several Aspera application plugins.

REST APIs of Aspera legacy applications (Aspera Node, Faspex, Shares, Console, Orchestrator, Server) use simple username/password authentication: HTTP Basic Authentication.

Those are using options:

* url
* username
* password

Those can be provided using command line, parameter set, env var, see section above.

Aspera on Cloud relies on Oauth, refer to the [Aspera on Cloud](#aoc) section.

# <a name="aoc"></a>Plugin: Aspera on Cloud

Aspera on Cloud uses the more advanced Oauth v2 mechanism for authentication (HTTP Basic authentication is not supported).

It is recommended to use the wizard to set it up, but manual configuration is also possible.

## <a name="aocwizard"></a>Configuration: using Wizard

`ascli` provides a configuration wizard. Here is a sample invocation :

```
$ ascli config wizard
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
$ ascli aoc user info show
```

Optionally, it is possible to create a new organization-specific "integration".
For this, specify the option: `--use-generic-client=no`.

This will guide you through the steps to create.

## <a name="aocmanual"></a>Configuration: using manual setup

If you used the wizard (recommended): skip this section.

### Configuration details

Several types of OAuth authentication are supported:

* JSON Web Token (JWT) : authentication is secured by a private key (recommended for CLI)
* Web based authentication : authentication is made by user using a browser
* URL Token : external users authentication with url tokens (public links)

The authentication method is controled by option `auth`.

For a _quick start_, follow the mandatory and sufficient section: [API Client Registration](#clientreg) (auth=web) as well as [[option preset](#lprt) for Aspera on Cloud](#aocpreset).

For a more convenient, browser-less, experience follow the [JWT](#jwt) section (auth=jwt) in addition to Client Registration.

In Oauth, a "Bearer" token are generated to authenticate REST calls. Bearer tokens are valid for a period of time.`ascli` saves generated tokens in its configuration folder, tries to re-use them or regenerates them when they have expired.

### <a name="clientreg"></a>Optional: API Client Registration

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

### <a name="aocpreset"></a>[option preset](#lprt) for Aspera on Cloud

If you did not use the wizard, you can also manually create a [option preset](#lprt) for `ascli` in its configuration file.

Lets create an [option preset](#lprt) called: `my_aoc_org` using `ask` interactive input (client info from previous step):

```
$ ascli config id my_aoc_org ask url client_id client_secret
option: url> https://myorg.ibmaspera.com/
option: client_id> BJLPObQiFw
option: client_secret> yFS1mu-crbKuQhGFtfhYuoRW...
updated: my_aoc_org
```

(This can also be done in one line using the command `config id my_aoc_org update --url=...`)

Define this [option preset](#lprt) as default configuration for the `aspera` plugin:

```
$ ascli config id default set aoc my_aoc_org
```

Note: Default `auth` method is `web` and default `redirect_uri` is `http://localhost:12345`. Leave those default values.

### <a name="jwt"></a>Activation of JSON Web Token (JWT) for direct authentication

For a Browser-less, Private Key-based authentication, use the following steps.

#### Key Pair Generation

In order to use JWT for Aspera on Cloud API client authentication,
a private/public key pair must be generated (without passphrase)
This can be done using any of the following method:

(TODO: add passphrase protection as option).

* using the CLI:

```
$ ascli config genkey ~/.aspera/ascli/aocapikey
```

* `ssh-keygen`:

```
$ ssh-keygen -t rsa -f ~/.aspera/ascli/aocapikey -N ''
```

* `openssl`

(on some openssl implementation (mac) there is option: -nodes (no DES))

```
$ APIKEY=~/.aspera/ascli/aocapikey
$ openssl genrsa -passout pass:dummypassword -out ${APIKEY}.protected 2048
$ openssl rsa -passin pass:dummypassword -in ${APIKEY}.protected -out ${APIKEY}
$ openssl rsa -pubout -in ${APIKEY} -out ${APIKEY}.pub
$ rm -f ${APIKEY}.protected
```

#### API Client JWT activation

If you are not using the built-in client_id and secret, JWT needs to be authorized in Aspera on Cloud. This can be done in two manners:

* Graphically

	* Open a web browser, log to your instance: https://myorg.ibmaspera.com/
	* Go to Apps&rarr;Admin&rarr;Organization&rarr;Integrations
	* Click on the previously created application
	* select tab : "JSON Web Token Auth"
	* Modify options if necessary, for instance: activate both options in section "Settings"
	* Click "Save"

* Using command line

```
$ ascli aoc admin res client list
:............:.........:
:     id     :  name   :
:............:.........:
: BJLPObQiFw : ascli :
:............:.........:
$ ascli aoc admin res client --id=BJLPObQiFw modify @json:'{"jwt_grant_enabled":true,"explicit_authorization_required":false}'
modified
```

### User key registration

The public key must be assigned to your user. This can be done in two manners:

* Graphically

open the previously generated public key located here: `$HOME/.aspera/ascli/aocapikey.pub`

	* Open a web browser, log to your instance: https://myorg.ibmaspera.com/
	* Click on the user's icon (top right)
	* Select "Account Settings"
	* Paste the _Public Key_ in the "Public Key" section
	* Click on "Submit"

* Using command line

```
$ ascli aoc admin res user list
:........:................:
:   id   :      name      :
:........:................:
: 109952 : Tech Support   :
: 109951 : LAURENT MARTIN :
:........:................:
$ ascli aoc user info modify @ruby:'{"public_key"=>File.read(File.expand_path("~/.aspera/ascli/aocapikey.pub"))}'
modified
```

Note: the `aspera user info show` command can be used to verify modifications.

### [option preset](#lprt) modification for JWT

To activate default use of JWT authentication for `ascli` using the [option preset](#lprt), do the folowing:

* change auth method to JWT
* provide location of private key
* provide username to login as (OAuth "subject")

Execute:

```
$ ascli config id my_aoc_org update --auth=jwt --private-key=@val:@file:~/.aspera/ascli/aocapikey --username=laurent.martin.aspera@fr.ibm.com
```

Note: the private key argument represents the actual PEM string. In order to read the content from a file, use the @file: prefix. But if the @file: argument is used as is, it will read the file and set in the config file. So to keep the "@file" tag in the configuration file, the @val: prefix is added.

After this last step, commands do not require web login anymore.


### <a name="aocfirst"></a>First Use

Once client has been registered and [option preset](#lprt) created: `ascli` can be used:

```
$ ascli aoc files br /
Current Workspace: Default Workspace (default)
empty
```


### Administration

The `admin` command allows several administrative tasks (and require admin privilege).

It allows actions (create, update, delete) on "resources": users, group, nodes, workspace, etc... with the `admin resource` command.

Bulk operations are possible using option `bulk` (yes,no(default)): currently: create only. In that case, the operation expects an Array of Hash instead of a simple Hash using the [Extended Value Syntax](#extended).

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

`q` and `sort` are available on most resrouce types.

Other parameters depend on the type of entity (refer to AoC API).

Examples:

* List users with `laurent` in name:

```
ascli aoc admin res user list --query=--query=@json:'{"q":"laurent"}'
```

* List users who logded-in before a date:

```
ascli aoc admin res user list --query=@json:'{"q":"last_login_at:<2018-05-28"}'
```

* List external users and sort in reverse alphabetical order using name:

```
ascli aoc admin res user list --query=@json:'{"member_of_any_workspace":false,"sort":"-name"}'
```

Refer to the AoC API for full list of query parameters, or use the browser in developer mode with the web UI.

Note the option `select` can also be used to further refine selection, refer to [section earlier](#option_select).

#### Access Key secrets

In order to access some administrative actions on "nodes" (in fact, access keys), the associated
secret is required, it is usually provided using the `secret` option. For example in a command like:

```
$ ascli aoc admin res node --id="access_key1" --secret="secret1" v3 info
```

It is also possible to provide a set of secrets used on a regular basis. This can be done using the `secrets` option. The value provided shall be a Hash, where keys are access key ids, and values are the associated secrets.

First choose a repository name, for example `my_secrets`, and populate it like this:

```
$ ascli conf id my_secrets set 'access_key1' 'secret1'
$ ascli conf id my_secrets set 'access_key2' 'secret2'
$ ascli conf id default get config
"cli_default"
```

Here above, one already has set a `config` global preset to preset `cli_default` (refer to earlier in documentation), then the repository can be read by default like this (note the prefix `@val:` to avoid the evaluation of prefix `@preset:`):

```
$ ascli conf id cli_default set secrets @val:@preset:my_secrets
```

A secret repository can always be selected at runtime using `--secrets=@preset:xxxx`, or `--secrets=@json:'{"accesskey1":"secret1"}'`

#### Examples

* Bulk creation

```
$ ascli aoc admin res user create --bulk=yes @json:'[{"email":"dummyuser1@example.com"},{"email":"dummyuser2@example.com"}]'
:.......:.........:
:  id   : status  :
:.......:.........:
: 98398 : created :
: 98399 : created :
:.......:.........:
```

* Find with filter and delete

```
$ ascli aoc admin res user list --query='@json:{"q":"dummyuser"}' --fields=id,email
:.......:........................:
:  id   :         email          :
:.......:........................:
: 98398 : dummyuser1@example.com :
: 98399 : dummyuser2@example.com :
:.......:........................:
$ thelist=$(ascli aoc admin res user list --query='@json:{"q":"dummyuser"}' --fields=id --format=json --display=data|jq -cr 'map(.id)')
$ echo $thelist
["113501","354061"]
$ ascli aoc admin res user --bulk=yes --id=@json:"$thelist" delete
:.......:.........:
:  id   : status  :
:.......:.........:
: 98398 : deleted :
: 98399 : deleted :
:.......:.........:
```

* <a name="deactuser"></a>Find deactivated users since more than 2 years

```
ascli aoc admin res user list --query=@ruby:'{"deactivated"=>true,"q"=>"last_login_at:<#{(DateTime.now.to_time.utc-2*365*86400).iso8601}"}'
```

To delete them use the same method as before

* Display current user's workspaces

```
$ ascli aoc user workspaces
:......:............................:
:  id  :            name            :
:......:............................:
: 16   : Engineering                :
: 17   : Marketing                  :
: 18   : Sales                      :
:......:............................:
```

* Create a sub access key in a "node"

Creation of a sub-access key is like creation of access key with the following difference: authentication to node API is made with accesskey (master access key) and only the path parameter is provided: it is relative to the storage root of the master key. (id and secret are optional)

```
$ ascli aoc admin resource node --name=_node_name_ --secret=_secret_ v4 access_key create --value=@json:'{"storage":{"path":"/folder1"}}'
```

* Display transfer events (ops/transfer)

```
$ ascli aoc admin res node --secret=_secret_ v3 transfer list --value=@json:'[["q","*"],["count",5]]'
```

Examples of query (TODO: cleanup):

```
{"q":"type(file_upload OR file_delete OR file_download OR file_rename OR folder_create OR folder_delete OR folder_share OR folder_share_via_public_link)","sort":"-date"}

{"tag":"aspera.files.package_id=LA8OU3p8w"}

              # filter= 'id', 'short_summary', or 'summary'
              # count=nnn
              # tag=x.y.z%3Dvalue
              # iteration_token=nnn
              # after_time=2016-05-01T23:53:09Z
              # active_only=true|false
```

* Display node events (events)

```
$ ascli aoc admin res node --secret=_secret_ v3 events
```

* display members of a workspace

```
$ ascli aoc admin res workspace_membership list --fields=member_type,manager,member.email --query=@json:'{"embed":"member","inherited":false,"workspace_id":11363,"sort":"name"}'
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

other query parameters:

```
{"workspace_membership_through":true,"include_indirect":true}
```

* <a name="aoc_sample_member"></a>add all members of a workspace to another workspace

a- Get id of first workspace

```
WS1='First Workspace'
WS1ID=$(ascli aoc admin res workspace list --query=@json:'{"q":"'"$WS1"'"}' --select=@json:'{"name":"'"$WS1"'"}' --fields=id --format=csv)
```

b- Get id of second workspace

```
WS2='Second Workspace'
WS2ID=$(ascli aoc admin res workspace list --query=@json:'{"q":"'"$WS2"'"}' --select=@json:'{"name":"'"$WS2"'"}' --fields=id --format=csv)
```

c- Extract membership information

```
$ ascli aoc admin res workspace_membership list --fields=manager,member_id,member_type,workspace_id --query=@json:'{"workspace_id":'"$WS1ID"'}' --format=jsonpp > ws1_members.json
```

d- Convert to creation data for second workspace:

```
grep -Eve '(direct|effective_manager|_count|storage|"id")' ws1_members.json|sed '/workspace_id/ s/"'"$WS1ID"'"/"'"$WS2ID"'"/g' > ws2_members.json
```

or, using jq:

```
jq '[.[] | {member_type,member_id,workspace_id,manager,workspace_id:"'"$WS2ID"'"}]' ws1_members.json > ws2_members.json
```

e- Add members to second workspace

```
$ ascli aoc admin res workspace_membership create --bulk=yes @json:@file:ws2_members.json
```

* Get users who did not log since a date

```
$ ascli aoc admin res user list --fields=email --query=@json:'{"q":"last_login_at:<2018-05-28"}'
:...............................:
:             email             :
:...............................:
: John.curtis@acme.com          :
: Jean.Dupont@tropfort.com      :
:...............................:
```

* List "Limited" users

```
$ ascli aoc admin res user list --fields=email --select=@json:'{"member_of_any_workspace":false}'
```

* Perform a multi Gbps transfer between two remote shared folders

In this example, a user has access to a workspace where two shared folders are located on differente sites, e.g. different cloud regions.

First, setup the environment (skip if already done)

```
$ ascli conf wizard --url=https://sedemo.ibmaspera.com --username=laurent.martin.aspera@fr.ibm.com
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
$ ascli aoc user info show
```

This creates the option preset "aoc_&lt;org name&gt;" to allow seamless command line access and sets it as default for aspera on cloud.

Then, create two shared folders located in two regions, in your files home, in a workspace.

Then, transfer between those:

```
$ ascli -Paoc_show aoc files transfer --from-folder='IBM Cloud SJ' --to-folder='AWS Singapore' 100GB.file --ts=@json:'{"target_rate_kbps":"1000000","multi_session":10,"multi_session_threshold":1}'
```

* create registration key to register a node

```
$ ascli aoc admin res admin/client create @json:'{"data":{"name":"laurentnode","client_subject_scopes":["alee","aejd"],"client_subject_enabled":true}}' --fields=token --format=csv
jfqslfdjlfdjfhdjklqfhdkl
```

* delete all registration keys

```
$ ascli aoc admin res admin/client list --fields=id --format=csv|ascli aoc admin res admin/client delete --bulk=yes --id=@lines:@stdin:
+-----+---------+
| id  | status  |
+-----+---------+
| 99  | deleted |
| 100 | deleted |
| 101 | deleted |
| 102 | deleted |
+-----+---------+
```

* List packages in a given shared inbox

First retrieve the id of the shared inbox, and then list packages with the appropriate filter.
(To find out available filters, consult the API definition, or use the web interface in developer mode).

Note that when no query is provided, the query used by default is: `{"archived":false,"exclude_dropbox_packages":true,"has_content":true,"received":true}`. The workspace id is added if not already present in the query.

```
shbxid=$(ascli aoc user shared_inboxes --select=@json:'{"dropbox.name":"My Shared Inbox"}' --format=csv --fields=dropbox_id --display=data)

ascli aoc packages list --query=@json:'{"dropbox_id":"'$shbxid'","archived":false,"received":true,"has_content":true,"exclude_dropbox_packages":false,"include_draft":false,"sort":"-received_at"}'
```

## Shared folders

* list shared folders in node

```
$ ascli aoc admin res node --id=8669 shared_folders
```

* list shared folders in workspace

```
$ ascli aoc admin res workspace --id=10818 shared_folders
```

* list members of shared folder

```
$ ascli aoc admin res node --id=8669 v4 perm 82 show
```

## Send a Package

Send a package:

```
$ ascli aoc packages send --value=[package extended value] [other parameters such as file list and transfer parameters]
```

Notes:

* the `value` parameter can contain any supported package creation parameter. Refer to the AoC package creation API, or display an existing package to find attributes.
* to provide the list of recipients, use fields: "recipients" and/or "bcc_recipients". ascli will resolve the list of email addresses to expected user ids.
* a recipient can be a shared inbox, in this case just use the name of the shared inbox as recipient.
* If a recipient is not already registered and the workspace allows external users, then the package is sent to an external user, and
  * if the option `new_user_option` is `@json:{"package_contact":true}` (default), then a public link is sent and the external user does not need to create an account.
  * if the option `new_user_option` is `@json:{}`, then external users are invited to join the workspace

Examples:

```
$ ascli aoc package send --value=@json:'{"name":"my title","note":"my note","recipients":["laurent.martin.aspera@fr.ibm.com","other@example.com"]}' --sources=@args my_file.dat
```

```
$ ascli aoc package send --value=@json:'{"name":"my file in shared inbox","recipients":["The Shared Inbox"]}' my_file.dat --ts=@json:'{"target_rate_kbps":100000}'
```

```
$ ascli aoc package send --workspace=eudemo --value=@json:'{"name":"my pack title","recipients":["Shared Inbox Name"],"metadata":[{"input_type":"single-text","name":"Project Id","values":["123"]},{"input_type":"single-dropdown","name":"Type","values":["Opt2"]},{"input_type":"multiple-checkbox","name":"CheckThose","values":["Check1","Check2"]},{"input_type":"date","name":"Optional Date","values":["2021-01-13T15:02:00.000Z"]}]}' ~/Documents/Samples/200KB.1
```

## <a name="aoccargo"></a>Receive new packages only

It is possible to automatically download new packages, like using Aspera Cargo:

```
$ ascli aoc packages recv --id=ALL --once-only=yes --lock-port=12345
```

* `--id=ALL` (case sensitive) will download all packages
* `--once-only=yes` keeps memory of any downloaded package in persistency files located in the configuration folder.
* `--lock-port=12345` ensures that only one instance is started at the same time, to avoid collisions

Typically, one would execute this command on a regular basis, using the method of your choice:

* Windows: [Task Scheduler](https://docs.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-start-page)
* Linux/Unix: [cron](https://www.man7.org/linux/man-pages/man5/crontab.5.html)
* etc...

## Download Files

Download of files is straightforward with a specific syntax for the `aoc files download` action: Like other commands the source file list is provided as  a list with the `sources` option. Nevertheless, consider this:

* if only one source is provided, it is downloaded
* if multiple sources must be downloaded, then the first in list is the path of the source folder, and the remaining items are the file names in this folder (without path).

## Find Files

The command `aoc files find [--value=expression]` will recursively scan storage to find files matching the expression criteria. It works also on node resource using the v4 command. (see examples)

The expression can be of 3 formats:

* empty (default) : all files, equivalent to value: `exec:true`
* not starting with `exec:` : the expression is a regular expression, using [Ruby Regex](https://ruby-doc.org/core/Regexp.html) syntax. equivalent to value: `exec:f['name'].match(/expression/)`

For instance, to find files with a special extension, use `--value='\.myext$'`

* starting with `exec:` : the Ruby code after the prefix is executed for each entry found. The entry variable name is `f`. The file is displayed if the result of the expression is true;

Examples of expressions: (using like this: `--value=exec:'<expression>'`)

* Find files more recent than 100 days

```
f["type"].eql?("file") and (DateTime.now-DateTime.parse(f["modified_time"]))<100
```

* Find files older than 1 year on a given node and store in file list

```
$ ascli aoc admin res node --name='my node name' --secret='my secret' v4 find / --fields=path --value='exec:f["type"].eql?("file") and (DateTime.now-DateTime.parse(f["modified_time"]))<100' --format=csv > my_file_list.txt
```

* Delete the files, one by one

```
$ cat my_file_list.txt|while read path;do echo ascli aoc admin res node --name='my node name' --secret='my secret' v4 delete "$path" ;done
```

* Delete the files in bulk

```
cat my_file_list.txt | ascli aoc admin res node --name='my node name' --secret='my secret' v3 delete @lines:@stdin:
```

## Activity

The activity app can be queried with:

```
$ ascli aoc admin analytics transfers
```

It can also support filters and send notification using option `notif_to`. a template is defined using option `notif_template` :

`mytemplate.erb`:

```
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

```
$ ascli aoc admin analytics transfers --once-only=yes --lock-port=12345 \
--query=@json:'{"status":"completed","direction":"receive"}' \
--notif-to=active --notif-template=@file:mytemplate.erb
```

Options:

* `once_only` keep track of last date it was called, so next call will get only new events
* `query` filter (on API call)
* `notify` send an email as specified by template, this could be places in a file with the `@file` modifier.

Note this must not be executed in less than 5 minutes because the analytics interface accepts only a period of time between 5 minutes and 6 months. The period is [date of previous execution]..[now].

## Using specific transfer ports

By default transfer nodes are expected to use ports TCP/UDP 33001. The web UI enforces that. The option `default_ports` ([yes]/no) allows ascli to retrieve the server ports from an API call (download_setup) which reads the information from `aspera.conf` on the server.


# Plugin: Aspera Transfer Service

ATS is usable either :

* from an AoC subscription : ascli aoc admin ats : use AoC authentication

* or from an IBM Cloud subscription : ascli ats : use IBM Cloud API key authentication

## IBM Cloud ATS : creation of api key

First get your IBM Cloud APIkey. For instance, it can be created using the IBM Cloud web interface, or using command line:

```
$ ibmcloud iam api-key-create mykeyname -d 'my sample key'
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

```
$ ascli config id my_ibm_ats update --ibm-api-key=my_secret_api_key_here_8f8d9fdakjhfsashjk678
$ ascli config id default set ats my_ibm_ats
$ ascli ats api_key instances
+--------------------------------------+
| instance                             |
+--------------------------------------+
| aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee |
+--------------------------------------+
$ ascli config id my_ibm_ats update --instance=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
$ ascli ats api_key create
+--------+----------------------------------------------+
| key    | value                                        |
+--------+----------------------------------------------+
| id     | ats_XXXXXXXXXXXXXXXXXXXXXXXX                 |
| secret | YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY |
+--------+----------------------------------------------+
$ ascli config id my_ibm_ats update --ats-key=ats_XXXXXXXXXXXXXXXXXXXXXXXX --ats-secret=YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY
```
## Cross Organization transfers

It is possible to transfer files directly between organizations without having to first download locally and then upload...

Although optional, the creation of [option preset](#lprt) is recommended to avoid placing all parameters in the command line.

Procedure to send a file from org1 to org2:

* Get access to Organization 1 and create a [option preset](#lprt): e.g. `org1`, for instance, use the [Wizard](#aocwizard)
* Check that access works and locate the source file e.g. `mysourcefile`, e.g. using command `files browse`
* Get access to Organization 2 and create a [option preset](#lprt): e.g. `org2`
* Check that access works and locate the destination folder `mydestfolder`
* execute the following:

```
$ ascli -Porg1 aoc files node_info /mydestfolder --format=json --display=data | ascli -Porg2 aoc files upload mysourcefile --transfer=node --transfer-info=@json:@stdin:
```

Explanation:

* `-Porg1 aoc` use Aspera on Cloud plugin and load credentials for `org1`
* `files node_info /mydestfolder` generate transfer information including node api credential and root id, suitable for the next command
* `--format=json` format the output in JSON (instead of default text table)
* `--display=data` display only the result, and remove other information, such as workspace name
* `|` the standard output of the first command is fed into the second one
* `-Porg2 aoc` use Aspera on Cloud plugin and load credentials for `org2`
* `files upload mysourcefile` upload the file named `mysourcefile` (located in `org1`)
* `--transfer=node` use transfer agent type `node` instead of default [`direct`](#direct)
* `--transfer-info=@json:@stdin:` provide `node` transfer agent information, i.e. node API credentials, those are expected in JSON format and read from standard input

Note that when using a POSIX shell, another possibility to write `cmd1 | cmd2 --transfer-info=@json:stdin:` is `cmd2 --transfer-info=@json:$(cmd1)` instead of ``
## Examples

Example: create access key on softlayer:

```
$ ascli ats access_key create --cloud=softlayer --region=ams --params=@json:'{"storage":{"type":"softlayer_swift","container":"_container_name_","credentials":{"api_key":"value","username":"_name_:_usr_name_"},"path":"/"},"id":"_optional_id_","name":"_optional_name_"}'
```

Example: create access key on AWS:

```
$ ascli ats access_key create --cloud=aws --region=eu-west-1 --params=@json:'{"id":"testkey3","name":"laurent key AWS","storage":{"type":"aws_s3","bucket":"my-bucket","credentials":{"access_key_id":"AKIA_MY_API_KEY","secret_access_key":"my/secret/here"},"path":"/laurent"}}'

```

Example: create access key on Azure SAS:

```
$ ascli ats access_key create --cloud=azure --region=eastus --params=@json:'{"id":"testkeyazure","name":"laurent key azure","storage":{"type":"azure_sas","credentials":{"shared_access_signature":"https://containername.blob.core.windows.net/blobname?sr=c&..."},"path":"/"}}'

```

(Note that the blob name is mandatory after server address and before parameters. and that parameter sr=c is mandatory.)

Example: create access key on Azure:

```
$ ascli ats access_key create --cloud=azure --region=eastus --params=@json:'{"id":"testkeyazure","name":"laurent key azure","storage":{"type":"azure","credentials":{"account":"myaccount","key":"myaccesskey","storage_endpoint":"myblob"},"path":"/"}}'

```

delete all my access keys:

```
for k in $(ascli ats access_key list --field=id --format=csv);do ascli ats access_key id $k delete;done
```

# Plugin: IBM Aspera High Speed Transfer Server (transfer)

This plugin works at FASP level (SSH/ascp/ascmd) and does not use the node API.

## Authentication

Both password and SSH keys auth are supported.

If not username is provided, the default transfer user `xfer` is used.

If no ssh password or key is provided, and a token is provided in transfer spec, then standard bypass keys are used.

```
$ ascli server --url=ssh://... --ts=@json:'{"token":"Basic abc123"}'
```

Multiple SSH key paths can be provided. The value of the parameter `ssh_keys` can be a single value or an array. Each value is a path to a private key and is expanded ("~" is replaced with the user's home folder).

Examples:

```
$ ascli server --ssh-keys=~/.ssh/id_rsa
$ ascli server --ssh-keys=@list:,~/.ssh/id_rsa
$ ascli server --ssh-keys=@json:'["~/.ssh/id_rsa"]'
```

The underlying ssh library `net::ssh` provides several options that may be used depending on environment. By default the ssh library expect that an ssh-agent is running.

If you get an error message such as:

```
[Linux]
ERROR -- net.ssh.authentication.agent: could not connect to ssh-agent: Agent not configured
```

or

```
[Windows]
ERROR -- net.ssh.authentication.agent: could not connect to ssh-agent: pageant process not running
```

This means that you dont have such an ssh agent running:

* check env var: `SSH_AGENT_SOCK`
* check if the key is protected with a passphrase
* [check the manual](https://net-ssh.github.io/ssh/v1/chapter-2.html#s2)
* To diable use of `ssh-agent`, use the option `ssh_option` like this (or set in preset):

```
$ ascli server --ssh-options=@ruby:'{use_agent: false}' ...
```

This can also be set as default using a preset.

## Example

One can test the "server" application using the well known demo server:

```
$ ascli config id aspera_demo_server update --url=ssh://demo.asperasoft.com:33001 --username=asperaweb --password=_demo_pass_
$ ascli config id default set server aspera_demo_server
$ ascli server browse /aspera-test-dir-large
$ ascli server download /aspera-test-dir-large/200MB
```

This creates a [option preset](#lprt) "aspera_demo_server" and set it as default for application "server"


# Plugin: IBM Aspera High Speed Transfer Server (node)

This plugin gives access to capabilities provided by HSTS node API.

## File Operations

It is possible to:
* browse
* transfer (upload / download)
* ...

For transfers, it is possible to control how transfer is authorized using option: `token_type`:

* `aspera` : api `<upload|download>_setup` is called to create the transfer spec including the Aspera token
* `basic` : transfer spec is created like this:

```
{
  "remote_host": address of node url,
  "remote_user": "xfer",
  "ssh_port": 33001,
  "token": "Basic <base 64 encoded user/pass>",
  "direction": send/recv
}
```

* `hybrid` : same as `aspera`, but token is replaced with basic token like `basic`

## Central

The central subcommand uses the "reliable query" API (session and file). It allows listing transfer sessions and transfered files.

Filtering can be applied:

```
$ ascli node central file list
```

by providing the `validator` option, offline transfer validation can be done.

## FASP Stream

It is possible to start a FASPStream session using the node API:

Use the "node stream create" command, then arguments are provided as a [_transfer-spec_](#transferspec).

```
$ ascli node stream create --ts=@json:'{"direction":"send","source":"udp://233.3.3.4:3000?loopback=1&ttl=2","destination":"udp://233.3.3.3:3001/","remote_host":"localhost","remote_user":"stream","remote_password":"XXXX"}' --preset=stream
```

## Watchfolder

Refer to [Aspera documentation](https://download.asperasoft.com/download/docs/entsrv/3.7.4/es_admin_linux/webhelp/index.html#watchfolder_external/dita/json_conf.html) for watch folder creation.

`ascli` supports remote operations through the node API. Operations are:

* Start watchd and watchfolderd services running as a system user having access to files
* configure a watchfolder to define automated transfers

```
$ ascli node service create @json:'{"id":"mywatchd","type":"WATCHD","run_as":{"user":"user1"}}'
$ ascli node service create @json:'{"id":"mywatchfolderd","type":"WATCHFOLDERD","run_as":{"user":"user1"}}'
$ ascli node watch_folder create @json:'{"id":"mywfolder","source_dir":"/watch1","target_dir":"/","transport":{"host":"10.25.0.4","user":"user1","pass":"mypassword"}}'
```

## Out of Transfer File Validation

Follow the Aspera Transfer Server configuration to activate this feature.

```
$ ascli node central file list --validator=ascli --data=@json:'{"file_transfer_filter":{"max_result":1}}'
:..............:..............:............:......................................:
: session_uuid :    file_id   :   status   :              path                    :
:..............:..............:............:......................................:
: 1a74444c-... : 084fb181-... : validating : /home/xfer.../PKG - my title/200KB.1 :
:..............:..............:............:......................................:
$ ascli node central file update --validator=ascli --data=@json:'{"files":[{"session_uuid": "1a74444c-...","file_id": "084fb181-...","status": "completed"}]}'
updated
```

## Example: SHOD to ATS

Access to a "Shares on Demand" (SHOD) server on AWS is provided by a partner. And we need to
transfer files from this third party SHOD instance into our Azure BLOB storage.
Simply create an "Aspera Transfer Service" instance (https://ts.asperasoft.com), which
provides access to the node API.
Then create a configuration for the "SHOD" instance in the configuration file: in section
"shares", a configuration named: awsshod.
Create another configuration for the Azure ATS instance: in section "node", named azureats.
Then execute the following command:

```
$ ascli node download /share/sourcefile --to-folder=/destinationfolder --preset=awsshod --transfer=node --transfer-info=@preset:azureats
```

This will get transfer information from the SHOD instance and tell the Azure ATS instance
to download files.

## Create access key

```
$ ascli node access_key create --value=@json:'{"id":"eudemo-sedemo","secret":"mystrongsecret","storage":{"type":"local","path":"/data/asperafiles"}}'
```

# Plugin: IBM Aspera Faspex5

3 authentication methods are supported:

* jwt
* web
* boot

For JWT, create an API client in Faspex with jwt support, and use: `--auth=jwt`.

For web method, create an API client in Faspex, and use: --auth=web

For boot method: (will be removed in future)

* open a browser
* start developer mode
* login to faspex 5
* find the first API call with `Authorization` token, and copy it (kind of base64 long string)

Use it as password and use `--auth=boot`.

```
$ ascli conf id f5boot update --url=https://localhost/aspera/faspex --auth=boot --password=ABC.DEF.GHI...
```

Ready to use Faspex5 with CLI.

# Plugin: IBM Aspera Faspex (4.x)

Notes:

* The command "v4" requires the use of APIv4, refer to the Faspex Admin manual on how to activate.
* For full details on Faspex API, refer to: [Reference on Developer Site](https://developer.ibm.com/apis/catalog/?search=faspex)

## Listing Packages

Command: `faspex package list`

### Option `box`

By default it looks in box `inbox`, but the following boxes are also supported: `archive` and `sent`, selected with option `box`.

### Option `recipient`

A user can receive a package because the recipient is:

* the user himself (default)
* the user is part of a dropbox or a workgroup (select with option `recipient` with value `*<name of WG or DB>`

### Option `query`

As inboxes may be large, it is possible to use the following query parameters:

* `count` : (native) number items in one API call (default=0, equivalent to 10)
* `page` : (native) id of page in call (default=0)
* `startIndex` : (native) index of item to start, default=0, oldest index=0
* `max` : maximum number of items
* `pmax` : maximum number of pages

(SQL query is `LIMIT <startIndex>, <count>`)

The API is listed in [Faspex 4 API Reference](https://developer.ibm.com/apis/catalog/?search=faspex) under "Services (API v.3)".

If no parameter `max` or `pmax` is provided, then all packages will be listed in the inbox, which result in paged API calls (using parameter: `count` and `page`). By default page is `0` (`10`), it can be increased to have less calls.

### Example

```
$ ascli faspex package list --box=inbox --recipient='*my_dropbox' --query=@json:'{"max":20,"pmax":2,"count":20}'
```

List a maximum of 20 items grouped by pages of 20, with maximum 2 pages in received box (inbox) when received in dropbox `*my_dropbox`.

## Receiving a Package

The command is `package recv`, possible methods are:

* provide a package id with option `id`
* provide a public link with option `link`
* provide a `faspe:` URI with option `link`

```
$ ascli faspex package recv --id=12345
$ ascli faspex package recv --link=faspe://...
```

If the package is in a specific dropbox, add option `recipient` for both the `list` and `recv` commands.

```
$ ascli faspex package list --recipient='*thedropboxname'
```

if `id` is set to `ALL`, then all packages are downloaded, and if option `once_only`is used, then a persistency file is created to keep track of already downloaded packages.

## Sending a Package

The command is `faspex package send`. Package information (title, note, metadata, options) is provided in option `delivery_info`. (Refer to Faspex API).

Example:

```
$ ascli faspex package send --delivery-info=@json:'{"title":"my title","recipients":["laurent.martin.aspera@fr.ibm.com"]}' --url=https://faspex.corp.com/aspera/faspex --username=foo --password=bar /tmp/file1 /home/bar/file2
```

If the recipient is a dropbox, just provide the name of the dropbox in `recipients`: `"recipients":["My Dropbox Name"]`

Additional optional parameters in `delivery_info`:

* Package Note: : `"note":"note this and that"`
* Package Metadata: `"metadata":{"Meta1":"Val1","Meta2":"Val2"}`

## Email notification on transfer

Like for any transfer, a notification can be sent by email using parameters: `notif_to` and `notif_template` .

Example:

```
$ ascli faspex package send --delivery-info=@json:'{"title":"test pkg 1","recipients":["aspera.user1@gmail.com"]}' ~/Documents/Samples/200KB.1 --notif-to=aspera.user1@gmail.com --notif-template=@ruby:'%Q{From: <%=from_name%> <<%=from_email%>>\nTo: <<%=to%>>\nSubject: Package sent: <%=ts["tags"]["aspera"]["faspex"]["metadata"]["_pkg_name"]%> files received\n\nTo user: <%=ts["tags"]["aspera"]["faspex"]["recipients"].first["email"]%>}'
```

In this example the notification template is directly provided on command line. Package information placed in the message are directly taken from the tags in transfer spec. The template can be placed in a file using modifier: `@file:`

## Operation on dropboxes

Example:

```
$ ascli faspex v4 dropbox create --value=@json:'{"dropbox":{"e_wg_name":"test1","e_wg_desc":"test1"}}'
$ ascli faspex v4 dropbox list
$ ascli faspex v4 dropbox delete --id=36
```

## Remote sources

Faspex lacks an API to list the contents of a remote source (available in web UI). To workaround this,
the node API is used, for this it is required to add a section ":storage" that links
a storage name to a node config and sub path.

Example:

```yaml
my_faspex_conf:
  url: https://10.25.0.3/aspera/faspex
  username: admin
  password: MyPassword
  storage:
    testlaurent:
      node: "@preset:my_faspex_node"
      path: /myfiles
my_faspex_node:
  url: https://10.25.0.3:9092
  username: node_faspex
  password: MyPassword
```

In this example, a faspex storage named "testlaurent" exists in Faspex, and is located
under the docroot in "/myfiles" (this must be the same as configured in Faspex).
The node configuration name is "my_faspex_node" here.

Note: the v4 API provide an API for nodes and shares.

## Automated package download (cargo)

It is possible to tell `ascli` to download newly received packages, much like the official
cargo client, or drive. Refer to the [same section](#aoccargo) in the Aspera on Cloud plugin:

```
$ ascli faspex packages recv --id=ALL --once-only=yes --lock-port=12345
```

# Plugin: IBM Aspera Shares

Aspera Shares supports the "node API" for the file transfer part. (Shares 1 and 2)

In Shares2, users, groups listing are paged, to display sequential pages:

```
$ for p in 1 2 3;do ascli shares2 admin users list --value=@json:'{"page":'$p'}';done
```

# Plugin: IBM Cloud Object Storage

The IBM Cloud Object Storage provides the possibility to execute transfers using FASP.
It uses the same transfer service as Aspera on Cloud, called Aspera Transfer Service (ATS).
Available ATS regions: [https://status.aspera.io](https://status.aspera.io)

There are two possibilities to provide credentials. If you already have the endpoint, apikey and CRN, use the forst method. If you dont have credentials but have access to the IBM Cloud console, then use the second method.

## Using endpoint, apikey and Ressource Instance ID (CRN)

If you have those parameters already, then following options shall be provided:

* `bucket` bucket name
* `endpoint` storage endpoint url, e.g. https://s3.hkg02.cloud-object-storage.appdomain.cloud
* `apikey` API Key
* `crn` resource instance id

For example, let us create a default configuration:

```
$ ascli conf id mycos update --bucket=mybucket --endpoint=https://s3.us-east.cloud-object-storage.appdomain.cloud --apikey=abcdefgh --crn=crn:v1:bluemix:public:iam-identity::a/xxxxxxx
$ ascli conf id default set cos mycos
```

Then, jump to the transfer example.

## Using service credential file

If you are the COS administrator and dont have yet the credential: Service credentials are directly created using the IBM cloud web ui. Navigate to:

Navigation Menu &rarr; Resource List &rarr; Storage &rarr; Cloud Object Storage &rarr; Service Credentials &rarr; &lt;select or create credentials&gt; &rarr; view credentials &rarr; copy

Then save the copied value to a file, e.g. : `$HOME/cos_service_creds.json`

or using the IBM Cloud CLI:

```
$ ibmcloud resource service-keys
$ ibmcloud resource service-key aoclaurent --output JSON|jq '.[0].credentials'>$HOME/service_creds.json
```

(if you dont have `jq` installed, extract the structure as follows)

It consists in the following structure:

```
{
  "apikey": "xxxxxxx.....",
  "cos_hmac_keys": {
    "access_key_id": "xxxxxxx.....",
    "secret_access_key": "xxxxxxx....."
  },
  "endpoints": "https://control.cloud-object-storage.cloud.ibm.com/v2/endpoints",
  "iam_apikey_description": "my description ...",
  "iam_apikey_name": "my key name",
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

```
$ ascli conf id mycos update --bucket=laurent --service-credentials=@val:@json:@file:~/service_creds.json --region=us-south
$ ascli conf id default set cos mycos
```

## Operations, transfers

Let's assume you created a default configuration from once of the two previous steps (else specify the access options on command lines).

A subset of `node` plugin operations are supported, basically node API:

```
$ ascli cos node info
$ ascli cos node upload 'faux:///sample1G?1g'
```

Note: we generate a dummy file `sample1G` of size 2GB using the `faux` PVCL (man ascp and section above), but you can of course send a real file by specifying a real file instead.

# Plugin: IBM Aspera Sync

A basic plugin to start an "async" using `ascli`.
The main advantage is the possibility to start from ma configuration file, using `ascli` standard options.

# Plugin: Preview

The `preview` generates "previews" of graphical files, i.e. thumbnails (office, images, video) and video previews on storage for use primarily in the Aspera on Cloud application.
This is based on the "node API" of Aspera HSTS when using Access Keys only inside it's "storage root".
Several parameters can be used to tune several aspects:

  * methods for detection of new files needing generation
  * methods for generation of video preview
  * parameters for video handling

## Aspera Server configuration

Specify the previews folder as shown in:

<https://ibmaspera.com/help/admin/organization/installing_the_preview_maker>

By default, the `preview` plugin expects previews to be generated in a folder named `previews` located in the storage root. On the transfer server execute:

```
# /opt/aspera/bin/asconfigurator -x "server;preview_dir,previews"
# /opt/aspera/bin/asnodeadmin --reload
```

Note: the configuration `preview_dir` is *relative* to the storage root, no need leading or trailing `/`. In general just set the value to `previews`

If another folder is configured on the HSTS, then specify it to `ascli` using the option `previews_folder`.

The HSTS node API limits any preview file to a parameter: `max_request_file_create_size_kb` (1 KB is 1024 bytes).
This size is internally capped to `1<<24` Bytes (16777216) , i.e. 16384 KBytes.

To change this parameter in `aspera.conf`, use `asconfigurator`. To display the value, use `asuserdata`:

```
# /opt/aspera/bin/asuserdata -a | grep max_request_file_create_size_kb
  max_request_file_create_size_kb: "1024"
# /opt/aspera/bin/asconfigurator -x "server; max_request_file_create_size_kb,16384"
```

If you use a value different than 16777216, then specify it using option `max_size`.

Note: the HSTS parameter (max_request_file_create_size_kb) is in *kiloBytes* while the generator parameter is in *Bytes* (factor of 1024).

## <a name="prev_ext"></a>External tools: Linux

The tool requires the following external tools available in the `PATH`:

* ImageMagick : `convert` `composite`
* OptiPNG : `optipng`
* FFmpeg : `ffmpeg` `ffprobe`
* Libreoffice : `libreoffice`
* ruby gem `mimemagic`

Here shown on Redhat/CentOS.

Other OSes should work as well, but are note tested.

To check if all tools are found properly, execute:

```
$ ascli preview check
```

### mimemagic

To benefit from extra mime type detection install gem mimemagic:

```
# gem install mimemagic
```

or to install an earlier version if any problem:

```
# gem install mimemagic -v '~> 0.3.0'
```

To use it, set option `mimemagic` to `yes`: `--mimemagic=yes`

If not used, Mime type used for conversion is the one provided by the node API.

If used, it the `preview` command will first analyse the file content using mimemagic, and if no match, will try by extension.

### Image: Imagemagick and optipng

```
yum install -y ImageMagick optipng
```

### Video: FFmpeg

The easiest method is to download and install the latest released version of ffmpeg with static libraries from [https://johnvansickle.com/ffmpeg/](https://johnvansickle.com/ffmpeg/)

```
curl -s https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz|(mkdir -p /opt && cd /opt && rm -f ffmpeg /usr/bin/{ffmpeg,ffprobe} && rm -fr ffmpeg-*-amd64-static && tar xJvf - && ln -s ffmpeg-* ffmpeg && ln -s /opt/ffmpeg/{ffmpeg,ffprobe} /usr/bin)
```

### Office: Unoconv and Libreoffice

If you dont want to have preview for office dpcuments or if it is too complex you can skip office document preview generation by using option: `--skip-types=office`

The generation of preview in based on the use of `unoconv` and `libreoffice`

* Centos 8

```
# dnf install unoconv
```

* Amazon Linux

```
# amazon-linux-extras enable libreoffice
# yum clean metadata
# yum install libreoffice-core libreoffice-calc libreoffice-opensymbol-fonts libreoffice-ure libreoffice-writer libreoffice-pyuno libreoffice-impress
# wget https://raw.githubusercontent.com/unoconv/unoconv/master/unoconv
# mv unoconv /usr/bin
# chmod a+x /usr/bin/unoconv
```

## Configuration

The preview generator is run as a user, preferably a regular user (not root). When using object storage, any user can be used, but when using local storage it is usually better to use the user `xfer`, as uploaded files are under this identity: this ensures proper access rights. (we will assume this)

Like any `ascli` commands, parameters can be passed on command line or using a configuration [option preset](#lprt).  The configuration file must be created with the same user used to run so that it is properly used on runtime.

Note that the `xfer` user has a special protected shell: `aspshell`, so changing identity requires specification of alternate shell:

```
# su -s /bin/bash - xfer
$ ascli config id previewconf update --url=https://localhost:9092 --username=my_access_key --password=my_secret --skip-types=office --lock-port=12346
$ ascli config id default set preview previewconf
```

Here we assume that Office file generation is disabled, else remove this option.
`lock_port` prevents concurrent execution of generation when using a scheduler.

One can check if the access key is well configured using:

```
$ ascli -Ppreviewconf node browse /
```

This shall list the contents of the storage root of the access key.

## Execution

The tool intentionally supports only a "one shot" mode (no infinite loop) in order to avoid having a hanging process or using too many resources (calling REST api too quickly during the scan or event method).
It needs to be run on a regular basis to create or update preview files. For that use your best
reliable scheduler. For instance use "CRON" on Linux or Task Scheduler on Windows.

Typically, for "Access key" access, the system/transfer is `xfer`. So, in order to be consistent have generate the appropriate access rights, the generation process should be run as user `xfer`.

Lets do a one shot test, using the configuration previously created:

```
# su -s /bin/bash - xfer
xfer$ ascli preview scan --overwrite=always
```

When the preview generator is first executed it will create a file: `.aspera_access_key`
in the previews folder which contains the access key used.
On subsequent run it reads this file and check that previews are generated for the same access key, else it fails. This is to prevent clash of different access keys using the same root.

## Configuration for Execution in scheduler

Here is an example of configuration for use with cron on Linux.
Adapt the scripts to your own preference.

We assume here that a configuration preset was created as shown previously.

Lets first setup a script that will be used in the sceduler and sets up the environment.

Example of startup script `cron_ascli`, which sets the Ruby environment and adds some timeout protection:

```
#!/bin/bash
# set a timeout protection, just in case
case "$*" in *trev*) tmout=10m ;; *) tmout=30m ;; esac
. /etc/profile.d/rvm.sh
rvm use 2.6 --quiet
exec timeout ${tmout} ascli "${@}"
```

Here the cronjob is created for user `xfer`.

```
xfer$ crontab<<EOF
0    * * * *  /home/xfer/cron_ascli preview scan --logger=syslog --display=error
2-59 * * * *  /home/xfer/cron_ascli preview trev --logger=syslog --display=error
EOF
```

Note that the loging options are kept in the cronfile instead of conf file to allow execution on command line with output on command line.

## Candidate detection for creation or update (or deletion)

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

```
$ ascli preview scan --skip-folders=@json:'["/not_here"]'
```

The option `folder_reset_cache` forces the node service to refresh folder contents using various methods.

When scanning the option `value` has the same behaviour as for the `node find` command.

For instance to filter out files beginning with `._` do:

```
... --value='exec:!f["name"].start_with?("._") or f["name"].eql?(".DS_Store")'
```

## Preview File types

Two types of preview can be generated:

  * png: thumbnail
  * mp4: video preview (only for video)

Use option `skip_format` to skip generation of a format.

## Supported input Files types

The preview generator supports redering of those file categories:

* image
* pdf
* plaintext
* office
* video

To avoid generation for some categories, specify a list using option `skip_types`.

Each category has a specific rendering method to produce the png thumbnail.

The mp4 video preview file is only for category `video`

File type is primarily based on file extension detected by the node API and translated info a mime type returned by the node API.

The tool can also locally detect the mime type using gem `mimemagic`.

## Access to original files and preview creation

Standard open source tools are used to create thumnails and video previews.
Those tools require that original files are accessible in the local file system and also write generated files on the local file system.
The tool provides 2 ways to read and write files with the option: `file_access`

If the preview generator is run on a system that has direct access to the file system, then the value `local` can be used. In this case, no transfer happen, source files are directly read from the storage, and preview files
are directly written to the storage.

If the preview generator does not have access to files on the file system (it is remote, no mount, or is an object storage), then the original file is first downloaded, then the result is uploaded, use method `remote`.


# SMTP for email notifications

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

## Example of configuration:

```
$ ascli config id smtp_google set server smtp.google.com
$ ascli config id smtp_google set username john@gmail.com
$ ascli config id smtp_google set password P@ssw0rd
```

or

```
$ ascli config id smtp_google init @json:'{"server":"smtp.google.com","username":"john@gmail.com","password":"P@ssw0rd"}'
```

or

```
$ ascli config id smtp_google update --server=smtp.google.com --username=john@gmail.com --password=P@ssw0rd
```

Set this configation as global default, for instance:

```
$ ascli config id cli_default set smtp @val:@preset:smtp_google
$ ascli config id default set config cli_default
```

## Email templates

Sent emails are built using a template that uses the [ERB](https://www.tutorialspoint.com/ruby/eruby.htm) syntax.

The template is the full SMTP message, including headers.

The following variables are defined by default:

* from_name
* from_email
* to

Other variables are defined depending on context.

## Test

Check settings with `smtp_settings` command. Send test email with `email_test`.

```
$ ascli config --smtp=@preset:smtp_google smtp
$ ascli config --smtp=@preset:smtp_google email --notif-to=sample.dest@example.com
```

## Notifications for transfer status

An e-mail notification can be sent upon transfer success and failure (one email per transfer job, one job being possibly multi session, and possibly after retry).

To activate, use option `notif_to`.

A default e-mail template is used, but it can be overriden with option `notif_template`.

The environment provided contains the following additional variables:

* subject
* body
* global_transfer_status
* ts

Example of template:

```
From: <%=from_name%> <<%=from_email%>>
To: <<%=to%>>
Subject: <%=subject%>

Transfer is: <%=global_transfer_status%>
```

# Tool: `asession`

This gem comes with a second executable tool providing a simplified standardized interface
to start a FASP session: `asession`.

It aims at simplifying the startup of a FASP session from a programmatic stand point as formating a [_transfer-spec_](#transferspec) is:

* common to Aspera Node API (HTTP POST /ops/transfer)
* common to Aspera Connect API (browser javascript startTransfer)
* easy to generate by using any third party language specific JSON library

Hopefully, IBM integrates this diectly in `ascp`, and this tool is made redundant.

This makes it easy to integrate with any language provided that one can spawn a sub process, write to its STDIN, read from STDOUT, generate and parse JSON.

The tool expect one single argument: a [_transfer-spec_](#transferspec).

If not argument is provided, it assumes a value of: `@json:@stdin:`, i.e. a JSON formated [_transfer-spec_](#transferspec) on stdin.

Note that if JSON is the format, one has to specify `@json:` to tell the tool to decode the hash using JSON.

During execution, it generates all low level events, one per line, in JSON format on stdout.

Note that there are special "extended" [_transfer-spec_](#transferspec) parameters supported by `asession`:

  * `EX_loglevel` to change log level of the tool
  * `EX_file_list_folder` to set the folder used to store (exclusively, because of garbage collection) generated file lists. By default it is `[system tmp folder]/[username]_asession_filelists`

Note that in addition, many "EX_" [_transfer-spec_](#transferspec) parameters are supported for the [`direct`](#direct) transfer agent (used by `asession`), refer to section [_transfer-spec_](#transferspec).

## Comparison of interfaces

<table>
<tr><th>feature/tool</th><th>asession</th><th>ascp</th><th>FaspManager</th><th>Transfer SDK</th></tr>
<tr><td>language integration</td><td>any</td><td>any</td><td>C/C++<br/>C#/.net<br/>Go<br/>Python<br/>java<br/></td><td>any</td></tr>
<tr><td>additional components to ascp</td><td>Ruby<br/>Aspera</td><td>-</td><td>library<br/>(headers)</td><td>daemon</td></tr>
<tr><td>startup</td><td>JSON on stdin<br/>(standard APIs:<br/>JSON.generate<br/>Process.spawn)</td><td>command line arguments</td><td>API</td><td>daemon</td></tr>
<tr><td>events</td><td>JSON on stdout</td><td>none by default<br/>or need to open management port<br/>and proprietary text syntax</td><td>callback</td><td>callback</td></tr>
<tr><td>platforms</td><td>any with ruby and ascp</td><td>any with ascp</td><td>any with ascp</td><td>any with ascp and transferdaemon</td></tr></table>

## Simple session

```
MY_TSPEC='{"remote_host":"demo.asperasoft.com","remote_user":"asperaweb","ssh_port":33001,"remote_password":"_demo_pass_","direction":"receive","destination_root":"./test.dir","paths":[{"source":"/aspera-test-dir-tiny/200KB.1"}],"resume_level":"none"}'

echo "${MY_TSPEC}"|asession
```

## Asynchronous commands and Persistent session

`asession` also supports asynchronous commands (on the management port). Instead of the traditional text protocol as described in ascp manual, the format for commands is: one single line per command, formatted in JSON, where parameters shall be "snake" style, for example: `LongParameter` -&gt; `long_parameter`

This is particularly useful for a persistent session ( with the [_transfer-spec_](#transferspec) parameter: `"keepalive":true` )

```
$ asession
{"remote_host":"demo.asperasoft.com","ssh_port":33001,"remote_user":"asperaweb","remote_password":"_demo_pass_","direction":"receive","destination_root":".","keepalive":true,"resume_level":"none"}
{"type":"START","source":"/aspera-test-dir-tiny/200KB.2"}
{"type":"DONE"}
```

(events from FASP are not shown in above example. They would appear after each command)

## Example of language wrapper

Nodejs: [https://www.npmjs.com/package/aspera](https://www.npmjs.com/package/aspera)

## Help

```
$ asession -h
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

# Hot folder

## Requirements

`ascli` maybe used as a simple hot folder engine. A hot folder being defined as a tool that:

* locally (or remotely) detects new files in a top folder
* send detected files to a remote (respectively, local) repository
* only sends new files, do not re-send already sent files
* optionally: sends only files that are not still "growing"
* optionally: after transfer of files, deletes or moves to an archive

In addition: the detection should be made "continuously" or on specific time/date.

## Setup procedure

The general idea is to rely on :

* existing `ascp` features for detection and transfer
* take advantage of `ascli` configuration capabilities and server side knowledge
* the OS scheduler for reliability and continuous operation

### ascp features

Interesting ascp features are found in its arguments: (see ascp manual):

* `ascp` already takes care of sending only "new" files: option `-k 1,2,3`, or transfer_spec: `resume_policy`
* `ascp` has some options to remove or move files after transfer: `--remove-after-transfer`, `--move-after-transfer`, `--remove-empty-directories`
* `ascp` has an option to send only files not modified since the last X seconds: `--exclude-newer-than` (--exclude-older-than)
* `--src-base` if top level folder name shall not be created on destination

Note that:

* `ascli` takes transfer parameters exclusively as a transfer_spec, with `--ts` parameter.
* most, but not all native ascp arguments are available as standard transfer_spec parameters
* native ascp arguments can be provided with the [_transfer-spec_](#transferspec) parameter: EX_ascp_args (array), only for the [`direct`](#direct) transfer agent (not connect or node)

### server side and configuration

Virtually any transfer on a "repository" on a regular basis might emulate a hot folder. Note that file detection is not based on events (inotify, etc...), but on a stateless scan on source side.

Note: parameters may be saved in a [option preset](#lprt) and used with `-P`.

### Scheduling

Once `ascli` parameters are defined, run the command using the OS native scheduler, e.g. every minutes, or 5 minutes, etc... Refer to section [_Scheduling_](#_scheduling_).

## Example

```
$ ascli server upload source_hot --to-folder=/Upload/target_hot --lock-port=12345 --ts=@json:'{"EX_ascp_args":["--remove-after-transfer","--remove-empty-directories","--exclude-newer-than=-8","--src-base","source_hot"]}'

```

The local folder (here, relative path: source_hot) is sent (upload) to basic fasp server, source files are deleted after transfer. growing files will be sent only once they dont grow anymore (based ona 8 second cooloff period). If a transfer takes more than the execution period, then the subsequent execution is skipped (lock-port).

# Aspera Health check and Nagios

Each plugin provide a `health` command that will check the health status of the application. Example:

```
$ ascli console health
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

```
$ ascli server health transfer --to-folder=/Upload --format=nagios --progress=none
OK - [transfer:ok]
$ ascli server health asctlstatus --cmd_prefix='sudo ' --format=nagios
OK - [NP:running, MySQL:running, Mongrels:running, Background:running, DS:running, DB:running, Email:running, Apache:running]
```

# Module: `Aspera`

Main components:

* `Aspera` generic classes for REST and OAuth
* `Aspera::Fasp`: starting and monitoring transfers. It can be considered as a FASPManager class for Ruby.
* `Aspera::Cli`: `ascli`.

A working example can be found in the gem, example:

```
$ ascli config gem_path
$ cat $(ascli config gem_path)/../examples/transfer.rb
```

This sample code shows some example of use of the API as well as
REST API.
Note: although nice, it's probably a good idea to use RestClient for REST.

Example of use of the API of Aspera on Cloud:

```
require 'aspera/aoc'

aoc=Aspera::AoC.new(url: 'https://sedemo.ibmaspera.com',auth: :jwt, scope: 'user:all', private_key: File.read(File.expand_path('~/.aspera/ascli/aspera_on_cloud_key')),username: 'laurent.martin.aspera@fr.ibm.com',subpath: 'api/v1')

aoc.read('self')
```

# History

When I joined Aspera, there was only one CLI: `ascp`, which is the implementation of the FASP protocol, but there was no CLI to access the various existing products (Server, Faspex, Shares). Once, Serban (founder) provided a shell script able to create a Faspex Package using Faspex REST API. Since all products relate to file transfers using FASP (ascp), I thought it would be interesting to have a unified CLI for transfers using FASP. Also, because there was already the `ascp` tool, I thought of an extended tool : `eascp.pl` which was accepting all `ascp` options for transfer but was also able to transfer to Faspex and Shares (destination was a kind of URI for the applications).

There were a few pitfalls:

* The tool was written in the aging `perl` language while most Aspera application products (but the Transfer Server) are written in `ruby`.
* The tool was only for transfers, but not able to call other products APIs

So, it evolved into `ascli`:

* portable: works on platforms supporting `ruby` (and `ascp`)
* easy to install with the `gem` utility
* supports transfers with multiple [Transfer Agents](#agents), that&apos;s why transfer parameters moved from ascp command line to [_transfer-spec_](#transferspec) (more reliable , more standard)
* `ruby` is consistent with other Aspera products

# Changes (Release notes)

* 4.4.0.pre

	* new: `aoc packages list` add possibility to add filter with option `query`
	* new: `aoc admin res xxx list` now get all items by default #50
	* new: `preset` option can specify name or hash value
	* new: `node` plugin accepts bearer token and access key as credential
	* new: `node` option `token_type` allows using basic token in addition to aspera type.
	* change: `server`: option `username` not mandatory anymore: xfer user is by default. If transfer spec token is provided, password or keys are optional, and bypass keys are used by default. 
	* change: (break) resource `apps_new` of `aoc` replaced with `application` (more clear)

* 4.3.0

	* new: parameter `multi_incr_udp` for option `transfer_info`: control if UDP port is incremented when multi-session is used on [`direct`](#direct) transfer agent.
	* new: command `aoc files node_info` to get node information for a given folder in the Files application of AoC. Allows cross-org or cross-workspace transfers.

* 4.2.2

	* new: `faspex package list` retrieves the whole list, not just first page
	* new: support web based auth to aoc and faspex 5 using HTTPS, new dependency on gem `webrick`
	* new: the error "Remote host is not who we expected" displays a special remediation message
	* new: `conf ascp spec` displays supported transfer spec
	* new: options `notif_to` and `notif_template` to send email notifications on transfer (and other events)
	* fix: space character in `faspe:` url are precent encoded if needed
	* fix: `preview scan`: if file_id is unknown, ignore and continue scan
	* change: for commands that potentially execute several transfers (`package recv --id=ALL`), if one transfer fails then `ascli` exits with code 1 (instead of zero=success)
	* change: (break) option `notify` or `aoc` replaced with `notif_to` and `notif_template`

* 4.2.1

	* new: command `faspex package recv` supports link of type: `faspe:`
	* new: command `faspex package recv` supports option `recipient` to specify dropbox with leading `*`

* 4.2.0

	* new: command `aoc remind` to receive organization membership by email
	* new: in `preview` option `value` to filter out on file name
	* new: `initdemo` to initialize for demo server
	* new: [`direct`](#direct) transfer agent options: `spawn_timeout_sec` and `spawn_delay_sec`
	* fix: on Windows `conf ascp use` expects ascp.exe
	* fix: (break) multi_session_threshold is Integer, not String
	* fix: `conf ascp install` renames sdk folder if it already exists (leftover shared lib may make fail)
	* fix: removed replace_illegal_chars from default aspera.conf causing "Error creating illegal char conversion table"
	* change: (break) `aoc apiinfo` is removed, use `aoc servers` to provide the list of cloud systems
	* change: (break) parameters for resume in `transfer-info` for [`direct`](#direct) are now in sub-key `"resume"`

* 4.1.0

	* fix: remove keys from transfer spec and command line when not needed 	* fix: default to create_dir:true so that sending single file to a folder does not rename file if folder does not exist
	* new: update documentation with regard to offline and docker installation
	* new: renamed command `nagios_check` to `health`
	* new: agent `http_gw` now supports upload
	* new: added option `sdk_url` to install SDK from local file for offline install
	* new: check new gem version periodically
	* new: the --fields= option, support -_fieldname_ to remove a field from default fields
	* new: Oauth tokens are discarded automatically after 30 minutes (useful for COS delegated refresh tokens)
	* new: mimemagic is now optional, needs manual install for `preview`, compatible with version 0.4.x
	* new: AoC a password can be provided for a public link
	* new: `conf doc` take an optional parameter to go to a section
	* new: initial support for Faspex 5 Beta 1

* 4.0.0

	* now available as open source at [https://github.com/IBM/aspera-cli](https://github.com/IBM/aspera-cli) with general cleanup
	* changed default tool name from `mlia` to `ascli`
	* changed `aspera` command to `aoc`
	* changed gem name from `asperalm` to `aspera-cli`
	* changed module name from `Asperalm` to `Aspera`
	* removed command `folder` in `preview`, merged to `scan`
	* persistency files go to sub folder instead of main folder
	* added possibility to install SDK: `config ascp install`

* 0.11.8

	* Simplified to use `unoconv` instead of bare `libreoffice` for office conversion, as `unoconv` does not require a X server (previously using Xvfb

* 0.11.7

	* rework on rest call error handling
	* use option `display` with value `data` to remove out of extraneous information
	* fixed option `lock_port` not working
	* generate special icon if preview failed
	* possibility to choose transfer progress bar type with option `progress`
	* AoC package creation now output package id

* 0.11.6

	* orchestrator : added more choice in auth type
	* preview: cleanup in generator (removed and renamed parameters)
	* preview: better documentation
	* preview: animated thumbnails for video (option: `video_png_conv=animated`)
	* preview: new event trigger: `trevents` (`events` seems broken)
	* preview: unique tmp folder to avoid clash of multiple instances
	* repo: added template for secrets used for testing

* 0.11.5

	* added option `default_ports` for AoC (see manual)
	* allow bulk delete in `aspera files` with option `bulk=yes`
	* fix getting connect versions
	* added section for Aix
	* support all ciphers for [`direct`](#direct) agent (including gcm, etc..)
	* added transfer spec param `apply_local_docroot` for [`direct`](#direct)

* 0.11.4

	* possibility to give shared inbox name when sending a package (else use id and type)

* 0.11.3

	* minor fixes on multi-session: avoid exception on progress bar

* 0.11.2

	* fixes on multi-session: progress bat and transfer spec param for "direct"

* 0.11.1

	* enhanced short_link creation commands (see examples)

* 0.11

	* add option to provide file list directly to ascp like this (only for direct transfer agent):

```
... --sources=@ts --ts=@json:'{"paths":[],"EX_file_list":"filelist"}'
```

* 0.10.18

	* new option in. `server` : `ssh_options`

* 0.10.17

	* fixed problem on `server` for option `ssh_keys`, now accepts both single value and list.
	* new modifier: `@list:<saparator>val1<separator>...`

* 0.10.16

	* added list of shared inboxes in workspace (or global), use `--query=@json:'{}'`

* 0.10.15

	* in case of command line error, display the error cause first, and non-parsed argument second
	* AoC : Activity / Analytics

* 0.10.14

	* added missing bss plugin

* 0.10.13

	* added Faspex5 (use option `value` to give API arguments)

* 0.10.12

	* added support for AoC node registration keys
	* replaced option : `local_resume` with `transfer_info` for agent [`direct`](#direct)
	* Transfer agent is no more a Singleton instance, but only one is used in CLI
	* `@incps` : new extended value modifier
	* ATS: no more provides access keys secrets: now user must provide it
	* begin work on "aoc" transfer agent

* 0.10.11

	* minor refactor and fixes

* 0.10.10

	* fix on documentation

* 0.10.9.1

	* add total number of items for AoC resource list
	* better gem version dependency (and fixes to support Ruby 2.0.0)
	* removed aoc search_nodes

* 0.10.8

	* removed option: `fasp_proxy`, use pseudo transfer spec parameter: `EX_fasp_proxy_url`
	* removed option: `http_proxy`, use pseudo transfer spec parameter: `EX_http_proxy_url`
	* several other changes..

* 0.10.7

	* fix: ascli fails when username cannot be computed on Linux.

* 0.10.6

	* FaspManager: transfer spec `authentication` no more needed for local tranfer to use Aspera public keys. public keys will be used if there is a token and no key or password is provided.
	* gem version requirements made more open

* 0.10.5

	* fix faspex package receive command not working

* 0.10.4

 	* new options for AoC : `secrets`
 	* ACLI-533 temp file list folder to use file lists is set by default, and used by asession

* 0.10.3

	* included user name in oauth bearer token cache for AoC when JWT is used.

* 0.10.2

	* updated `search_nodes` to be more generic, so it can search not only on access key, but also other queries.
	* added doc for "cargo" like actions
	* added doc for multi-session

* 0.10.1

	* AoC and node v4 "browse" works now on non-folder items: file, link
	* initial support for AoC automation (do not use yet)

* 0.10

	* support for transfer using IBM Cloud Object Storage
	* improved `find` action using arbitrary expressions

* 0.9.36

	* added option to specify file pair lists

* 0.9.35

	* updated plugin `preview` , changed parameter names, added documentation
	* fix in `ats` plugin : instance id needed in request header

* 0.9.34

	* parser "@preset" can be used again in option "transfer_info"
	* some documentation re-organizing

* 0.9.33

	* new command to display basic token of node
	* new command to display bearer token of node in AoC
	* the --fields= option, support +_fieldname_ to add a field to default fields
	* many small changes

* 0.9.32

	* all Faspex public links are now supported
	* removed faspex operation recv_publink
	* replaced with option `link` (consistent with AoC)

* 0.9.31

	* added more support for public link: receive and send package, to user or dropbox and files view.
	* delete expired file lists
	* changed text table gem from text-table to terminal-table because it supports multiline values

* 0.9.27

	* basic email support with SMTP
	* basic proxy auto config support

* 0.9.26

	* table display with --fields=ALL now includes all column names from all lines, not only first one
	* unprocessed argument shows error even if there is an error beforehand

* 0.9.25

	* the option `value` of command `find`, to filter on name, is not optional
	* `find` now also reports all types (file, folder, link)
	* `find` now is able to report all fields (type, size, etc...)

* 0.9.24

	* fix bug where AoC node to node transfer did not work
	* fix bug on error if ED25519 private key is defined in .ssh

* 0.9.23

	* defined REST error handlers, more error conditions detected
	* commands to select specific ascp location

* 0.9.21

	* supports simplified wizard using global client
	* only ascp binary is required, other SDK (keys) files are now generated

* 0.9.20

	* improved wizard (prepare for AoC global client id)
	* preview generator: addedoption : --skip-format=&lt;png,mp4&gt;
	* removed outdated pictures from this doc

* 0.9.19

	* added command aspera bearer --scope=xx

* 0.9.18

	* enhanced aspera admin events to support query

* 0.9.16

	* AoC transfers are now reported in activity app
	* new interface for Rest class authentication (keep backward compatibility)

* 0.9.15

	* new feature: "find" command in aspera files
	* sample code for transfer API

* 0.9.12

	* add nagios commands
	* support of ATS for IBM Cloud, removed old version based on aspera id

* 0.9.11

	* Breaking change: @stdin is now @stdin:
	* support of ATS for IBM Cloud, removed old version based on aspera id


* 0.9.10

	* Breaking change: parameter transfer-node becomes more generic: transfer-info
	* Display SaaS storage usage with command: aspera admin res node --id=nn info
	* cleaner way of specifying source file list for transfers
	* Breaking change: replaced download_mode option with http_download action

* 0.9.9

	* Breaking change: "aspera package send" parameter deprecated, use the --value option instead with "recipients" value. See example.
	* Now supports "cargo" for Aspera on Cloud (automatic package download)

* 0.9.8

	* Faspex: use option once_only set to yes to enable cargo like function. id=NEW deprecated.
	* AoC: share to share transfer with command "transfer"

* 0.9.7

	* homogeneous [_transfer-spec_](#transferspec) for `node` and [`direct`](#direct) transfer agents
	* preview persistency goes to unique file by default
	* catch mxf extension in preview as video
	* Faspex: possibility to download all paclages by specifying id=ALL
	* Faspex: to come: cargo-like function to download only new packages with id=NEW

* 0.9.6

	* Breaking change: `@param:`is now `@preset:` and is generic
	* AoC: added command to display current workspace information

* 0.9.5

	* new parameter: new_user_option used to choose between public_link and invite of external users.
	* fixed bug in wizard, and wizard uses now product detection

* 0.9.4

	* Breaking change: onCloud file list follow --source convention as well (plus specific case for download when first path is source folder, and other are source file names).
	* AoC Package send supports external users
	* new command to export AoC config to Aspera CLI config

* 0.9.3

	* REST error message show host and code
	* option for quiet display
	* modified transfer interface and allow token re-generation on error
	* async add admin command
	* async add db parameters
	* Breaking change: new option "sources" to specify files to transfer

* 0.9.2

	* Breaking change: changed AoC package creation to match API, see AoC section

* 0.9.1

	* Breaking change: changed faspex package creation to match API, see Faspex section

* 0.9

	* Renamed the CLI from aslmcli to `ascli`
	* Automatic rename and conversion of former config folder from aslmcli to `ascli`

* 0.7.6

	* add "sync" plugin

* 0.7

	* Breaking change: AoC package recv take option if for package instead of argument.
	* Breaking change: Rest class and Oauth class changed init parameters
	* AoC: receive package from public link
	* select by col value on output
	* added rename (AoC, node)

* 0.6.19

Breaking change:

	* ats server list provisioned &rarr; ats cluster list
	* ats server list clouds &rarr; ats cluster clouds
	* ats server list instance --cloud=x --region=y &rarr; ats cluster show --cloud=x --region=y
	* ats server id xxx &rarr; ats cluster show --id=xxx
	* ats subscriptions &rarr; ats credential subscriptions
	* ats api_key repository list &rarr; ats credential cache list
	* ats api_key list &rarr; ats credential list
	* ats access_key id xxx &rarr; ats access_key --id=xxx

* 0.6.18

	* some commands take now --id option instead of id command.

* 0.6.15

	* Breaking change: "files" application renamed to "aspera" (for "Aspera on Cloud"). "repository" renamed to "files". Default is automatically reset, e.g. in config files and change key "files" to "aspera" in [option preset](#lprt) "default".

# BUGS, FEATURES, CONTRIBUTION

For issues or feature requests use the Github repository and issues.

You can also contribute to this open source project.

One can also create one's own command nplugin.

## Only one value for any option

Some commands and sub commands may ask for the same option name.
Currently, since option definition is position independant (last one wins), it is not possible
to give an option to a command and the same option with different value to a sub command.

For instance, if an entity is identified by the option `id` but later on the command line another `id` option is required, the later will override the earlier one, and both entity will use the same id.
As a workaround use another option, if available, to identify the entity.

This happens typically for the `node` sub command, e.g. identify the node by name instead of id.


## ED255519 key not supported

ED25519 keys are deactivated since version 0.9.24 so this type of key will just be ignored.

Without this deactivation, if such key was present the following error was generated:

```
OpenSSH keys only supported if ED25519 is available
```

Which meant that you do not have ruby support for ED25519 SSH keys.
You may either install the suggested Gems, or remove your ed25519 key from your `.ssh` folder to solve the issue.

## Error "Remote host is not who we expected"

Cause: `ascp` >= 4.x checks fingerprint of highest server host key, including ECDSA. `ascp` < 4.0 (3.9.6 and earlier) support only to RSA level (and ignore ECDSA presented by server). `aspera.conf` supports a single fingerprint.

Workaround on client side: To ignore the certificate (SSH fingerprint) add option on client side (this option can also be added permanently to the config file):

```
--ts=@json:'{"sshfp":null}'
```

Workaround on server side: Either remove the fingerprint from `aspera.conf`, or keep only RSA host keys in `sshd_config`.

References: ES-1944 in release notes of 4.1 and to [HSTS admin manual section "Configuring Transfer Server Authentication With a Host-Key Fingerprint"](https://www.ibm.com/docs/en/ahts/4.2?topic=upgrades-configuring-ssh-server).

## Miscelaneous

* remove rest and oauth classes and use ruby standard gems:

	* oauth
	* https://github.com/rest-client/rest-client

* use Thor or any standard Ruby CLI manager

* provide metadata in packages

* deliveries to dropboxes

* Going through proxy: use env var http_proxy and https_proxy, no_proxy

* easier use with https://github.com/pmq20/ruby-packer
