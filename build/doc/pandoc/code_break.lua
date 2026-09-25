-- For LaTeX output, allow line breaks inside inline code after separators
-- (e.g. `/`, `=`, `,`, `.`, `_`) so that long options, paths and identifiers
-- wrap instead of overflowing the page or the table cell.
-- Other hyphens get no break, as TeX would otherwise break after them (e.g. `-L`, `--`).
-- Code in headings is left unchanged, so that PDF bookmarks keep their text.
-- luacheck: globals FORMAT pandoc

if not FORMAT:match("latex") then return {} end

-- Private use characters marking break points, replaced after LaTeX escaping
local MARK_BREAK = utf8.char(0xE000)
local MARK_NOBREAK = utf8.char(0xE001)
-- Characters after which a break is allowed
local SEPARATORS = "[/=,;:._&?|]"

-- Mark break points: after a run of separators, after a hyphen between two alphanumerics,
-- or before an opening bracket following an alphanumeric (e.g. `Array[String]`)
local function mark_breaks(text)
  local result = {}
  for i = 1, #text - 1 do
    local prev, char, next = text:sub(i - 1, i - 1), text:sub(i, i), text:sub(i + 1, i + 1)
    table.insert(result, char)
    if next ~= " " and not next:match(SEPARATORS) and (
          char:match(SEPARATORS) or
          (char == "-" and prev:match("%w") and next:match("%w")) or
          (next == "[" and char:match("%w"))) then
      table.insert(result, MARK_BREAK)
    elseif char == "-" then
      table.insert(result, MARK_NOBREAK)
    end
  end
  table.insert(result, text:sub(-1))
  return table.concat(result)
end

return { {
  traverse = "topdown",
  Header = function(_) return nil, false end,
  Code = function(el)
    if #el.classes > 0 then return nil end
    local marked = mark_breaks(el.text)
    if marked == el.text then return nil end
    local latex = pandoc.write(pandoc.Pandoc({ pandoc.Plain({ pandoc.Code(marked) }) }), "latex",
      { wrap_text = "wrap-none" })
    latex = latex:gsub("%s+$", ""):gsub(MARK_BREAK, "\\allowbreak{}"):gsub(MARK_NOBREAK, "\\nobreak{}")
    return pandoc.RawInline("latex", latex)
  end,
} }
