function Table(tbl)
    if not FORMAT:match("latex") then return tbl end

    local simpleTable = pandoc.utils.to_simple_table(tbl)
    local blocks = pandoc.Blocks {}

    -- Function to create a LaTeX row
    local function create_latex_row(cells)
        local latex_row = ""
        for i, cell in ipairs(cells) do
            for _, content in ipairs(cell) do
                latex_row = latex_row .. pandoc.write(pandoc.Pandoc({ content }), "latex")
            end
            if i < #cells then
                latex_row = latex_row .. " & "
            end
        end
        return latex_row .. " \\\\\n"
    end

    -- Determine number of columns
    local num_cols = 0
    if simpleTable.header and #simpleTable.header > 0 then
        num_cols = #simpleTable.header
    elseif #simpleTable.rows > 0 then
        num_cols = #simpleTable.rows[1]
    end

    -- Generate 'X' type columns for tabularx
    local col_spec = string.rep("l", num_cols - 1) .. "X"

    -- Begin tabularx environment
    blocks:insert(pandoc.RawBlock("latex", "\\begin{table}[htbp]"))
    if tbl.caption then
        local caption_text = pandoc.utils.stringify(tbl.caption)
        blocks:insert(pandoc.RawBlock("latex", "\\caption{" .. caption_text .. "}"))
    end
    if tbl.attr and tbl.attr.identifier and tbl.attr.identifier ~= "" then
        blocks:insert(pandoc.RawBlock("latex", "\\label{" .. tbl.attr.identifier .. "}"))
    end
    blocks:insert(pandoc.RawBlock("latex", "\\centering"))
    blocks:insert(pandoc.RawBlock("latex", "\\begin{tabularx}{\\textwidth}{" .. col_spec .. "}"))

    -- Process header row
    if simpleTable.header and #simpleTable.header > 0 then
        local header_row = create_latex_row(simpleTable.header)
        blocks:insert(pandoc.RawBlock("latex", header_row .. "\\hline"))
    end

    -- Process data rows
    for _, row in ipairs(simpleTable.rows) do
        local latex_row = create_latex_row(row)
        blocks:insert(pandoc.RawBlock("latex", latex_row))
    end

    -- End tabularx and table
    blocks:insert(pandoc.RawBlock("latex", "\\end{tabularx}"))
    blocks:insert(pandoc.RawBlock("latex", "\\end{table}"))

    return blocks
end
