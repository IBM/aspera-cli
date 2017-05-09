# Asperalm - Laurent's Aspera Ruby library, including a CLI

Laurent/2016

This GEM is not endorsed/supported by IBM/Aspera

## Overview
This is a Ruby Gem that provides the following features:

* a command line tool: aslmcli
* a FASPManager class for Ruby
* REST and OAuth classes for use with Aspera products APIs

This Gem was developed for the following Purposes:

* show use of Aspera (REST) APIs: Node, Files, Shares, Faspex, Console
* provide a command line for some tasks
* cross-platform (ruby)

Ruby has been chosen as language as it is used in most Aspera products, and the 
interpret can be found for most platforms.

This gem is provided as-is, and is not intended to be a complete CLI, or 
industry-grade product. This is a sample. 
Aspera provides a CLI tool here: http://downloads.asperasoft.com/en/downloads/62 .

The CLI's folder where configuration and cache files are kept is `$HOME/.aspera/aslmcli`

Requires Ruby 2.0+

In examples below, command line operations are shown using Bash.

## Quick Start

### General setup
First, install the gem and its dependencies, this requires Ruby v2.0+, and 
initialize a configuration file:

```bash
$ gem install asperalm
```
The tool can be used right away: `aslmcli`

### Configuration file setup

The use of the configuration file is not mandatory, all parameters can be set on 
command line, 
but the configuration file provides a way to define default values, especially
for authentication parameters. A sample configuration file can be created with:

```bash
$ aslmcli config init
```

This creates a sample configuration file: `$HOME/.aspera/aslmcli/config.yaml`

For Faspex, Shares, Node (including ATS (Aspera Transfer Service)), Console, 
only username/password 
and url are required (either on command line, or from config file). Just fill-in url and
credentials in the configuration file (section: default), and then you can start 
using the CLI without having to specify those on command line. 
Switch between servers with `-n` option.

### Configuration for use with Aspera Files

Aspera Files APIs do not support Basic HTTP authentication (see section "Authentication").

To use the CLI with Aspera Files, a possibility is to do the following (jwt auth):

* Create a private/public key pair, as specified in section: "Private/Public Keys"

* Register a new application in the Aspera Files Admin GUI (refer to section "Authentication"). 
Here, as public key, use the contents of a file (generated in step 2):
 `$HOME/.aspera/aslmcli/filesapikey.pub`

* Edit the file: `$HOME/.aspera/aslmcli/config.yaml`, and set the values in section: 
files/default for items:
   * url : Your Aspera Files organization URL, e.g. `https://myorg.asperafiles.com`
   * client_id and client_secret : copy from the Application registration form (step 3)
   * username : your username in Aspera Files, e.g. `user@example.com`
   * private_key : location of private key file, leave as `@file:~/.aspera/aslmcli/filesapikey`

* CLI is ready to use:

```bash
$ aslmcli files repo browse /
:..............................:........:................:...........:......................:..............:
:             name             :  type  : recursive_size :   size    :    modified_time     : access_level :
:..............................:........:................:...........:......................:..............:
: Summer 2016 Training         : link   :                :           : 2016-07-25T15:21:22Z : edit         :
: Laurent Garage SE            : folder : 19316893       :           :                      : edit         :
: Italy Training               : folder : 312068540      :           :                      : edit         :
: Cheese pile.jpeg             : file   :                : 9824      : 2016-11-16T12:10:25Z : edit         :
: Aspera Video                 : folder : 122237276      :           :                      : edit         :
:..............................:........:................:...........:......................:..............:

```

## Usage

```bash
$ aslmcli -h
NAME
	aslmcli -- a command line tool for Aspera Applications

SYNOPSIS
	aslmcli COMMANDS [OPTIONS] [ARGS]

COMMANDS
	Supported commands: console, faspex, files, node, shares, config
	Note that commands can be written shortened.

DESCRIPTION
	Use Aspera application to perform operations on command line.
	OAuth 2.0 is used for authentication in Files, Several authentication methods are provided.
	Additional documentation here: https://rubygems.org/gems/asperalm

EXAMPLES
	aslmcli files repo browse /
	aslmcli faspex send ./myfile --log-level=debug
	aslmcli shares upload ~/myfile /myshare

SPECIAL OPTION VALUES
	if an option value begins with @env: or @file:, value is taken from env var or file
	dates format is 'DD-MM-YY HH:MM:SS', or 'now' or '-<num>h'

OPTIONS (global)
    -h, --help                       Show this message
    -l, --log-level=VALUE            Log level. Values=(debug,info,warn,error,fatal,unknown), current=warn
    -q, --logger=VALUE               log method. Values=(syslog,stdout), current=stdout
        --format=VALUE               output format. Values=(ruby,text_table,json,text), current=text_table
        --transfer=VALUE             type of transfer. Values=(ascp,connect,node), current=ascp
    -f, --config-file=STRING         read parameters from file in YAML format, current=/Users/laurent/.aspera/aslmcli/config.yaml
    -n, --config-name=STRING         name of configuration in config file
        --transfer-node=STRING       name of configuration used to transfer when using --transfer=node
        --fields=STRING              comma separated list of fields, or ALL, or DEF
        --fasp-proxy=STRING          URL of FASP proxy (dnat / dnats)
        --http-proxy=STRING          URL of HTTP proxy (for http fallback)
    -r, --rest-debug                 more debug for HTTP calls
    -k, --insecure                   do not validate cert
        --ts=JSON                    override transfer spec values, current=
```

