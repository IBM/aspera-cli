## Plugin: `console`: IBM Aspera Console

### Transfer filter

Listing transfers supports the API syntax.

Query parameters `from` and `to` select the period (at most 24 hours), by default the last 24 hours.
They also accept the syntax of [`@date:`](#dates), for example:

```shell
<%=cmd%> console transfer current list --query=@json:'{"from":"now-2h"}'
```

A date without time zone is in UTC, as for Console, e.g. `2013-02-28 12:00:00`.

In addition, it is possible to place a single `query` parameter in the request to filter the results: `filter`, following the syntax:

```text
(field operator value)and(field operator value)...
```

<%=include_commands_for_plugin(:console)%>

