-- Replace raw HTML line breaks (<br/>) inside table cells with proper Pandoc
-- LineBreak elements, ensuring clean cross-format rendering of tables.
-- luacheck: globals pandoc

-- https://pandoc.org/lua-filters.html#pandoc.Table
function Table(tbl)
    -- Convert the table to and from a simple Pandoc table for easy traversal.
    tbl = pandoc.utils.to_simple_table(tbl)
    for _, row in ipairs(tbl.rows) do
        for _, cell in ipairs(row) do
            for _, block in ipairs(cell) do
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
    return pandoc.utils.from_simple_table(tbl)
end
