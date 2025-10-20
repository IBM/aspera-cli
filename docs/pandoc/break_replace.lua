-- Replace raw HTML line breaks (<br/>) inside table cells with proper Pandoc
-- LineBreak elements, ensuring clean cross-format rendering of tables.
-- luacheck: globals pandoc

-- https://pandoc.org/lua-filters.html#pandoc.Table
function Table(tbl)
    for _, body in ipairs(tbl.bodies) do
    for _, row in ipairs(body.body) do
        for _, cell in ipairs(row.cells) do
                for _, block in ipairs(cell.content) do
                if block.t == "Plain" or block.t == "Para" then
                    for i, el in ipairs(block.content) do
                        if el.t == "RawInline" and el.format == "html" and el.text == "<br/>" then
                            block.content[i] = pandoc.LineBreak()
                        end
                    end
                end
            end
        end
    end
    end
    return tbl
end
