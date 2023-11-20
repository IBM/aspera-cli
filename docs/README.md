# Notes on documentation generation

`docs/README.erb.md` uses markdown format with embedded ruby macros (`erb`).

`/README.md` is generated after compilation of `docs/README.erb.md`.

docs/README.erb.md contains various macros, see `doc_tools.rb` :

* `<%=cmd%>` just the command line tool name
* `<%=tool%>` the tool name in pre-formatted to be included in text paragraphs
* `<%=evp%>` env var prefix
* `<%=opprst%>` option preset
* `<%=prst%>` link to preset section, name and link to preset
* `<%=prstt%>` preset in title

The font used is : IBM Plex, see <https://www.ibm.com/plex/>
