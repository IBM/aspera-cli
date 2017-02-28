# Asperalm - Laurent's aspera Ruby library, including a CLI

Laurent/Aspera/2016

## Overview
This is a sample ruby application that uses Aspera Web Applications APIs:
- it can send packages with Faspex or Files
- it can retrieve the last package received
- supports Files, Shares, Node, Faspex, limited set of commands

For Files: :send, :recv, :upload, :download, :events, :set_client_key, :faspexgw, :admin

The gem can also be used on other ruby applications, it provides easy access to Files API, and provides a FaspManager API in Ruby.

## Installation
The simplest way is to install the gem with:

```bash
$ gem install asperalm
```

Add the path (in .profile): 
```bash
$ export PATH="$PATH:$(cd $(dirname $(gem which asperalm/cli/main))/../../../bin&&pwd -P)"
```

## Usage

```bash
$ ascli -h
```

## Configuration
All parameters can be provided on command line, but it is more convenient to place applications access data in the configuration file.

The file is organized by application types.

For each application type, there is a list of named configurations. The configuration named "default" is taken if no "-n" option is provided.

Options needs to be provided at their right level, i.e. global parameters before first command, and option of first command after first command, etc...

values of arguments can be retrieve from files with format: @file: , or env var with: @env:, the prefix @val: is optional.

A default configuration file can be created: $HOME/.aspera/ascli/config.yaml

here is an example:

```yaml
---
:loglevel: :warn
:files:
  default:
    :auth: :jwt
    :url: https://mycompany.asperafiles.com
    :client_id: <insert client id here>
    :client_secret: <insert client secret here>
    :private_key: "@file:~/.aspera/ascli/filesapikey"
    :subject: laurent@asperasoft.com
  p:
    :auth: :web
    :url: https://aspera.asperafiles.com
    :client_id: <insert client id here>
    :client_secret: <insert client secret here>
    :redirect_uri: http://local.connectme.us:12345
:faspex:
  default:
    :url: https://10.25.0.3
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
```

## Authentication to applications

### Faspex / Shares / Console / Node

Only Basic auth is supported. provide --username and --password

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

follow:
https://quickleft.com/blog/engineering-lunch-series-step-by-step-guide-to-building-your-first-ruby-gem/

## Contributing

TODO