## Configuration and parameters
All CLI parameters can be provided on command line, but it is more convenient 
to set common parameters (e.g. cedentials) in a configuration file.

The configuration file is a YAML file organized by applications.

For each application type, there is a list of named configurations. The 
configuration named "default" is taken if no "-n" option is provided 
(short for --config-name).

Arguments that require a value can be specified on command line or config file 
with the following specific rules:

* direct value, e.g. --username=foouser
* or, similarly, with @val: --username=@val:foouser
* or a value read from a file: --key=@file:$HOME/.ssh/mykey
* or a value read from a named env var: --password=@env:MYPASSVAR

The default configuration file is: $HOME/.aspera/aslmcli/config.yaml

Here is an example:

```yaml
---
:global:
  default:
    :loglevel: :warn
:files:
  default:
    :auth: :jwt
    :url: https://mycompany.asperafiles.com
    :client_id: <insert client id here>
    :client_secret: <insert client secret here>
    :private_key: "@file:~/.aspera/aslmcli/filesapikey"
    :username: laurent@asperasoft.com
  p:
    :auth: :web
    :url: https://aspera.asperafiles.com
    :client_id: <insert client id here>
    :client_secret: <insert client secret here>
    :redirect_uri: http://local.connectme.us:12345
:faspex:
  default:
    :url: https://10.25.0.3/aspera/faspex
    :username: admin
    :password: MyPassword
:shares:
  default:
    :url: https://10.25.0.6
    :username: admin
    :password: MyPassword
:node:
  default:
    :url: https://10.25.0.8:9092
    :username: node_root
    :password: MyPassword
:console:
  default:
    :url: https://console.asperademo.com/aspera/console
    :username: nyapiuset
    :password: "mypassword"
:fasp:
  default:
    :transfer_spec: '{"remote_host":"demo.asperasoft.com","remote_user":"asperaweb","password":"xxxx"}'
```
The "default" configuration is taken, but can be overridden on comand line.
Another configuration can be taken with option "-n".

## Learning Aspera Product APIs (REST)

This CLI uses REST APIs.
To display HTTP calls, use argument `-r` or `--rest-debug`, this is useful to display 
exact content or HTTP requests and responses.

In order to get traces of execution, use argument : `--log-level=debug`

## Authentication

### Aspera Faspex / Shares / Console / Node

Only Basic authentication is supported. A "username" and "password" are provided, 
either on command line (--username, --password) or in the configuration file.

### Aspera Files

Aspera Files supports a more powerful and secure authentication mechanism: Oauth. 
HTTP Basic authentication is not supported (deprecated).

With OAuth, the application (aslmcli) must be identified, and a valid Aspera Files 
user must be used to access Aspera Files. Then a "Bearer" token is used for 
HTTP authentication.

