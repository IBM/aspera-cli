# Notes on documentation generation

`docs//README.md` is generated after compilation of `docs/README.erb.md`.

`docs/README.erb.md` uses the Markdown format with embedded Ruby macros (`erb`).

Those macros are basically functions defined in `doc_tools.rb`, for example:

| ERB                   | Description    |
|-----------------------|------------------------------------------------------------------|
| `<%=cmd%>`            | just the command line tool name |
| `<%=tool%>`           | the tool name in pre-formatted to be included in text paragraphs |
| `<%=br%>`             | line break |
| `<%=opt_env <NAME>%>` | env var prefix |
| `<%=ph <NAME>%>`      | place holder with name of value |

The font used is : IBM Plex, see <https://www.ibm.com/plex/>
