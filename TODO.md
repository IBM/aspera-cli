# TODO

Ideas and TODO list.
Add improvement ideas here.

## Preview: deletion of orphaned preview files

Deletion of preview files for deleted source files is not yet implemented.

## Architecture: replace custom REST client with `rest-client` gem

Evaluate replacing the custom REST implementation with the standard
[`rest-client`](https://github.com/rest-client/rest-client) gem.

## Architecture: replace custom OAuth client with `oauth2` gem

Evaluate replacing the custom OAuth 2.0 implementation with the standard
[`oauth2`](https://github.com/oauth-xx/oauth2) gem.

## Architecture: explore Traveling Ruby for single-executable distribution

Explore [Traveling Ruby](https://github.com/phusion/traveling-ruby)
(or [truby Traveling Ruby](https://github.com/trubygems/traveling-ruby)) as an alternative
single-executable distribution method.

## OCRAN packaging

## Add `description:` to all `ArgumentSpec` declarations

The `description` field is user-facing (shown in `--help` output) and should be present on
every `ArgumentSpec`. Arguments that already carry a `schema:` key or whose name is
self-explanatory are lower priority, but all should have explicit descriptions eventually.

Example fix:

```ruby
# Before
{name: :async_id, type: :identifier, lookup: :async_lookup}

# After
{name: :async_id, description: 'Async operation identifier', type: :identifier, lookup: :async_lookup}
```