First the application (aslmcli) must be declared in the Files GUI 
(see https://aspera.asperafiles.com/helpcenter/admin/organization/registering-an-api-client ). By declaring the application, a "client\_id" and "client\_secret" are generated:

<img src="docs/Auth1.png" alt="Files-admin-organization-apiclient-clientdetails"/>

It is possible to use the Aspera Files API, but a web browser is required to generate the token. `aslmcli` will either display the URL to be entered in a local browser, or open a browser directly (various options are proposed).

It is also possible to enable browser-less authentication by using JWT, in this case a private/public key pair is required (see section: Generating a key pair), the public key is provided to Aspera Files:

<img src="docs/Auth2.png" alt="Files-admin-organization-apiclient-authoptions"/>

Upon successful authentication, auth token are saved (cache) in local files, and 
can be used subsequently. Expired token can be refreshed.

## Sample commands

```bash
aslmcli shares browse /
aslmcli shares upload ~/200KB.1 /projectx
aslmcli shares download /projectx/200KB.1 .
aslmcli faspex recv_publink https://myfaspex.myorg.com/aspera/faspex/external_deliveries/78780?passcode=a003aaf2f53e3123456b908525084db6bebc7031
aslmcli faspex package list
aslmcli faspex package recv 05b92393-02b7-4900-ab69-fd56721e896c
aslmcli faspex package send ~/200KB.1 --config-name=myfaspex --note="my note" --title="my title" --recipient="laurent@asperasoft.com"
aslmcli console transfers list
aslmcli node browse /
aslmcli node upload ~/200KB.1 /tmp
aslmcli node download /tmp/200KB.1 .
aslmcli files repo browse /
aslmcli files repo upload ~/200KB.1 /
aslmcli files repo download /200KB.1 .
aslmcli files package send ~/200KB.1
aslmcli files package list
aslmcli files package recv VleoMSrlA
aslmcli files admin events
aslmcli files admin usage_reports
...and more
```

## Private/Public Keys

In order to use JWT for Aspera Files API client authentication, 
a private/public key pair must be generated.

For example, generate a passphrase-less keypair with `ssh-keygen`:

```bash
$ ssh-keygen -t rsa -f ~/.aspera/aslmcli/filesapikey -N ''
```

One can also use the "openssl" utility:

```bash
$ APIKEY=~/.aspera/aslmcli/filesapikey
$ openssl genrsa -passout pass:dummypassword -out ${APIKEY}.protected 2048
$ openssl rsa -passin pass:dummypassword -in ${APIKEY}.protected -out ${APIKEY}
$ openssl rsa -pubout -in ${APIKEY} -out ${APIKEY}.pub
$ rm -f ${APIKEY}.protected
```

## FASP based transfer options

The CLI provides access to Aspera Applications functions through REST APIs, it also
allows FASP based transfers (upload and download).

Any FASP parameter can be set by changing parameters in the associated "transfer spec".
The CLI standadizes on the use of "transfer spec" and does not support directly ascp options.
It is nevertheless possible to add ascp options (for fasp manager only, but not node api or connect)
using the special transfer spec parameter: EX_ascp_args.

Three methods for starting transfers are currently supported:

### FASPManager API based

By default the CLI will use the Aspera Connect Client FASP part, in this case
it requires the installation of the Aspera Connect Client to be 
able to execute FASP based transfers. The CLI will try to automatically locate the 
Aspera Protocol (`ascp`). This is option: `--transfer=ascp`. Note that parameters
are always provided with a "transfer spec".

### Aspera Connect Client GUI

By specifying option: `--transfer=connect`, the CLI will start transfers in the Aspera
Connect Client.

### Aspera Node API

By specifying option: `--transfer=node`, the CLI will start transfers in an Aspera
Transfer Server using the Node API.

### Example of use

Access to a "Shares on Demand" (SHOD) server on AWS is provided by a partner. And we need to 
transfer files from this third party SHOD instance into our Azure BLOB storage.
Simply create an "Aspera Transfer Service" instance (https://ts.asperasoft.com), which
provides access to the node API.
Then create a configuration for the "SHOD" instance in the configuration file: in section 
"shares", a configuration named: awsshod.
Create another configuration for the Azure ATS instance: in section "node", named azureats.
Then execute the following command:
```bash
aslmcli download /share/sourcefile /destinationfolder --config-name=awsshod --transfer=node --transfer-node=azureats
```
This will get transfer information from the SHOD instance and tell the Azure ATS instance 
to download files.

### Multi session transfers

Multi-session is also available, simply add `--ts='{...}'` like
```bash
--ts='{"multi_session":10,"multi_session_threshold":1,"target_rate_kbps":500000,"checksum_type":"none","cookie":"custom:aslmcli:Laurent:My Transfer"}'
```
This is supported only with node based transfers.

## Contents
Included files are:

<table>
<tr><td><code>lib/asperalm/browser_interaction.rb</code></td><td>for user web login, supports watir or terminal</td></tr>
<tr><td><code>lib/asperalm/cli/*.rb</code></td><td>The CLI itself.</td></tr>
<tr><td><code>lib/asperalm/colors.rb</code></td><td>VT100 colors</td></tr>
<tr><td><code>lib/asperalm/fasp_manager.rb</code></td><td>Ruby FaspManager lib</td></tr>
<tr><td><code>lib/asperalm/oauth.rb</code></td><td>sample oauth</td></tr>
<tr><td><code>lib/asperalm/rest.rb</code></td><td>REST and CRUD support</td></tr>
</table>

## BUGS
This is a sample code only, dont expect full capabilities. This code is not
supported by IBM/Aspera.

## TODO
* remove rest and oauth and use ruby standard gems:

  * oauth
  * https://github.com/rest-client/rest-client

use tools from:
http://blog.excelwithcode.com/build-commandline-apps.html

## Contributing

Please contribute: add new functions that use the APIs!
You may contact the author.

