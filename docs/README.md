docs/README.erb.md uses markdown format with embeded ruby macros (erb)

/README.md is generated after compilation of README.erb.md

docs/README.erb.md contains the following macros:

* `<%=cmd%>` just the command line tool name
* `<%=tool%>` the tool name in courrier to be included in text paragraphs
* `<%=evp%>` env var prefix
* `<%=opprst%>` option preset
* `<%=prst%>` link to preset section, name and link to preset
* `<%=prstt%>` preset in title
