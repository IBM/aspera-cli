[comment1]: # (Do not edit this README.md, edit docs/README.erb.md, for details, read docs/README.md)
<%
 # check that required env vars exist, and files
%w{EXENAME GEMSPEC INCL_USAGE INCL_COMMANDS INCL_ASESSION INCL_TRSPEC}.each do |e|
  raise "missing env var #{e}" unless ENV.has_key?(e)
  raise "missing file #{ENV[e]}" unless File.exist?(ENV[e]) or !e.start_with?('INCL_') #_
end
cmd=ENV["EXENAME"] # just command name
tool='`'+cmd+'`'   # used in text with formatting of command
evp=cmd.upcase+'_' # prefix for env vars
opprst='option preset' # just the name for "option preset"
prst='['+opprst+'](#lprt)'
prsts='['+opprst+'s](#lprt)'
prstt=opprst.capitalize # in title
gemspec=Gem::Specification::load(ENV["GEMSPEC"]) or raise "error loading #{ENV["GEMSPEC"]}"
geminstadd=gemspec.version.to_s.match(/\.[^0-9]/)?' --pre':''
-%>
# <%=tool%> : a Command Line for IBM Aspera products

Version : <%= gemspec.version.to_s %>

_Laurent/2016-<%=Time.new.year%>_

This gem provides a command line interface to Aspera Applications.

Location (once released):
[<%= gemspec.metadata['rubygems_uri'] %>](<%= gemspec.metadata['rubygems_uri'] %>)

Disclaimers:

* This has not yet been officially released so things may change

That being said, <%=tool%> is very powerful and gets things done, it&apos;s also a great tool to learn Aspera APIs.

This manual addresses three parts:

* <%=tool%> : The command line tool
* `asession` : starting a FASP Session with JSON parameters
* `Aspera` : includes a Ruby "FASPManager"

In examples, command line operations (starting with `$`) are shown using a standard shell: `bash` or `zsh`.

Command line parameters in example beginning with `my_`, like `my_param_value` are user-provided value and not fixed value commands.

# Quick Start

This section guides you from installation, first use and advanced use.

