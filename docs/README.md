# Notes on documentation generation

`/README.md` is generated after compilation of `docs/README.erb.md`.

`docs/README.erb.md` uses markdown format with embedded ruby macros (`erb`).

Those macros are basically functions defined in `doc_tools.rb`, for example:

* `<%=cmd%>` just the command line tool name
* `<%=tool%>` the tool name in pre-formatted to be included in text paragraphs
* `<%=opt_env%>` env var prefix

The font used is : IBM Plex, see <https://www.ibm.com/plex/>
