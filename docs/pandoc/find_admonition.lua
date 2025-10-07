-- Transform block quotes starting with [!TAG] (e.g. [!NOTE], [!WARNING]) into
-- styled <div> blocks with a class matching the tag and a title header inside.
-- Used to create admonition-style boxes in Pandoc output.
-- luacheck: globals pandoc
function BlockQuote(el)
    local first = el.content[1]
    if not (first and first.t == "Para") then return el end
    local inlines = first.content
    if not (inlines and #inlines > 0 and inlines[1].t == "Str") then return el end
    local s = inlines[1].text
    local tag = s:match("^%[!(%u+)%]%s*$")
    if not tag then return el end
    local title_text = tag:sub(1, 1):upper() .. tag:sub(2):lower()
    table.remove(inlines, 1)
    if #inlines > 0 and inlines[1].t == "SoftBreak" then table.remove(inlines, 1) end
    local final_content = { pandoc.Div(
        { pandoc.Para({ pandoc.Str(title_text) }) },
        { id = "", class = "title" }
    ) }
    for i, block in ipairs(el.content) do
        table.insert(final_content, block)
    end
    return pandoc.Div(
        final_content,
        { id = "", class = tag:lower() }
    )
end