First, follow the section: [Installation](#installation) (Ruby, Gem, FASP) to start using <%=tool%>.

Once the gem is installed, <%=tool%> shall be accessible:

```
$ <%=cmd%> --version
<%= gemspec.version.to_s %>
```

## First use

Once installation is completed, you can proceed to the first use with a demo server:

If you want to test with Aspera on Cloud, jump to section: [Wizard](#aocwizard)

If you want to test with Aspera demo transfer server, a default configuration is created on first use:

```
$ <%=cmd%> server browse /
:............:...........:......:........:...........................:.......................:
:   zmode    :   zuid    : zgid :  size  :           mtime           :         name          :
:............:...........:......:........:...........................:.......................:
: dr-xr-xr-x : asperaweb : fasp : 4096   : 2014-04-10 19:44:05 +0200 : aspera-test-dir-tiny  :
: drwxr-xr-x : asperaweb : fasp : 176128 : 2018-03-15 12:20:10 +0100 : Upload                :
: dr-xr-xr-x : asperaweb : fasp : 4096   : 2015-04-01 00:37:22 +0200 : aspera-test-dir-small :
: dr-xr-xr-x : asperaweb : fasp : 4096   : 2018-05-04 14:26:55 +0200 : aspera-test-dir-large :
:............:...........:......:........:...........................:.......................:
```

If you want to use <%=tool%> with another server, and in order to make further calls more convenient, it is advised to define a <%=prst%> for the server's authentication options. The following example will:

* create a <%=prst%>
* define it as default for "server" plugin
* list files in a folder
* download a file

```
$ <%=cmd%> config id myserver update --url=ssh://demo.asperasoft.com:33001 --username=asperaweb --password=demoaspera
updated: myserver
$ <%=cmd%> config id default set server myserver
updated: default&rarr;server to myserver
$ <%=cmd%> server browse /aspera-test-dir-large
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
$ <%=cmd%> server download /aspera-test-dir-large/200MB
Time: 00:00:02 ========================================================================================================== 100% 100 Mbps Time: 00:00:00
complete
```

## Going further

Get familiar with configuration, options, commands : [Command Line Interface](#cli).

Then, follow the section relative to the product you want to interact with ( Aspera on Cloud, Faspex, ...) : [Application Plugins](plugins)

# <a name="installation"></a>Installation

In order to use the tool or the gem, it is necessary to install those components:

* [Ruby](#ruby)
* [<%= gemspec.name %>](#the_gem)
* [FASP](#fasp_prot)

The following sections provide information on the installation.

## <a name="ruby"></a>Ruby

A ruby interpreter is required to run the tool or to use the gem and tool.
The Ruby version shall be <%= gemspec.required_ruby_version %>.
Any type of Ruby installation can be used.

Refer to the following sections for a proposed method for specific operating systems.

### macOS


MacOS 10.13+ (High Sierra) comes with a recent Ruby, so you can use it directly, you will need to install <%= gemspec.name %> using `sudo` :

```
$ sudo gem install <%= gemspec.name %><%=geminstadd%>
```

Alternatively, if you use [Homebrew](https://brew.sh/) already you can install Ruby with it:

```
$ brew install ruby
```

### Windows

Install Latest stable Ruby using [https://rubyinstaller.org/](https://rubyinstaller.org/).

Go to "Downloads".

Select the version "without devkit", x64 corresponding to the one recommended "with devkit".

During installation, skip the installation of "MSys2".

### Linux

Install Latest Ruby using "rvm" [https://rvm.io/](https://rvm.io/) .
It installs by default in /usr/local/rvm , but you can install in another location:

```
curl -sSL https://get.rvm.io | bash -s -- --path /usr/local
```

Once installed, you can install latest ruby:

```
# rvm install ruby
```

If you dont want all users to have ruby by default,
rename the file: `/etc/profile.d/rvm.sh` with another extension, and source it to get rvm.

Alternatively, only if you know what you do, on RPM based systems (CentOs, Redhat), install the ruby provided by yum which may be 2.0.

```
# yum install -y ruby rubygems ruby-json
```

If necessary, pre-install jwt for older Ruby < 2.1.

```
# gem install jwt -v 1.5.6
```

You can cleanup your whole yum-installed ruby environment like this to uninstall:

```
gem uninstall $(ls $(gem env gemdir)/gems/|sed -e 's/-[^-]*$//'|sort -u)
yum remove -y ruby ruby-libs
```

### Other Unixes: Aix, etc...

If your unix do not provide a pre-built ruby, you can get using one of those
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

## <a name="the_gem"></a>`<%= gemspec.name %>` gem

Once you have Ruby and rights to install gems: Install the gem and its dependencies:

```
# gem install <%= gemspec.name %><%=geminstadd%>
```

To upgrade to the latest version:

```
# gem update <%= gemspec.name %>
```

## <a name="fasp_prot"></a>FASP Protocol

Most file transfers will be done using the FASP protocol. Only two additional files are required to perform
an Aspera Transfer:

* ascp
* aspera-license (in same folder, or ../etc)

This can be installed directly with

```
$ <%=cmd%> conf ascp install
```

Those can be found in one of IBM Asprea transfer server or client with its license file (some are free):

* IBM Aspera Connect Client (Free)
* IBM Aspera Desktop Client (Free)
* IBM Aspera CLI (Free)
* IBM Aspera High Speed Transfer Server (Licensed)
* IBM Aspera High Speed Transfer EndPoint (Licensed)

For instance, Aspera Connect Client can be installed
by visiting the page: [http://downloads.asperasoft.com/connect2/](http://downloads.asperasoft.com/connect2/).

<%=tool%> will detect most of Aspera transfer products in standard locations and use the first one found.
Refer to section [FASP](#client) for details on how to select a client or set path to the FASP protocol.

Several methods are provided on how to start a transfer. Use of a local client is one of them, but
other methods are available. Refer to section: [Transfer Agents](#agents)

# <a name="cli"></a>Command Line Interface: <%=tool%>

The `<%= gemspec.name %>` Gem provides a command line interface (CLI) which interacts with Aspera Products (mostly using REST APIs):

* IBM Aspera High Speed Transfer Server (FASP and Node)
* IBM Aspera on Cloud (including ATS)
* IBM Aspera Faspex
* IBM Aspera Shares
* IBM Aspera Console
* IBM Aspera Orchestrator
* and more...

<%=tool%> provides the following features:

* Supports most Aspera server products (on-premise and SaaS)
* Any command line options (products URL, credentials or any option) can be provided on command line, in configuration file, in env var, in files
* Supports Commands, Option values and Parameters shortcuts
* FASP [Transfer Agents](#agents) can be: FaspManager (local ascp), or Connect Client, or any transfer node
* Transfer parameters can be altered by modification of _transfer-spec_, this includes requiring multi-session
* Allows transfers from products to products, essentially at node level (using the node transfer agent)
* Supports FaspStream creation (using Node API)
* Supports Watchfolder creation (using Node API)
* Additional command plugins can be written by the user
* Supports download of faspex and Aspera on Cloud "external" links
* Supports "legacy" ssh based FASP transfers and remote commands (ascmd)

Basic usage is displayed by executing:

```
$ <%=cmd%> -h
```

Refer to sections: [Usage](#usage) and [Sample Commands](#commands).

Not all <%=tool%> features are fully documented here, the user may explore commands on the command line.

## Arguments : Commands and options

Arguments are the units of command line, as parsed by the shell, typically separated by spaces (and called "argv").

There are two types of arguments: Commands and Options. Example :

```
$ <%=cmd%> command --option-name=VAL1 VAL2
```

* executes _command_: `command`
* with one _option_: `option_name`
* this option has a _value_ of: `VAL1`
* the command has one additional _argument_: `VAL2`

When the value of a command, option or argument is constrained by a fixed list of values, it is possible to use the first letters of the value only, provided that it uniquely identifies a value. For example `<%=cmd%> conf ov` is the same as `<%=cmd%> config overview`.

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
$ <%=cmd%> config echo -- --sample
"--sample"
```

Note that `--sample` is taken as an argument, and not option.

Options can be optional or mandatory, with or without (hardcoded) default value. Options can be placed anywhere on comand line and evaluated in order.

The value for _any_ options can come from the following locations (in this order, last value evaluated overrides previous value):

* [Configuration file](#configfile).
* Environment variable
* Command line

Environment variable starting with prefix: <%=evp%> are taken as option values,
e.g. `<%=evp%>OPTION_NAME` is for `--option-name`.

Options values can be displayed for a given command by providing the `--show-config` option: `<%=cmd%> node --show-config`

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

### Filtering columns for `object_list`

Table output can be filtered using the `select` parameter. Example:

```
$ <%=cmd%> oncloud admin res user list --fields=name,email,ats_admin --query=@json:'{"per_page":1000,"page":1,"sort":"name"}' --select=@json:'{"ats_admin":true}'
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

## <a name="extended"></a>Extended Value Syntax

Usually, values of options and arguments are specified by a simple string. But sometime it is convenient to read a value from a file, or decode it, or have a value more complex than a string (e.g. Hash table).

The extended value syntax is:

```
<0 or more decoders><0 or 1 reader><nothing or some text value>
```

The difference between reader and decoder is order and ordinality. Both act like a function of value on right hand side. Decoders are at the beginning of the value, followed by a single optional reader, followed by the optional value.

The following "readers" are supported:

* @val:VALUE , prevent further special prefix processing, e.g. `--username=@val:laurent` sets the option `username` to value `laurent`.
* @file:PATH , read value from a file (prefix "~/" is replaced with the users home folder), e.g. --key=@file:~/.ssh/mykey
* @path:PATH , performs path expansion (prefix "~/" is replaced with the users home folder), e.g. --config-file=@path:~/sample_config.yml
* @env:ENVVAR , read from a named env var, e.g.--password=@env:MYPASSVAR
* @stdin: , read from stdin (no value on right)
* @preset:NAME , get whole <%=opprst%> value by name

In addition it is possible to decode a value, using one or multiple decoders :

* @base64: decode a base64 encoded string
* @json: decode JSON values (convenient to provide complex structures)
* @zlib: uncompress data
* @ruby: execute ruby code
* @csvt: decode a titled CSV value
* @lines: split a string in multiple lines and return an array
* @list: split a string in multiple items taking first character as separator and return an array
* @incps: include values of presets specified by key include_presets in hash

To display the result of an extended value, use the `config echo` command.

Example: read the content of the specified file, then, base64 decode, then unzip:

```
$ <%=cmd%> config echo @zlib:@base64:@file:myfile.dat
```

Example: create a value as a hash, with one key and the value is read from a file:

```
$ <%=cmd%> config echo @ruby:'{"token_verification_key"=>File.read("pubkey.txt")}'
```

Example: read a csv file and create a list of hash for bulk provisioning:

```
$ cat test.csv
name,email
lolo,laurent@example.com
toto,titi@tutu.tata
$ <%=cmd%> config echo @csvt:@file:test.csv
:......:.....................:
: name :        email        :
:......:.....................:
: lolo : laurent@example.com :
: toto : titi@tutu.tata      :
:......:.....................:
```

Example: create a hash and include values from preset named "config" of config file

```
$ <%=cmd%> config echo @incps:@json:'{"hello":true,"incps":["config"]}'
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

<%=tool%> configuration and other runtime files (token cache, file lists, persistency files)
are stored in folder `$HOME/.aspera/<%=cmd%>`. The folder can be displayed using :

```
$ <%=cmd%> config folder
/Users/kenji/.aspera/<%=cmd%>
```

## <a name="configfile"></a>Configuration file

On the first execution of <%=tool%>, an empty configuration file is created in the configuration folder.
Nevertheless, there is no mandatory information required in this file, the use of it is optional as any option can be provided on the command line.

Although the file is a standard YAML file, <%=tool%> provides commands to read and modify it
using the `config` command.

All options for <%=tool%> commands can be set on command line, or by env vars, or using <%=prsts%> in the configuratin file.

A configuration file provides a way to define default values, especially
for authentication parameters, thus avoiding to always having to specify those parameters on the command line.

The default configuration file is: `$HOME/.aspera/<%=cmd%>/config.yaml`
(this can be overriden with option `--config-file=path` or equivalent env var).

So, finally, the configuration file is simply a catalog of pre-defined lists of options,
called: <%=prsts%>. Then, instead of specifying some common options on the command line (e.g. address, credentials), it is possible to invoke the ones of a <%=prst%> (e.g. `mypreset`) using the option: `-Pmypreset` or `--preset=mypreset`.

### <a name="lprt"></a><%=prstt%>

A <%=prst%> is simply a collection of parameters and their associated values in a named section in the configuration file.

A named <%=prst%> can be modified directly using <%=tool%>, which will update the configuration file :

```
$ <%=cmd%> config id <<%=opprst%>> set|delete|show|initialize|update
```

The command `update` allows the easy creation of <%=prst%> by simply providing the options in their command line format, e.g. :

```
$ <%=cmd%> config id demo_server update --url=ssh://demo.asperasoft.com:33001 --username=asperaweb --password=demoaspera --ts=@json:'{"precalculate_job_size":true}'
```

* This creates a <%=prst%> `demo_server` with all provided options.

The command `set` allows setting individual options in a <%=prst%>.

```
$ <%=cmd%> config id demo_server set password demoaspera
```

The command `initialize`, like `update` allows to set several parameters at once, but it deletes an existing configuration instead of updating it, and expects a _[Structured Value](#native)_.

```
$ <%=cmd%> config id demo_server initialize @json:'{"url":"ssh://demo.asperasoft.com:33001","username":"asperaweb","password":"demoaspera","ts":{"precalculate_job_size":true}}'
```

A good practice is to not manually edit the configuration file and use modification commands instead.
If necessary, the configuration file can be edited (or simply consulted) with:

```
$ <%=cmd%> config open
```

A full terminal based overview of the configuration can be displayed using:

```
$ <%=cmd%> config over
```

A list of <%=prst%> can be displayed using:

```
$ <%=cmd%> config list
```

### <a name="lprtconf"></a>Special <%=prstt%>: config

This preset name is reserved and contains a single key: `version`. This is the version of <%=tool%> which created the file.

### <a name="lprtdef"></a>Special <%=prstt%>: default

This preset name is reserved and contains an array of key-value , where the key is the name of a plugin, and the value is the name of another preset.

When a plugin is invoked, the preset associated with the name of the plugin is loaded, unless the option --no-default (or -N) is used.

Note that special plugin name: `config` can be associated with a preset that is loaded initially, typically used for default values.

Operations on this preset are done using regular `config` operations:

```
$ <%=cmd%> config id default set _plugin_name_ _defauklt_preset_for_plugin_
$ <%=cmd%> config id default get _plugin_name_
"_defauklt_preset_for_plugin_"
```

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
  password: demoaspera
```

We can see here:

* The configuration was created with CLI version 0.3.7
* the default <%=prst%> to load for plugin "server" is : `demo_server`
* the <%=prst%> `demo_server` defines some parameters: the URL and credentials
* the default <%=prst%> to load in any case is : `cli_default`

Two <%=prsts%> are reserved:

* `config` contains a single value: `version` showing the CLI
version used to create the configuration file. It is used to check compatibility.
* `default` is reserved to define the default <%=prst%> name used for known plugins.

The user may create as many <%=prsts%> as needed. For instance, a particular <%=prst%> can be created for a particular application instance and contain URL and credentials.

Values in the configuration also follow the [Extended Value Syntax](#extended).

Note: if the user wants to use the [Extended Value Syntax](#extended) inside the configuration file, using the `config id update` command, the user shall use the `@val:` prefix. Example:

```
$ <%=cmd%> config id my_aoc_org set private_key @val:@file:"$HOME/.aspera/<%=cmd%>/aocapikey"
```

This creates the <%=prst%>:

```
...
my_aoc_org:
  private_key: @file:"/Users/laurent/.aspera/<%=cmd%>/aocapikey"
...
```

So, the key file will be read only at execution time, but not be embedded in the configuration file.

Options are loaded using this algorithm:

* if option '--preset=xxxx' is specified (or -Pxxxx), this reads the <%=prst%> specified from the configuration file.
    * else if option --no-default (or -N) is specified, then dont load default
    * else it looks for the name of the default <%=prst%> in section "default" and loads it
* environment variables are evaluated
* command line options are evaluated

Parameters are evaluated in the order of command line.

To avoid loading the default <%=prst%> for a plugin, just specify a non existing configuration: `-Pnone`

On command line, words in parameter names are separated by a dash, in configuration file, separator
is an underscore. E.g. --xxx-yyy  on command line gives xxx_yyy in configuration file.

Note: before version 0.4.5, some keys could be ruby symbols, from 0.4.5 all keys are strings. To
convert olver versions, remove the leading ":" in front of keys.

The main plugin name is *config*, so it is possible to define a default <%=prst%> for
the main plugin with:

```
$ <%=cmd%> config id cli_default set interactive no
$ <%=cmd%> config id default set config cli_default
```

A <%=prst%> value can be removed with `unset`:

```
$ <%=cmd%> config id cli_default unset interactive
```


### Examples

For Faspex, Shares, Node (including ATS, Aspera Transfer Service), Console,
only username/password and url are required (either on command line, or from config file).
Those can usually be provided on the command line:

```
$ <%=cmd%> shares repo browse / --url=https://10.25.0.6 --username=john --password=4sp3ra
```

This can also be provisioned in a config file:

```
1$ <%=cmd%> config id shares06 set url https://10.25.0.6
2$ <%=cmd%> config id shares06 set username john
3$ <%=cmd%> config id shares06 set password 4sp3ra
4$ <%=cmd%> config id default set shares shares06
5$ <%=cmd%> config overview
6$ <%=cmd%> shares repo browse /
```

The three first commands build a <%=prst%>.
Note that this can also be done with one single command:

```
$ <%=cmd%> config id shares06 init @json:'{"url":"https://10.25.0.6","username":"john","password":"4sp3ra"}'
```

The fourth command defines this <%=prst%> as the default <%=prst%> for the
specified application ("shares"). The 5th command displays the content of configuration file in table format.
Alternative <%=prsts%> can be used with option "-P&lt;<%=prst%>&gt;"
(or --preset=&lt;<%=prst%>&gt;)

Eventually, the last command shows a call to the shares application using default parameters.


## Plugins

The CLI tool uses a plugin mechanism. The first level command (just after <%=tool%> on the command line) is the name of the concerned plugin which will execute the command. Each plugin usually represent commands sent to a specific application.
For instance, the plugin "faspex" allows operations on the application "Aspera Faspex".

### Create your own plugin
```
$ mkdir -p ~/.aspera/<%=cmd%>/plugins
$ cat<<EOF>~/.aspera/<%=cmd%>/plugins/test.rb
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

The gem is equipped with traces. By default logging level is "warn". To increase debug level, use parameter `log_level`, so either command line `--log-level=xx` or env var `<%=evp%>LOG_LEVEL`.

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
$ <%=cmd%> config proxy_check --fpac=file:///./proxy.pac http://www.example.com
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
$ <%=cmd%> config ascp show
/Users/laurent/Applications/Aspera Connect.app/Contents/Resources/ascp
```

### Selection of local `ascp`

To temporarily use an alternate ascp path use option `ascp_path` (`--ascp-path=`)

To permanently use another ascp:

```
$ <%=cmd%> config ascp use '/Users/laurent/Applications/Aspera CLI/bin/ascp'
saved to default global preset /Users/laurent/Applications/Aspera CLI/bin/ascp
```

This sets up a global default.

### List locally installed Aspera Transfer products

Locally installed Aspera products can be listed with:

```
$ <%=cmd%> config ascp products list
:.........................................:................................................:
:                  name                   :                    app_root                    :
:.........................................:................................................:
: Aspera Connect                          : /Users/laurent/Applications/Aspera Connect.app :
: IBM Aspera CLI                          : /Users/laurent/Applications/Aspera CLI         :
: IBM Aspera High-Speed Transfer Endpoint : /Library/Aspera                                :
: Aspera Drive                            : /Applications/Aspera Drive.app                 :
:.........................................:................................................:
```

### Selection of local client

If no ascp is selected, this is equivalent to using option: `--use-product=FIRST`.

Using the option use_product finds the ascp binary of the selected product.

To permanently use the ascp of a product:

```
$ <%=cmd%> config ascp products use 'Aspera Connect'
saved to default global preset /Users/laurent/Applications/Aspera Connect.app/Contents/Resources/ascp
```

### Installation of Connect Client on command line

```
$ <%=cmd%> config ascp connect list
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
$ <%=cmd%> config ascp connect id 'Aspera Connect for Mac Intel 10.6' links list
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
$ <%=cmd%> config ascp connect id 'Aspera Connect for Mac Intel 10.6' links id 'Mac Intel Installer' download --to-folder=.
downloaded: AsperaConnect-3.6.1.111259-mac-intel-10.6.dmg
```

## <a name="agents"></a>Transfer Agents

Some of the actions on Aspera Applications lead to file transfers (upload and download) using the FASP protocol (`ascp`).

When a transfer needs to be started, a [_transfer-spec_](#transferspec) has been internally prepared.
This [_transfer-spec_](#transferspec) will be executed by a transfer client, here called "Transfer Agent".

There are currently 3 agents:

* `direct` : a local execution of `ascp`
* `connect` : use of a local Connect Client
* `node` : use of an Aspera Transfer Node (potentially _remote_).
* `httpgw` : use of an Aspera HTTP Gateway

Note that all transfer operation are seen from the point of view of the agent.
For instance, a node agent making an "upload", or "package send" operation,
will effectively push files to the related server from the agent node.

<%=tool%> standadizes on the use of a [_transfer-spec_](#transferspec) instead of _raw_ ascp options to provide parameters for a transfer session, as a common method for those three Transfer Agents.


### <a name="direct"></a>Direct (local ascp using FASPManager API)

By default the CLI will use a local FASP protocol, equivalent to specifying `--transfer=direct`.
<%=tool%> will detect locally installed Aspera products.
Refer to section [FASP](#client).

To specify a FASP proxy (only supported with the `direct` agent), set the appropriate [_transfer-spec_](#transferspec) parameter:

* `EX_fasp_proxy_url`
* `EX_http_proxy_url` (proxy for legacy http fallback)
* `EX_ascp_args`

The `transfer-info` optionally provides the following auto resume parameters:

<table>
<tr><th>Name</th><th>Default</th><th>Feature</th><th>Description</th></tr>
<tr><td>iter_max</td>.    <td>7</td><td>Resume</td><td>Max number of retry on error</td></tr>
<tr><td>sleep_initial</td><td>2</td><td>Resume</td><td>First Sleep before retry</td></tr>
<tr><td>sleep_factor</td> <td>2</td><td>Resume</td><td>Multiplier of Sleep</td></tr>
<tr><td>sleep_max</td>.   <td>60</td><td>Resume</td><td>Maximum sleep</td></tr>
<tr><td>wss</td>          <td>false</td><td>Web Socket Session</td><td>Enable use of web socket session in case it is available</td></tr>
</table>

### IBM Aspera Connect Client GUI

By specifying option: `--transfer=connect`, <%=tool%> will start transfers
using the locally installed Aspera Connect Client.

### Aspera Node API : Node to node transfers

By specifying option: `--transfer=node`, the CLI will start transfers in an Aspera
Transfer Server using the Node API, either on a local or remote node.

If a default node has been configured
in the configuration file, then this node is used by default else the parameter
`--transfer-info` is required. The node specification shall be a hash table with
three keys: url, username and password, corresponding to the URL of the node API
and associated credentials (node user or access key).

The `--transfer-info` parameter can directly specify a pre-configured <%=prst%> :
`--transfer-info=@preset:<psetname>` or specified using the option syntax :
`--transfer-info=@json:'{"url":"https://...","username":"theuser","password":"thepass"}'`

### <a name="trinfoaoc"></a>Aspera on cloud

By specifying option: `--transfer=aoc`, WORK IN PROGRESS

### <a name="httpgw"></a>HTTP Gateway

If it possible to send using a HTTP gateway, in case FASP is not allowed.

Example:

```
$ <%=cmd%> faspex package recv --id=323 --transfer=httpgw --transfer-info=@json:'{"url":"https://eudemo.asperademo.com:9443/aspera/http-gwy/v1"}'
```

## <a name="transferspec"></a>Transfer Specification

Some commands lead to file transfer (upload/download), all parameters necessary for this transfer
is described in a _transfer-spec_ (Transfer Specification), such as:

* server address
* transfer user name
* credentials
* file list
* etc...

<%=tool%> builds a default _transfer-spec_ internally, so it is not necessary to provide additional parameters on the command line for this transfer.

If needed, it is possible to modify or add any of the supported _transfer-spec_ parameter using the `ts` option. The `ts` option accepts a [Structured Value](#native) containing one or several _transfer-spec_ parameters.

It is possible to specify ascp options when the `transfer` option is set to `direct` using the special [_transfer-spec_](#transferspec) parameter: `EX_ascp_args`. Example: `--ts=@json:'{"EX_ascp_args":["-l","100m"]}'`. This is espacially useful for ascp command line parameters not supported yet in the transfer spec.

The use of a _transfer-spec_ instead of `ascp` parameters has the advantage of:

* common to all [Transfer Agent](#agents)
* not dependent on command line limitations (special characters...)

A [_transfer-spec_](#transferspec) is a Hash table, so it is described on the command line with the [Extended Value Syntax](#extended).

## <a name="transferparams"></a>Transfer Parameters

All standard _transfer-spec_ parameters can be overloaded. To display parameters,
run in debug mode (--log-level=debug). [_transfer-spec_](#transferspec) can
also be saved/overridden in the config file.

<%= File.read(ENV['INCL_TRSPEC']).gsub(/.*<body>(.*)<\/body>.*/m,'\1') %>

### Destination folder for transfers

The destination folder is set by <%=tool%> by default to:

* `.` for downloads
* `/` for uploads

It is specified by the [_transfer-spec_](#transferspec) parameter `destination_root`.
As such, it can be modified with option: `--ts=@json:'{"destination_root":"<path>"}'`.
The option `to_folder` provides an equivalent and convenient way to change this parameter:
`--to-folder=<path>` .

### List of files for transfers

When uploading, downloading or sending files, the user must specify
the list of files to transfer. Most of the time, the list of files to transfer will be simply specified on the command line:

```
$ <%=cmd%> server upload ~/mysample.file secondfile
```

This is equivalent to:

```
$ <%=cmd%> server upload --sources=@args ~/mysample.file secondfile
```

More advanced options are provided to adapt to various cases. In fact, list of files to transfer are conveyed using the [_transfer-spec_](#transferspec) using the field: "paths" which is a list (array) of pairs of "source" (mandatory) and "destination" (optional).

Note that this is different from the "ascp" command line. The paradigm used by <%=tool%> is: all transfer parameters are kept in [_transfer-spec_](#transferspec) so that execution of a transfer is independent of the transfer agent. Note that other IBM Aspera interfaces use this: connect, node, transfer sdk.

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

* Although not recommended, because it applies *only* to the `local` transfer agent (i.e. bare ascp), it is possible to specify bare ascp arguments using the pseudo [_transfer-spec_](#transferspec) parameter `EX_ascp_args`. In that case, one must specify a dummy list in the [_transfer-spec_](#transferspec), which will be overriden by the bare ascp command line provided.

```
--sources=@ts --ts=@json:'{"paths":[{"source":"dummy"}],"EX_ascp_args":["--file-list","myfilelist"]}'
```

In case the file list is provided on the command line (i.e. using `--sources=@args` or `--sources=<Array>`, but not `--sources=@ts`), the list of files will be used either as a simple file list or a file pair list depending on the value of the option: `src_type`:

* `list` : (default) the path of destination is the same as source
* `pair` : in that case, the first element is the first source, the second element is the first destination, and so on.

Example:

```
$ <%=cmd%> server upload --src-type=pair ~/Documents/Samples/200KB.1 /Upload/sample1
```

Note the special case when the source files are located on "Aspera on Cloud", i.e. using access keys and the `file id` API:

* All files must be in the same source folder.
* If there is a single file : specify the full path
* For multiple files, specify the source folder as first item in the list followed by the list of file names.

Source files are located on "Aspera on cloud", when :

* the server is Aspera on Cloud, and making a download / recv
* the agent is Aspera on Cloud, and making an upload / send

### <a name="multisession"></a>Support of multi-session

Multi session, i.e. starting a transfer of a file set using multiple sessions is supported on "direct" and "node" agents, not yet on connect.

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

Multi-session spawn is done by <%=tool%>.


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



## <a name="scheduling"></a>Scheduling an exclusive execution

It is possible to ensure that a given command is only run once at a time with parameter: `--lock-port=nnnn`. This is especially usefull when scheduling a command on a regular basis, for instance involving transfers, and a transfer may last longer than the execution period.

This opens a local TCP server port, and fails if this port is already used, providing a local lock.

This option is used when the tools is executed automatically, for instance with "preview" generation.

Usually the OS native scheduler shall already provide some sort of such protection (windows scheduler has it natively, linux cron can leverage `flock`).

## <a name="commands"></a>Sample Commands

A non complete list of commands used in unit tests:

```
<%= File.read(ENV["INCL_COMMANDS"]) %>
...and more
```

## <a name="usage"></a>Usage

```
$ <%=cmd%> -h
<%= File.read(ENV["INCL_USAGE"]) %>

```

Note that actions and parameter values can be written in short form.

# <a name="plugins"></a>Plugins: Application URL and Authentication

<%=tool%> comes with several Aspera application plugins.

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

<%=tool%> provides a configuration wizard. Here is a sample invocation :

```
$ <%=cmd%> config wizard
option: url> https://myorg.ibmaspera.com
Detected: Aspera on Cloud
Preparing preset: aoc_myorg
Please provide path to your private RSA key, or empty to generate one:
option: pkeypath>
using existing key:
/Users/myself/.aspera/<%=cmd%>/aspera_on_cloud_key
Using global client_id.
option: username> john@example.com
Updating profile with new key
creating new config preset: aoc_myorg
Setting config preset as default for aspera
saving config file
Done.
You can test with:
$ <%=cmd%> oncloud user info show
```

Optionally, it is possible to create a new organization-specific "integration".
For this, specify the option: `--use-generic-client=no`.

This will guide you through the steps to create.

## <a name="aocwizard"></a>Configuration: using manual setup

If you used the wizard (recommended): skip this section.

### Configuration details

Several types of OAuth authentication are supported:

* JSON Web Token (JWT) : authentication is secured by a private key (recommended for CLI)
* Web based authentication : authentication is made by user using a browser
* URL Token : external users authentication with url tokens (public links)

The authentication method is controled by option `auth`.

For a _quick start_, follow the mandatory and sufficient section: [API Client Registration](#clientreg) (auth=web) as well as [<%=prst%> for Aspera on Cloud](#aocpreset).

For a more convenient, browser-less, experience follow the [JWT](#jwt) section (auth=jwt) in addition to Client Registration.

In Oauth, a "Bearer" token are generated to authenticate REST calls. Bearer tokens are valid for a period of time.<%=tool%> saves generated tokens in its configuration folder, tries to re-use them or regenerates them when they have expired.

### <a name="clientreg"></a>Optional: API Client Registration

If you use the built-in client_id and client_secret, skip this and do not set them in next section.

Else you can use a specific OAuth API client_id, the first step is to declare <%=tool%> in Aspera on Cloud using the admin interface.

(official documentation: <https://ibmaspera.com/help/admin/organization/registering_an_api_client> ).

Let's start by a registration with web based authentication (auth=web):

* Open a web browser, log to your instance: e.g. `https://myorg.ibmaspera.com/`
* Go to Apps&rarr;Admin&rarr;Organization&rarr;Integrations
* Click "Create New"
	* Client Name: <%=tool%>
	* Redirect URIs: `http://localhost:12345`
	* Origins: `localhost`
	* uncheck "Prompt users to allow client to access"
	* leave the JWT part for now
* Save

Note: for web based authentication, <%=tool%> listens on a local port (e.g. specified by the redirect_uri, in this example: 12345), and the browser will provide the OAuth code there. For `<%=tool%>, HTTP is required, and 12345 is the default port.

Once the client is registered, a "Client ID" and "Secret" are created, these values will be used in the next step.

### <a name="aocpreset"></a><%=prst%> for Aspera on Cloud

If you did not use the wizard, you can also manually create a <%=prst%> for <%=tool%> in its configuration file.

Lets create an <%=prst%> called: `my_aoc_org` using `ask` interactive input (client info from previous step):

```
$ <%=cmd%> config id my_aoc_org ask url client_id client_secret
option: url> https://myorg.ibmaspera.com/
option: client_id> BJLPObQiFw
option: client_secret> yFS1mu-crbKuQhGFtfhYuoRW...
updated: my_aoc_org
```

(This can also be done in one line using the command `config id my_aoc_org update --url=...`)

Define this <%=prst%> as default configuration for the `aspera` plugin:

```
$ <%=cmd%> config id default set aspera my_aoc_org
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
$ <%=cmd%> config genkey ~/.aspera/<%=cmd%>/aocapikey
```

* `ssh-keygen`:

```
$ ssh-keygen -t rsa -f ~/.aspera/<%=cmd%>/aocapikey -N ''
```

* `openssl`

(on some openssl implementation (mac) there is option: -nodes (no DES))

```
$ APIKEY=~/.aspera/<%=cmd%>/aocapikey
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
$ <%=cmd%> oncloud admin res client list
:............:.........:
:     id     :  name   :
:............:.........:
: BJLPObQiFw : <%=cmd%> :
:............:.........:
$ <%=cmd%> oncloud admin res client --id=BJLPObQiFw modify @json:'{"jwt_grant_enabled":true,"explicit_authorization_required":false}'
modified
```

### User key registration

The public key must be assigned to your user. This can be done in two manners:

* Graphically

open the previously generated public key located here: `$HOME/.aspera/<%=cmd%>/aocapikey.pub`

	* Open a web browser, log to your instance: https://myorg.ibmaspera.com/
	* Click on the user's icon (top right)
	* Select "Account Settings"
	* Paste the _Public Key_ in the "Public Key" section
	* Click on "Submit"

* Using command line

```
$ <%=cmd%> oncloud admin res user list
:........:................:
:   id   :      name      :
:........:................:
: 109952 : Tech Support   :
: 109951 : LAURENT MARTIN :
:........:................:
$ <%=cmd%> oncloud user info modify @ruby:'{"public_key"=>File.read(File.expand_path("~/.aspera/<%=cmd%>/aocapikey.pub"))}'
modified
```

Note: the `aspera user info show` command can be used to verify modifications.

### <%=prst%> modification for JWT

To activate default use of JWT authentication for <%=tool%> using the <%=prst%>, do the folowing:

* change auth method to JWT
* provide location of private key
* provide username to login as (OAuthg "subject")

Execute:

```
$ <%=cmd%> config id my_aoc_org update --auth=jwt --private-key=@val:@file:~/.aspera/<%=cmd%>/aocapikey --username=laurent.martin.aspera@fr.ibm.com
```

Note: the private key argument represents the actual PEM string. In order to read the content from a file, use the @file: prefix. But if the @file: argument is used as is, it will read the file and set in the config file. So to keep the "@file" tag in the configuration file, the @val: prefix is added.

After this last step, commands do not require web login anymore.


### <a name="aocfirst"></a>First Use

Once client has been registered and <%=prst%> created: <%=tool%> can be used:

```
$ <%=cmd%> oncloud files br /
Current Workspace: Default Workspace (default)
empty
```


### Administration

The `admin` command allows several administrative tasks (and require admin privilege).

It allows actions (create, update, delete) on "resources": users, group, nodes, workspace, etc... with the `admin resource` command.

Bulk operations are possible using option `bulk` (yes,no(default)): currently: create only. In that case, the operation expects an Array of Hash instead of a simple Hash using the [Extended Value Syntax](#extended).

To get more resources when doing request add:

```
--query=@json:'{"per_page":10000}'
```

other query parameters can be used:
```
--query=@json:'{"member_of_any_workspace":true}'
--query=@json:'{"q":"laurent"}'
```

Refer to the AoC API for full list of query parameters.

#### Access Key secrets

In order to access some administrative actions on "nodes" (in fact, access keys), the associated
secret is required, it is usually provided using the `secret` option. For example in a command like:

```
$ <%=cmd%> oncloud admin res node --id="access_key1" --secret="secret1" v3 info
```

It is also possible to provide a set of secrets used on a regular basis. This can be done using the `secrets` option. The value provided shall be a Hash, where keys are access key ids, and values are the associated secrets.

First choose a repository name, for example `my_secrets`, and populate it like this:

```
$ <%=cmd%> conf id my_secrets set 'access_key1' 'secret1'
$ <%=cmd%> conf id my_secrets set 'access_key2' 'secret2'
$ <%=cmd%> conf id default get config
"cli_default"
```

Here above, one already has set a `config` global preset to preset `cli_default` (refer to earlier in documentation), then the repository can be read by default like this (note the prefix `@val:` to avoid the evaluation of prefix `@preset:`):

```
$ <%=cmd%> conf id cli_default set secrets @val:@preset:my_secrets
```

A secret repository can always be selected at runtime using `--secrets=@preset:xxxx`, or `--secrets=@json:'{"accesskey1":"secret1"}'`

#### Examples

* Bulk creation

```
$ <%=cmd%> oncloud admin res user create --bulk=yes @json:'[{"email":"dummyuser1@example.com"},{"email":"dummyuser2@example.com"}]'
:.......:.........:
:  id   : status  :
:.......:.........:
: 98398 : created :
: 98399 : created :
:.......:.........:
```

* Find with filter and delete

```
$ <%=cmd%> oncloud admin res user list --query='@json:{"q":"dummyuser"}' --fields=id,email
:.......:........................:
:  id   :         email          :
:.......:........................:
: 98398 : dummyuser1@example.com :
: 98399 : dummyuser2@example.com :
:.......:........................:
$ thelist=$(echo $(<%=cmd%> oncloud admin res user list --query='@json:{"q":"dummyuser"}' --fields=id,email --field=id --format=csv)|tr ' ' ,)
$ echo $thelist
98398,98399
$ <%=cmd%> oncloud admin res user --bulk=yes --id=@json:[$thelist] delete
:.......:.........:
:  id   : status  :
:.......:.........:
: 98398 : deleted :
: 98399 : deleted :
:.......:.........:
```

* Display current user's workspaces

```
$ <%=cmd%> oncloud user workspaces
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
$ <%=cmd%> oncloud admin resource node --name=_node_name_ --secret=_secret_ v4 access_key create --value=@json:'{"storage":{"path":"/folder1"}}'
```

* Display transfer events (ops/transfer)

```
$ <%=cmd%> oncloud admin res node --secret=_secret_ v3 transfer list --value=@json:'[["q","*"],["count",5]]'
```

              # page=1&per_page=10&q=type:(file_upload+OR+file_delete+OR+file_download+OR+file_rename+OR+folder_create+OR+folder_delete+OR+folder_share+OR+folder_share_via_public_link)&sort=-date
              #events=@api_files.read('events',{'q'=>'type:(file_upload OR file_download)'})[:data]
              # can add filters: tag=aspera.files.package_id%3DLA8OU3p8w
              #'tag'=>'aspera.files.package_id%3DJvbl0w-5A'
              # filter= 'id', 'short_summary', or 'summary'
              # count=nnn
              # tag=x.y.z%3Dvalue
              # iteration_token=nnn
              # after_time=2016-05-01T23:53:09Z
              # active_only=true|false


* Display node events (events)

```
$ <%=cmd%> oncloud admin res node --secret=_secret_ v3 events
```

* display members of a workspace

```
$ <%=cmd%> oncloud admin res workspace_membership list --fields=member_type,manager,member.email --query=@json:'{"page":1,"per_page":50,"embed":"member","inherited":false,"workspace_id":11363,"sort":"name"}'
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

a- get id of first workspace

```
WS1='First Workspace'
WS1ID=$(<%=cmd%> oncloud admin res workspace list --query=@json:'{"q":"'"$WS1"'"}' --select=@json:'{"name":"'"$WS1"'"}' --fields=id --format=csv)
```

b- get id of second workspace

```
WS2='Second Workspace'
WS2ID=$(<%=cmd%> oncloud admin res workspace list --query=@json:'{"q":"'"$WS2"'"}' --select=@json:'{"name":"'"$WS2"'"}' --fields=id --format=csv)
```

c- extract membership information and change workspace id

```
$ <%=cmd%> oncloud admin res workspace_membership list --fields=manager,member_id,member_type,workspace_id --query=@json:'{"per_page":10000,"workspace_id":'"$WS1ID"'}' --format=jsonpp > ws1_members.json
```

d- convert to creation data for second workspace:

```
grep -Eve '(direct|effective_manager|_count|storage|"id")' ws1_members.json|sed '/workspace_id/ s/"'"$WS1ID"'"/"'"$WS2ID"'"/g' > ws2_members.json
```

or, using jq:

```
jq '[.[] | {member_type,member_id,workspace_id,manager,workspace_id:"'"$WS2ID"'"}]' ws1_members.json > ws2_members.json
```

e- add members to second workspace

```
$ <%=cmd%> oncloud admin res workspace_membership create --bulk=yes @json:@file:ws2_members.json
```

* get users who did not log since a date

```
$ <%=cmd%> oncloud admin res user list --fields=email --query=@json:'{"per_page":10000,"q":"last_login_at:<2018-05-28"}'
:...............................:
:             email             :
:...............................:
: John.curtis@acme.com          :
: Jean.Dupont@tropfort.com      :
:...............................:
```

* list "Limited" users

```
$ <%=cmd%> oncloud admin res user list --fields=email --query=@json:'{"per_page":10000}' --select=@json:'{"member_of_any_workspace":false}'
```

* Perform a multi Gbps transfer between two remote shared folders

In this example, a user has access to a workspace where two shared folders are located on differente sites, e.g. different cloud regions.

First, setup the environment (skip if already done)

```
$ <%=cmd%> conf wizard --url=https://sedemo.ibmaspera.com --username=laurent.martin.aspera@fr.ibm.com
Detected: Aspera on Cloud
Preparing preset: aoc_sedemo
Using existing key:
/Users/laurent/.aspera/<%=cmd%>/aspera_on_cloud_key
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
$ <%=cmd%> oncloud user info show
```

This creates the option preset "aoc_&lt;org name&gt;" to allow seamless command line access and sets it as default for aspera on cloud.

Then, create two shared folders located in two regions, in your files home, in a workspace.

Then, transfer between those:

```
$ <%=cmd%> -Paoc_show aspera files transfer --from-folder='IBM Cloud SJ' --to-folder='AWS Singapore' 100GB.file --ts=@json:'{"target_rate_kbps":"1000000","multi_session":10,"multi_session_threshold":1}'
```

* create registration key to register a node
```
$ <%=cmd%> oncloud admin res admin/client create @json:'{"data":{"name":"laurentnode","client_subject_scopes":["alee","aejd"],"client_subject_enabled":true}}' --fields=token --format=csv
jfqslfdjlfdjfhdjklqfhdkl
```

* delete all registration keys

```
$ <%=cmd%> oncloud admin res admin/client list --fields=id --format=csv|<%=cmd%> oncloud admin res admin/client delete --bulk=yes --id=@lines:@stdin:
+-----+---------+
| id  | status  |
+-----+---------+
| 99  | deleted |
| 100 | deleted |
| 101 | deleted |
| 102 | deleted |
+-----+---------+
```

## Shared folders

* list shared folders in node

```
$ <%=cmd%> oncloud admin res node --id=8669 shared_folders
```

* list shared folders in workspace

```
$ <%=cmd%> oncloud admin res workspace --id=10818 shared_folders
```

* list members of shared folder

```
$ <%=cmd%> oncloud admin res node --id=8669 v4 perm 82 show
```

## Send a Package

Send a package:

```
$ <%=cmd%> oncloud packages send --value=@json:'{"name":"my title","note":"my note","recipients":["laurent.martin.aspera@fr.ibm.com","other@example.com"]}' --sources=@args my_file.dat
```

Notes:

* the `value` parameter can contain any supported package creation parameter. Refer to the API, or display an existing package.
* to list recipients use fields: "recipients" and/or "bcc_recipients". <%=cmd%> will resolve the list of email addresses to expected user ids. If a recipient is not already registered and the workspace allows external users, then the package is sent to an external user, and
  * if the option `new_user_option` is `@json:{"package_contact":true}` (default), then a public link is sent and the external user does not need to create an account.
  * if the option `new_user_option` is `@json:{}`, then external users are invited to join the workspace

## <a name="aoccargo"></a>Receive only new packages

It is possible to automatically download new packages, like using Aspera Cargo:

```
$ <%=cmd%> oncloud packages recv --id=ALL --once-only=yes --lock-port=12345
```

* `--id=ALL` (case sensitive) will download all packages
* `--once-only=yes` keeps memory of any downloaded package in persistency files located in the configuration folder.
* `--lock-port=12345` ensures that only one instance is started at the same time, to avoid collisions

Typically, one would regularly execute this command on a regular basis, using the method oif your choice:

* Windows scheduler
* cron
* etc...

## Download Files

Download of files is straightforward with a specific syntax for the `aspera files download` action: Like other commands the source file list is provided as  a list with the `sources` option. Nevertheless, consider this:

* if only one source is provided, it is downloaded
* if multiple sources must be downloaded, then the first in list is the path of the source folder, and the remaining items are the file names in this folder (without path).

## Find Files

The command `aspera files find [--value=expression]` will recursively scan storage to find files matching the expression criteria. It works also on node resource using the v4 command. (see examples)

The expression can be of 3 formats:

* empty (default) : all files, equivalent to: `exec:true`
* not starting with `exec:` : the expression is a regular expression, using ruby regex syntax. equivalent to: `exec:f['name'].match(/expression/)`

For instance, to find files with a special extension, use `--value='\.myext$'`

* starting with `exec:` : the ruby code after the prefix is executed for each entry found. the entry variable name is `f`. the file is displayed if the result is true;

Examples of expressions: (think to prefix with `exec:` and put in single quotes using bash)

* find files more recent than 100 days

```
f["type"].eql?("file") and (DateTime.now-DateTime.parse(f["modified_time"]))<100
```

* expression to find files older than 1 year on a given node and store in file list

```
$ <%=cmd%> oncloud admin res node --name='my node name' --secret='my secret' v4 find / --fields=path --value='exec:f["type"].eql?("file") and (DateTime.now-DateTime.parse(f["modified_time"]))<100' --format=csv > my_file_list.txt
```

* delete the files, one by one

```
$ cat my_file_list.txt|while read path;do echo <%=cmd%> oncloud admin res node --name='my node name' --secret='my secret' v4 delete "$path" ;done
```

* delete the files in bulk

```
cat my_file_list.txt | <%=cmd%> oncloud admin res node --name='my node name' --secret='my secret' v3 delete @lines:@stdin:
```

## Activity

The activity app can be queried with:

```
$ <%=cmd%> oncloud admin analytics transfers
```

It can also support filters and send notification email with a template:

```
$ <%=cmd%> oncloud admin analytics transfers --once-only=yes --lock-port=123455 \
--query=@json:'{"status":"completed","direction":"receive"}' \
--notify=@json:'{"to":"<''%=transfer[:user_email.to_s]%>","subject":"<''%=transfer[:files_completed.to_s]%> files received","body":"Dear <''%=transfer[:user_email.to_s]%>\nWe received <''%=transfer[:files_completed.to_s]%> files for a total of <''%=transfer[:transferred_bytes.to_s]%> bytes, starting with file:\n<''%=transfer[:content.to_s]%>\n\nThank you."}'
```

* `once_only` keep track of last date it was called, so next call will get only new events
* `query` filter (on API call)
* `notify` send an email as specified by template, this could be places in a file with the `@file` modifier.

Note this must not be executed in less than 5 minutes because the analytics interface accepts only a period of time between 5 minutes and 6 months. here the period is [date of previous execution]..[now].

## Using specific transfer ports

By default transfer nodes are expected to use ports TCP/UDP 33001. The web UI enforces that. The option `default_ports` ([yes]/no) allows <%=cmd%> to retrieve the server ports from an API call (download_setup) which reads the information from `aspera.conf` on the server.


# Plugin: Aspera Transfer Service

ATS is usable either :

* from an AoC subscription : <%=cmd%> oncloud admin ats : use AoC authentication

* or from an IBM Cloud subscription : <%=cmd%> ats : use IBM Cloud API key authentication

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
$ <%=cmd%> config id my_ibm_ats update --ibm-api-key=my_secret_api_key_here_8f8d9fdakjhfsashjk678
$ <%=cmd%> config id default set ats my_ibm_ats
$ <%=cmd%> ats api_key instances
+--------------------------------------+
| instance                             |
+--------------------------------------+
| aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee |
+--------------------------------------+
$ <%=cmd%> config id my_ibm_ats update --instance=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
$ <%=cmd%> ats api_key create
+--------+----------------------------------------------+
| key    | value                                        |
+--------+----------------------------------------------+
| id     | ats_XXXXXXXXXXXXXXXXXXXXXXXX                 |
| secret | YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY |
+--------+----------------------------------------------+
$ <%=cmd%> config id my_ibm_ats update --ats-key=ats_XXXXXXXXXXXXXXXXXXXXXXXX --ats-secret=YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY
```

## Examples

Example: create access key on softlayer:

```
$ <%=cmd%> ats access_key create --cloud=softlayer --region=ams --params=@json:'{"storage":{"type":"softlayer_swift","container":"_container_name_","credentials":{"api_key":"value","username":"_name_:_usr_name_"},"path":"/"},"id":"_optional_id_","name":"_optional_name_"}'
```

Example: create access key on AWS:

```
$ <%=cmd%> ats access_key create --cloud=aws --region=eu-west-1 --params=@json:'{"id":"testkey3","name":"laurent key AWS","storage":{"type":"aws_s3","bucket":"my-bucket","credentials":{"access_key_id":"AKIA_MY_API_KEY","secret_access_key":"my/secret/here"},"path":"/laurent"}}'

```

Example: create access key on Azure SAS:

```
$ <%=cmd%> ats access_key create --cloud=azure --region=eastus --params=@json:'{"id":"testkeyazure","name":"laurent key azure","storage":{"type":"azure_sas","credentials":{"shared_access_signature":"https://containername.blob.core.windows.net/blobname?sr=c&..."},"path":"/"}}'

```

(Note that the blob name is mandatory after server address and before parameters. and that parameter sr=c is mandatory.)

Example: create access key on Azure:

```
$ <%=cmd%> ats access_key create --cloud=azure --region=eastus --params=@json:'{"id":"testkeyazure","name":"laurent key azure","storage":{"type":"azure","credentials":{"account":"myaccount","key":"myaccesskey","storage_endpoint":"myblob"},"path":"/"}}'

```

delete all my access keys:

```
for k in $(<%=cmd%> ats access_key list --field=id --format=csv);do <%=cmd%> ats access_key id $k delete;done
```

# Plugin: IBM Aspera High Speed Transfer Server (transfer)

This plugin works at FASP level (SSH/ascp/ascmd) and does not use the node API.

## Authentication

Both password and SSH keys auth are supported.

Multiple SSH key paths can be provided. The value of the parameter `ssh_keys` can be a single value or an array. Each value is a path to a private key and is expanded ("~" is replaced with the user's home folder).

Examples:

```
$ <%=cmd%> server --ssh-keys=~/.ssh/id_rsa
$ <%=cmd%> server --ssh-keys=@list:,~/.ssh/id_rsa
$ <%=cmd%> server --ssh-keys=@json:'["~/.ssh/id_rsa"]'
```

The underlying ssh library `net::ssh` provides several options that may be used
depending on environment. By default the ssh library expect that an ssh-agent is running, but if you get the error message:

```
ERROR -- net.ssh.authentication.agent: could not connect to ssh-agent: Agent not configured
```

This means that you dont have such agent, check env var: `SSH_AGENT_SOCK`, check if the key is protected with a passphrase. [check the manual](https://net-ssh.github.io/ssh/v1/chapter-2.html#s2)

To diable use of `ssh-agent`, use the option `ssh_option` like this (or set in preset):

```
$ <%=cmd%> server --ssh-options=@ruby:'{use_agent: false}' ...
```

## Example

One can test the "server" application using the well known demo server:

```
$ <%=cmd%> config id aspera_demo_server update --url=ssh://demo.asperasoft.com:33001 --username=asperaweb --password=demoaspera
$ <%=cmd%> config id default set server aspera_demo_server
$ <%=cmd%> server browse /aspera-test-dir-large
$ <%=cmd%> server download /aspera-test-dir-large/200MB
```

This creates a <%=prst%> "aspera_demo_server" and set it as default for application "server"


# Plugin: IBM Aspera High Speed Transfer Server (node)

This plugin gives access to capabilities provided by HSTS node API.

## Simple Operations

It is possible to:
* browse
* transfer (upload / download)
* ...

## Central

The central subcommand uses the "reliable query" API (session and file). It allows listing transfer sessions and transfered files.

Filtering can be applied:
```
$ <%=cmd%> node central file list
```

by providing the `validator` option, offline transfer validation can be done.

## FASP Stream

It is possible to start a FASPStream session using the node API:

Use the "node stream create" command, then arguments are provided as a [_transfer-spec_](#transferspec).

```
$ <%=cmd%> node stream create --ts=@json:'{"direction":"send","source":"udp://233.3.3.4:3000?loopback=1&ttl=2","destination":"udp://233.3.3.3:3001/","remote_host":"localhost","remote_user":"stream","remote_password":"XXXX"}' --preset=stream
```

## Watchfolder

Refer to [Aspera documentation](https://download.asperasoft.com/download/docs/entsrv/3.7.4/es_admin_linux/webhelp/index.html#watchfolder_external/dita/json_conf.html) for watch folder creation.

<%=tool%> supports remote operations through the node API. Operations are:

* Start watchd and watchfolderd services running as a system user having access to files
* configure a watchfolder to define automated transfers


```
$ <%=cmd%> node service create @json:'{"id":"mywatchd","type":"WATCHD","run_as":{"user":"user1"}}'
$ <%=cmd%> node service create @json:'{"id":"mywatchfolderd","type":"WATCHFOLDERD","run_as":{"user":"user1"}}'
$ <%=cmd%> node watch_folder create @json:'{"id":"mywfolder","source_dir":"/watch1","target_dir":"/","transport":{"host":"10.25.0.4","user":"user1","pass":"mypassword"}}'
```

## Out of Transfer File Validation

Follow the Aspera Transfer Server configuration to activate this feature.

```
$ <%=cmd%> node central file list --validator=<%=cmd%> --data=@json:'{"file_transfer_filter":{"max_result":1}}'
:..............:..............:............:......................................:
: session_uuid :    file_id   :   status   :              path                    :
:..............:..............:............:......................................:
: 1a74444c-... : 084fb181-... : validating : /home/xfer.../PKG - my title/200KB.1 :
:..............:..............:............:......................................:
$ <%=cmd%> node central file update --validator=<%=cmd%> --data=@json:'{"files":[{"session_uuid": "1a74444c-...","file_id": "084fb181-...","status": "completed"}]}'
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
$ <%=cmd%> node download /share/sourcefile --to-folder=/destinationfolder --preset=awsshod --transfer=node --transfer-info=@preset:azureats
```

This will get transfer information from the SHOD instance and tell the Azure ATS instance
to download files.

## Create access key

```
$ <%=cmd%> node access_key create --value=@json:'{"id":"eudemo-sedemo","secret":"mystrongsecret","storage":{"type":"local","path":"/data/asperafiles"}}'
```

# Plugin: IBM Aspera Faspex

Note that the command "v4" requires the use of APIv4, refer to the Faspex Admin manual on how to activate.

## Sending a Package

Provide delivery info in JSON, example:

```
--delivery-info=@json:'{"title":"my title","recipients":["laurent.martin.aspera@fr.ibm.com"]}'
```

a note can be added: `"note":"Please ..."`

metadata: `"metadata":{"Meta1":"Val1","Meta2":"Val2"}`


Note for full details, refer to:
[Reference on Developer Site](https://developer.asperasoft.com/web/faspex/sending)

## operation on dropboxes

Example:

```
$ <%=cmd%> faspex v4 dropbox create --value=@json:'{"dropbox":{"e_wg_name":"test1","e_wg_desc":"test1"}}'
$ <%=cmd%> faspex v4 dropbox list
$ <%=cmd%> faspex v4 dropbox delete --id=36
```

## remote sources

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

It is possible to tell <%=tool%> to download newly received packages, much like the official
cargo client, or drive. Refer to the [same section](#aoccargo) in the Aspera on Cloud plugin:

```
$ <%=cmd%> faspex packages recv --id=ALL --once-only=yes --lock-port=12345
```

# Plugin: IBM Aspera Shares

Aspera Shares supports the "node API" for the file transfer part. (Shares 1 and 2)

In Shares2, users, groups listing are paged, to display sequential pages:

```
$ for p in 1 2 3;do <%=cmd%> shares2 admin users list --value=@json:'{"page":'$p'}';done
```

# Plugin: IBM Cloud Object Storage

The IBM Cloud Object Storage provides the possibility to execute transfers using FASP.

Required options are either:

* `bucket` bucket name
* `endpoint` storage endpoint url, e.g. https://s3.hkg02.cloud-object-storage.appdomain.cloud
* `apikey` API Key
* `crn` resource instance id

or:

* `bucket` bucket name
* `region` bucket region, e.g. eu-de
* `service_credentials` see below

Service credentials are directly created using the IBM cloud web ui. Navigate to:

Navigation Menu &rarr; Resource List &rarr; Storage &rarr; Cloud Object Storage &rarr; Service Credentials &rarr; &lt;select or create credentials&gt; &rarr; view credentials &rarr; copy

Then save the copied value to a file, e.g. : `$HOME/cos_service_creds.json`

or using the CLI:

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

Endpoints for regions can be found by querying the `endpoints` URL.

For convenience, let us create a default configuration, for example:

```
$ <%=cmd%> conf id mycos update --service-credentials=@val:@json:@file:$HOME/service_creds.json  --region=us-south --bucket=laurent
$ <%=cmd%> conf id default set cos mycos
```

Now, Ready to do operations, a subset of "node" plugin operations are supported, basically node API:

```
$ <%=cmd%> cos node browse /
$ <%=cmd%> cos node upload myfile.txt
```

# Plugin: IBM Aspera Sync

A basic plugin to start an "async" using <%=tool%>. The main advantage is the possibility
to start from ma configuration file, using <%=tool%> standard options.

# Plugin: Preview

The `preview` generates "previews" of graphical files, i.e. thumbnails (office, images, video) and video previews on an Aspera HSTS for use primarily in the Aspera on Cloud application.
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

If another folder is configured on the HSTS, then specify it to <%=tool%> using the option `previews_folder`.

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

Here shown on Redhat/CentOS.

Other OSes should work as well, but are note tested.

To check if all tools are found properly, execute:

```
$ <%=cmd%> preview check
```

### Image: Imagemagick and optipng

```
yum install -y ImageMagick optipng
```

### Video: FFmpeg

```
curl -s https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz|(mkdir -p /opt && cd /opt && tar xJvf - && rm -f /opt/ffmpeg /usr/bin/{ffmpeg,ffprobe} && ln -s ffmpeg-* ffmpeg && ln -s /opt/ffmpeg/{ffmpeg,ffprobe} /usr/bin)
```

### Office: Unoconv and Libreoffice

If you dont want to have preview for office dpcuments or if it is too complex you can skip office document preview generation by using option: `--skip-types=office`

The generation of preview in based on the use of `unoconv` and `libreoffice`

* Centos 8

```
# dnf install unoconv
```


## Configuration

Like any <%=tool%> commands, parameters can be passed on command line or using a configuration <%=prst%>. Note that if you use the <%=tool%> run as `xfer` user, like here, the configuration file must be created as the same user. Example using a <%=prst%> named `my_preset_name` (choose any name relevant to you, e.g. the AoC node name, and replace in the following lines):

```
# su -s /bin/bash - xfer
$ <%=cmd%> config id my_preset_name update --url=https://localhost:9092 --username=my_access_key --password=my_secret --skip-types=office --lock-port=12346
$ <%=cmd%> config id default set preview my_preset_name
```

Here we assume that Office file generation is disabled, else remove the option. For the `lock_port` option refer to a previous section in thsi manual.

Once can check if the access key is well configured using:

```
$ <%=cmd%> -Pmy_preset_name node browse /
```

This shall list the contents of the storage root of the access key.

## Execution

The tool intentionally supports only a "one shot" mode in order to avoid having a hanging process or using too many resources (calling REST api too quickly during the scan or event method).
It needs to be run regularly to create or update preview files. For that use your best
reliable scheduler. For instance use "CRON" on Linux or Task Scheduler on Windows.

Typically, for "Access key" access, the system/transfer is `xfer`. So, in order to be consiustent have generate the appropriate access rights, the generation process
should be run as user `xfer`.

Lets do a one shot test, using the configuration previously created:

```
# su -s /bin/bash - xfer
$ <%=cmd%> preview scan --overwrite=always
```

When the preview generator is first executed it will create a file: `.aspera_access_key`
which contains the access key used.
On subsequent run it reads this file and check that previews are generated for the same access key, else it fails. This is to prevent clash of different access keys using the same root.

## Configuration for Execution in scheduler

Here is an example of configuration for use with cron on Linux. Adapt the scripts to your own preference.

We assume here that a configuration preset was created as shown previously.

Here the cronjob is created for `root`, and changes the user to `xfer`, also overriding the shell which should be `aspshell`. (adapt the command below, as it would override existing crontab). It is also up to you to use directly the `xfer` user's crontab. This is an example only.

```
# crontab<<EOF
2-59 * * * * su -s /bin/bash - xfer -c 'nice +10 timeout 10m <%=cmd%> preview event --log-level=info --logger=syslog --iteration-file=/tmp/preview_restart.txt'
0 * * * *    su -s /bin/bash - xfer -c 'nice +10 timeout 30m <%=cmd%> preview scan  --log-level=info --logger=syslog'
EOF
```

Nopte that the options here may be located in the config preset, but it was left on the command line to keep stdout for command line execution of preview.

## Candidate detection for creation or update (or deletion)

The tool will find candidates for preview generation using three commands:

* `trevents` : only recently uploaded files will be tested (transfer events)
* `events` : only recently uploaded files will be tested (file events: not working)
* `scan` : deeply scan all files under the access key&apos;s "storage root"
* `folder` : same as `scan`, but only on the specified folder&apos;s "file identifier"
* `file` : for an individual file generation

Note that for the `event`, the option `iteration_file` should be specified so that
successive calls only process new events. This file will hold an identifier
telling from where to get new events.

It is also possible to test a local file, using the `test` command.

Once candidate are selected, once candidates are selected,
a preview is always generated if it does not exist already,
else if a preview already exist, it will be generated
using one of three overwrite method:

* `always` : preview is always generated, even if it already exists and is newer than original
* `never` : preview is generated only if it does not exist already
* `mtime` : preview is generated only if the original file is newer than the existing

Deletion of preview for deleted source files: not implemented yet.

If the `scan` or `events` detection method is used, then the option : `skip_folders` can be used to skip some folders. It expects a list of path relative to the storage root (docroot) starting with slash, use the `@json:` notation, example:

```
$ <%=cmd%> preview scan --skip-folders=@json:'["/not_here"]'
```

The option `folder_reset_cache` forces the node service to refresh folder contents using various methods.

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
<tr><td>server</td><td>-</td><td>smtp.gmail.com</td><td>SMTP server address</td></tr>
<tr><td>tls</td><td>true</td><td>false</td><td>use of TLS</td></tr>
<tr><td>port</td><td>587 for tls<br/>25 else</td><td>587</td><td>port for service</td></tr>
<tr><td>domain</td><td>domain of server</td><td>gmail.com</td><td>email domain of user</td></tr>
<tr><td>username</td><td>-</td><td>john@example.com</td><td>user to authenticate on SMTP server, leave empty for open auth.</td></tr>
<tr><td>password</td><td>-</td><td>MyP@ssword</td><td>password for above username</td></tr>
<tr><td>from\_email</td><td>username if defined</td><td>laurent.martin.l@gmail.com</td><td>address used if received replies</td></tr>
<tr><td>from\_name</td><td>same as email</td><td>John Wayne</td><td>display name of sender</td></tr>
</table>

## Example of configuration:

```
$ <%=cmd%> config id smtp_google set server smtp.google.com
$ <%=cmd%> config id smtp_google set username john@gmail.com
$ <%=cmd%> config id smtp_google set password P@ssw0rd
```

or

```
$ <%=cmd%> config id smtp_google init @json:'{"server":"smtp.google.com","username":"john@gmail.com","password":"P@ssw0rd"}'
```

or

```
$ <%=cmd%> config id smtp_google update --server=smtp.google.com --username=john@gmail.com --password=P@ssw0rd
```

Set this configation as global default, for instance:

```
$ <%=cmd%> config id cli_default set smtp @val:@preset:smtp_google
$ <%=cmd%> config id default set config cli_default
```

## Test

Check settings with `smtp_settings` command. Send test email with `email_test`.

```
$ <%=cmd%> config --smtp=@preset:smtp_google smtp
$ <%=cmd%> config --smtp=@preset:smtp_google email sample.dest@example.com
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

Note that in addition, many "EX_" [_transfer-spec_](#transferspec) parameters are supported for the "local" transfer agent (used by `asession`), refer to section [_transfer-spec_](#transferspec).

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
MY_TSPEC='{"remote_host":"demo.asperasoft.com","remote_user":"asperaweb","ssh_port":33001,"remote_password":"demoaspera","direction":"receive","destination_root":"./test.dir","paths":[{"source":"/aspera-test-dir-tiny/200KB.1"}],"resume_level":"none"}'

echo "${MY_TSPEC}"|asession
```

## Asynchronous commands and Persistent session

`asession` also supports asynchronous commands (on the management port). Instead of the traditional text protocol as described in ascp manual, the format for commands is: one single line per command, formatted in JSON, where parameters shall be "snake" style, for example: `LongParameter` -&gt; `long_parameter`

This is particularly useful for a persistent session ( with the [_transfer-spec_](#transferspec) parameter: `"keepalive":true` )

```
$ asession
{"remote_host":"demo.asperasoft.com","ssh_port":33001,"remote_user":"asperaweb","remote_password":"demoaspera","direction":"receive","destination_root":".","keepalive":true,"resume_level":"none"}
{"type":"START","source":"/aspera-test-dir-tiny/200KB.2"}
{"type":"DONE"}
```

(events from FASP are not shown in above example. They would appear after each command)

## Example of language wrapper

Nodejs: [https://www.npmjs.com/package/aspera](https://www.npmjs.com/package/aspera)

## Help

```
$ asession -h
<%= File.read(ENV["INCL_ASESSION"]) %>
```

# Hot folder

## Requirements

<%=tool%> maybe used as a simple hot folder engine. A hot folder being defined as a tool that:

* locally (or remotely) detects new files in a top folder
* send detected files to a remote (respectively, local) repository
* only sends new files, do not re-send already sent files
* optionally: sends only files that are not still "growing"
* optionally: after transfer of files, deletes or moves to an archive

In addition: the detection should be made "continuously" or on specific time/date.

## Setup procedure

The general idea is to rely on :

* existing `ascp` features for detection and transfer
* take advantage of <%=tool%> configuration capabilities and server side knowledge
* the OS scheduler for reliability and continuous operation

### ascp features

Interesting ascp features are found in its arguments: (see ascp manual):

* `ascp` already takes care of sending only "new" files: option `-k 1,2,3`, or transfer_spec: `resume_policy`
* `ascp` has some options to remove or move files after transfer: `--remove-after-transfer`, `--move-after-transfer`, `--remove-empty-directories`
* `ascp` has an option to send only files not modified since the last X seconds: `--exclude-newer-than` (--exclude-older-than)
* `--src-base` if top level folder name shall not be created on destination

Note that:

* <%=tool%> takes transfer parameters exclusively as a transfer_spec, with `--ts` parameter.
* not all native ascp arguments are available as standard transfer_spec parameters
* native ascp arguments can be provided with the [_transfer-spec_](#transferspec) parameter: EX_ascp_args (array), only for the "local" transfer agent (not connect or node)

### server side and configuration

Virtually any transfer on a "repository" on a regular basis might emulate a hot folder. Note that file detection is not based on events (inotify, etc...), but on a stateless scan on source side.

Note: parameters may be saved in a <%=prst%> and used with `-P`.

### Scheduling

Once <%=tool%> parameters are defined, run the command using the OS native scheduler, e.g. every minutes, or 5 minutes, etc... Refer to section [_Scheduling_](#_scheduling_).

## Example

```
$ <%=cmd%> server upload source_hot --to-folder=/Upload/target_hot --lock-port=12345 --ts=@json:'{"EX_ascp_args":["--remove-after-transfer","--remove-empty-directories","--exclude-newer-than=-8","--src-base","source_hot"]}'

```

The local (here, relative path: source_hot) is sent (upload) to basic fasp server, source files are deleted after transfer. growing files will be sent only once they dont grow anymore (based ona 8 second cooloff period). If a transfer takes more than the execution period, then the subsequent execution is skipped (lock-port).

# Module: `Aspera`

Main components:

* `Aspera` generic classes for REST and OAuth
* `Aspera::Fasp`: starting and monitoring transfers. It can be considered as a FASPManager class for Ruby.
* `Aspera::Cli`: <%=tool%>.

A working example can be found in the gem, example:

```
$ <%=cmd%> config gem_path
$ cat $(<%=cmd%> config gem_path)/../examples/transfer.rb
```

This sample code shows some example of use of the API as well as
REST API.
Note: although nice, it's probably a good idea to use RestClient for REST.

# History

When I joined Aspera, there was only one CLI: `ascp`, which is the implementation of the FASP protocol, but there was no CLI to access the various existing products (Server, Faspex, Shares). Once, Serban (founder) provided a shell script able to create a Faspex Package using Faspex REST API. Since all products relate to file transfers using FASP (ascp), I thought it would be interesting to have a unified CLI for transfers using FASP. Also, because there was already the `ascp` tool, I thought of an extended tool : `eascp.pl` which was accepting all `ascp` options for transfer but was also able to transfer to Faspex and Shares (destination was a kind of URI for the applications).

There were a few pitfalls:

* The tool was written in the aging `perl` language while most Aspera application products (but the Transfer Server) are written in `ruby`.
* The tool was only for transfers, but not able to call other products APIs

So, it evolved into <%=tool%>:

* portable: works on platforms supporting `ruby` (and `ascp`)
* easy to install with the `gem` utility
* supports transfers with multiple [Transfer Agents](#agents), that&apos;s why transfer parameters moved from ascp command line to [_transfer-spec_](#transferspec) (more reliable , more standard)
* `ruby` is consistent with other Aspera products



# Release Notes

* 4.0.0.pre1

	* now available as open source at [<%= gemspec.homepage %>](<%= gemspec.homepage %>) with general cleanup
	* changed default tool name from `mlia` to `ascli`
	* changed `aspera` command to `oncloud`
	* changed gem name from `asperalm` to `aspera-cli`
	* changed module name from `Asperalm` to `Aspera`
	* removed command `folder` in `preview`, merged to `scan`
	* persistency files go to sub folder instead of main folder

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
	* support all ciphers for `local`ascp (incl. gcm, etc..)
	* added transfer spec param `apply_local_docroot` for `local`

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
	* replaced option : `local_resume` with `transfer_info` for agent `direct`
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

	* fix: <%=cmd%> fails when username cannot be computed on Linux.

* 0.10.6

	* FaspManager: transfer spec `authentication` no more needed for local tranfer to use aspera public keys. public keys will be used if there is a token and no key or password is provided.
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

  * homogeneous [_transfer-spec_](#transferspec) for node and local
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

  * Renamed the CLI from aslmcli to <%=tool%>
  * Automatic rename and conversion of former config folder from aslmcli to <%=tool%>

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

  * Breaking change: "files" application renamed to "aspera" (for "Aspera on Cloud"). "repository" renamed to "files". Default is automatically reset, e.g. in config files and change key "files" to "aspera" in <%=prst%> "default".

# BUGS

* This is best effort code without official support, dont expect full capabilities. This code is not supported by IBM/Aspera. You can contact the author for bugs or features.

## only one value for any option

Some commands and sub commands may ask for the same option name.
Currently, since option definition is position independant (last one wins), it is not possible
to give an option to a command and the same option with different value to a sub command.

For instance, if an entity is identified by the option `id` but later on the command line another `id` option is required, the later will override the earlier one, and both entity will use the same id.
As a workaround use another option, if available, to identify the entity.

This happens typically for the `node` sub command, e.g. identify the node by name instead of id.


## ED255519 key not supported

ED255519 keys are deactivated since version 0.9.24 so this type of key will just be ignored.
Without this deactivation, if such key was present the following error was generated:

```
OpenSSH keys only supported if ED25519 is available
```

Which meant that you do not have ruby support for ED25519 SSH keys.
You may either install the suggested Gems, or remove your ed25519 key from your `.ssh` folder to solve the issue.

# TODO

* remove rest and oauth classes and use ruby standard gems:

  * oauth
  * https://github.com/rest-client/rest-client

* use Thor or any standard Ruby CLI manager

* provide metadata in packages

* deliveries to dropboxes

* Going through proxy: use env var http_proxy and https_proxy, no_proxy

* easier use with https://github.com/pmq20/ruby-packer

# Contribution

Send comments !

Create your own plugin !
