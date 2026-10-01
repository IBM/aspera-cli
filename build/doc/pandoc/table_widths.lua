-- For LaTeX output, size the columns of wide tables from their content.
-- pandoc gives a pipe table wider than 72 characters relative column widths taken from the
-- dashes of its separator row. When all columns got the same width (separator not tuned,
-- e.g. `| --- | --- |`), widths are computed from the cells instead: each column gets at least
-- its longest word, the remaining width is shared in proportion to the length of its lines.
-- Tables with a tuned separator row, and narrow tables (natural widths), are left unchanged.
-- `<br/>` in a cell (see break_replace.lua) starts a new line.
-- luacheck: globals FORMAT pandoc

if not FORMAT:match("latex") then return {} end

-- Text width, in characters of the body font
local TEXT_WIDTH = 110
-- Inline code characters are wider than body text characters
local CODE_FACTOR = 1.25
-- Space between columns, in characters
local COLUMN_PADDING = 2

-- Measurement state of a cell: current line and word, longest line and word so far
local function end_word(m)
    m.longest_word = math.max(m.longest_word, m.word)
    m.word = 0
end

local function end_line(m)
    end_word(m)
    m.longest_line = math.max(m.longest_line, m.line)
    m.line = 0
end

local function add(m, width)
    m.word = m.word + width
    m.line = m.line + width
end

-- Add the width of a list of inlines to the measurement state
local function walk(inlines, m)
    for _, el in ipairs(inlines) do
        if el.t == "Str" or el.t == "Math" then
            add(m, utf8.len(el.text) or #el.text)
        elseif el.t == "Space" or el.t == "SoftBreak" then
            end_word(m)
            m.line = m.line + 1
        elseif el.t == "LineBreak" or (el.t == "RawInline" and el.format == "html" and el.text:match("^<br%s*/?>$")) then
            end_line(m)
        elseif el.t == "Code" then
            -- breaks at spaces only (code_break.lua adds more break points, as a last resort)
            local first = true
            for piece in el.text:gmatch("%S+") do
                if not first then
                    end_word(m)
                    m.line = m.line + CODE_FACTOR
                end
                add(m, (utf8.len(piece) or #piece) * CODE_FACTOR)
                first = false
            end
        elseif el.t == "Quoted" then
            add(m, 1)
            walk(el.content, m)
            add(m, 1)
        elseif el.content ~= nil and el.t ~= "Note" then
            -- Emph, Strong, Link, Span, Strikeout, Underline, SmallCaps, Cite...
            walk(el.content, m)
        end
    end
end

-- Longest line and longest word of a table cell
local function measure_cell(cell)
    local m = { line = 0, word = 0, longest_line = 0, longest_word = 0 }
    for _, block in ipairs(cell.contents) do
        if block.t == "Plain" or block.t == "Para" then
            walk(block.content, m)
        else
            walk(pandoc.Inlines(pandoc.utils.stringify(block)), m)
        end
        end_line(m)
    end
    return m.longest_line, m.longest_word
end

-- True if all columns have the same relative width, i.e. the separator row was not tuned
local function equal_widths(colspecs)
    local first = colspecs[1][2]
    if type(first) ~= "number" then return false end
    for _, colspec in ipairs(colspecs) do
        if type(colspec[2]) ~= "number" or math.abs(colspec[2] - first) > 1e-6 then return false end
    end
    return true
end

function Table(tbl)
    local count = #tbl.colspecs
    if count < 2 or not equal_widths(tbl.colspecs) then return nil end
    local want, need = {}, {}
    for i = 1, count do
        want[i], need[i] = 0, 0
    end
    local function measure_rows(rows)
        for _, row in ipairs(rows) do
            for i, cell in ipairs(row.cells) do
                if i <= count and cell.col_span == 1 then
                    local line, word = measure_cell(cell)
                    want[i] = math.max(want[i], line + COLUMN_PADDING)
                    need[i] = math.max(need[i], word + COLUMN_PADDING)
                end
            end
        end
    end
    measure_rows(tbl.head.rows)
    for _, body in ipairs(tbl.bodies) do
        measure_rows(body.head)
        measure_rows(body.body)
    end
    measure_rows(tbl.foot.rows)
    local sum_want, sum_need = 0, 0
    for i = 1, count do
        sum_want, sum_need = sum_want + want[i], sum_need + need[i]
    end
    local widths = {}
    if sum_want <= TEXT_WIDTH then
        -- the content fits on one line per cell: the table is narrower than the text
        for i = 1, count do
            widths[i] = want[i] / TEXT_WIDTH
        end
    else
        local rest = math.max(0, TEXT_WIDTH - sum_need)
        local sum_extra = sum_want - sum_need
        local total = 0
        for i = 1, count do
            widths[i] = need[i] + rest * (want[i] - need[i]) / sum_extra
            total = total + widths[i]
        end
        for i = 1, count do
            widths[i] = widths[i] / total
        end
    end
    for i = 1, count do
        tbl.colspecs[i] = { tbl.colspecs[i][1], widths[i] }
    end
    return tbl
end
