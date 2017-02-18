# Asperalm - Laurent's aspera Ruby library, including a CLI

Laurent/Aspera/2016

## Overview
This is a sample ruby application that uses Aspera Web Applications APIs:
- it can send packages with Faspex or Files
- it can retrieve the last package received
- supports Shares or Node

It's best to use Ruby version 2+

## Setup
* extract the zip file
* create a softlink "ascli" that points to as_cli.rb
* copy the file: ascli.yaml to $HOME/.ascli.yaml
* execute command ascli -h

gem install asperalm-0.1.0.gem
alias ascli=$(cd $(dirname $(gem which asperalm/cli/main))/../../../bin&&pwd -P)/ascli

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
    :url: https://aspera.asperafiles.com
    :client_id: ERuzXGuXY
    :client_secret: abKaOo1Q1_1tdCI54cZY7j00x03ZUmhW45R-ykWgeIIigs6HoGvet4GRN1jSLC0WkqNj_4vuybeH0V0zgYv17058ZNj6ueT8
    :private_key: "@file:~/.aspera/ascli/filesapikey"
    :subject: laurent@asperasoft.com
  p:
    :auth: :web
    :url: https://aspera.asperafiles.com
    :client_id: ERuzXGuPA
    :client_secret: edKaOo1Q1_1tdCI54cZY7j00x03ZUmhW45R-ykWgeIIigs6HoGvet4GRN1jSLC0WkqNj_4vuybeH0V0zgYv17058ZNj6ueT8
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

## Authentication

### Faspex / Shares

Only Basic auth is supported

### Files
Files supports the following authentication types:

* Basic : limited to only some users, not really supported
* OAuth based (bearer token)
 * with web authentication
 * with JSON Web Token (JWT)

Web authentication is supported with various means:

* either address is displayed on terminal and user needs to manually open a browser
* or the Mac command "open" is used
* or a wen automation is used (watir) 

Upon successful web authentication, auth token are saved (cache) in local files, and can be used subsequently. Expired token can be refreshed.

## Contents
included files are:

<table>
<tr><td><code>lib/asperalm/browser_interaction.rb</code></td><td>for user web login, supports watir or terminal</td></tr>
<tr><td><code>lib/asperalm/cli/*.rb</code></td><td>the actual use of Products APIs - most important files</td></tr>
<tr><td><code>lib/asperalm/colors.rb</code></td><td>VT100 colors</td></tr>
<tr><td><code>lib/asperalm/fasp_manager.rb</code></td><td>Ruby FaspManager lib</td></tr>
<tr><td><code>lib/asperalm/oauth.rb</code></td><td>sample oauth</td></tr>
<tr><td><code>lib/asperalm/rest.rb</code></td><td>REST and CRUD support</td></tr>
<tr><td><code>data/ascli.yaml</code></td><td>configuration profiles</td></tr>
<tr><td><code>src/as_cli.rb</code></td><td>main program, initializations, you can lower debug level here</td></tr>
</table>

## BUGS
This is a sample code only.

## TODO
* remove rest and oauth and use ruby standard objects:

  * oauth
  * https://github.com/rest-client/rest-client

follow:
https://quickleft.com/blog/engineering-lunch-series-step-by-step-guide-to-building-your-first-ruby-gem/

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'asperalm'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install asperalm

## Usage

TODO: Write usage instructions here

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Laurent Martin/asperalm.

