# Asperalm - Laurent's Aspera Ruby library, including a CLI

Laurent/Aspera/2016

## Overview
This is a Ruby Gem that provides the following features:

* a command line tool: aslmcli


application that uses Aspera REST APIs, as well as uses FASP for transfers.

Purpose:
- show use of (REST) APIs: Node, Files, Shares, Faspex
- provide a command line for some tasks
- cross-platform

Ruby has been chosen as language as it is used in most Aspera products, and the interpret can be found for most platforms.

Example of tasks:
- send packages with Faspex or Files
- retrieve the last package received
- retrieve a package from a passcode based link in Faspex
- supports , limited set of commands

## Installation
A version is available on rubygems.org, so the simplest way is to install the gem is:

```bash
$ gem install asperalm
```

This install the "aslmcli" executable.

## Usage

```bash
$ aslmcli -h
```

## Configuration and parameters
All parameters can be provided on command line, but it is more convenient to place applications access data in the configuration file.

The file is organized by application types.

For each application type, there is a list of named configurations. The configuration named "default" is taken if no "-n" option is provided (short for --config-name).

Command line options needs to be provided at their right level, i.e. global parameters before first command, and option of first command after first command, etc...

Arguments that require a value can be specified on command line or config file with the following specific rules:

* direct value, e.g. --username=foouser
* or, similarly, with @val: --username=@val:foouser
* or with a value specified in a file: --key=@file:$HOME/.ssh/mykey
* or with a value specified in an env var: --password=@env:MYPASSVAR

A default configuration file can be created: $HOME/.aspera/aslmcli/config.yaml

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
    :url: https://console.asperademo.com/aspera/console/api
    :username: nyapiuset
    :password: "mypassword"
```

## Authentication to applications

### Faspex / Shares / Console / Node

Only Basic authentication is supported. A "username" and "password" are provided, either on command line (--username, --password) or in the configuration file.

### Files
Files supports the following authentication types:

* Basic : limited to only some users, will be deprecated, dont use
* OAuth (bearer token) with web authentication (requires a browser)
* OAuth (bearer token) with JSON Web Token (JWT, requires registration of public key)

Web authentication is supported with various means:
* either address is displayed on terminal and user needs to manually open a browser
* or the CLI starts the browser with the "open" command (Mac)
* or a web automation is used (watir, experimental, dont use) 

Upon successful authentication, auth token are saved (cache) in local files, and can be used subsequently.
Expired token can be refreshed.

## Contents
included files are:

<table>
<tr><td><code>lib/asperalm/browser_interaction.rb</code></td><td>for user web login, supports watir or terminal</td></tr>
<tr><td><code>lib/asperalm/cli/*.rb</code></td><td>The CLI itself.</td></tr>
<tr><td><code>lib/asperalm/colors.rb</code></td><td>VT100 colors</td></tr>
<tr><td><code>lib/asperalm/fasp_manager.rb</code></td><td>Ruby FaspManager lib</td></tr>
<tr><td><code>lib/asperalm/oauth.rb</code></td><td>sample oauth</td></tr>
<tr><td><code>lib/asperalm/rest.rb</code></td><td>REST and CRUD support</td></tr>
</table>

## BUGS
This is a sample code only, dont expect full capabilities.

## TODO
* remove rest and oauth and use ruby standard objects:

  * oauth
  * https://github.com/rest-client/rest-client

use tools from:
http://blog.excelwithcode.com/build-commandline-apps.html

follow:
https://quickleft.com/blog/engineering-lunch-series-step-by-step-guide-to-building-your-first-ruby-gem/

## Sample commands

```bash
aslmcli shares browse /
aslmcli shares upload ~/200KB.1 /projectx
aslmcli shares download /projectx/200KB.1 .
aslmcli faspex recv_publink https://myfaspex.myorg.com/aspera/faspex/external_deliveries/78780?passcode=a003aaf2f53e3123456b908525084db6bebc7031
aslmcli -nibm faspex list
aslmcli -nibm faspex recv 05b92393-02b7-4900-ab69-fd56721e896c
aslmcli -nibm faspex --note="my note" --title="my title" --recipient="laurent@asperasoft.com" send ~/200KB.1 
aslmcli console transfers list
aslmcli node browse /
aslmcli node upload ~/200KB.1 /tmp
aslmcli node download /tmp/200KB.1 .
aslmcli files browse /
aslmcli files upload ~/200KB.1 /
aslmcli files download /200KB.1 .
aslmcli files send ~/200KB.1
aslmcli files packages
aslmcli files recv VleoMSrlA
aslmcli files events
aslmcli files usage_reports
```

## Example: sending packages with Aspera Files
1- In order to use Aspera Files API and not have to log-in using the web interface,
one can register the tool using the Aspera Files GUI and JWT. see <a href="https://aspera.asperafiles.com/helpcenter/admin/organization/registering-an-api-client">here</a>.
The private/(public) key pair can be generated with either ssh-keygen or openssl tools:

```bash
$ ssh-keygen -t rsa -f ~/.ssh/my_files_key -N ''
```

## Contributing

Please contribute: add new functions that use the APIs!

