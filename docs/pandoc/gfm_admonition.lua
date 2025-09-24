local box_styles = {
  note = {
    colback = "blue!5",
    coltitle = "white",
    colbacktitle = "blue!75!black",
    htmlclass = "admonition note",
  },
  caution = {
    colback = "yellow!5",
    coltitle = "black",
    colbacktitle = "yellow!70!black",
    htmlclass = "admonition caution",
  },
  warning = {
    colback = "red!5",
    coltitle = "white",
    colbacktitle = "red!75!black",
    htmlclass = "admonition warning",
  },
  important = {
    colback = "orange!5",
    coltitle = "white",
    colbacktitle = "orange!70!black",
    htmlclass = "admonition important",
  },
  tip = {
    colback = "green!5",
    coltitle = "white",
    colbacktitle = "green!60!black",
    htmlclass = "admonition tip",
  },
  info = {
    colback = "gray!5",
    coltitle = "black",
    colbacktitle = "gray!60!black",
    htmlclass = "admonition info",
  },
}

function Div(el)
  if #el.classes == 0 then return nil end
  local tag = el.classes[1]
  local style = box_styles[tag]
  if not style then return nil end

  -- Extract title (first child Div)
  local title = tag:gsub("^%l", string.upper)
  local content_blocks = {}
  for _, block in ipairs(el.content) do
    if block.t == "Div" and block.classes[1] == "title" then
      title = pandoc.utils.stringify(block)
    else
      table.insert(content_blocks, block)
    end
  end

  -- Render depending on output format
  if FORMAT:match("latex") then
    local opts = string.format(
      "enhanced, breakable, colback=%s, colframe=%s, coltitle=%s, colbacktitle=%s, title={%s}",
      style.colback, style.colbacktitle, style.coltitle, style.colbacktitle, title
    )

    local body_parts = {}
    for _, b in ipairs(content_blocks) do
      table.insert(body_parts, pandoc.write(pandoc.Pandoc({ b }), "latex"))
    end
    local body = table.concat(body_parts, "\n")

    return pandoc.RawBlock("latex",
      "\\begin{tcolorbox}[" .. opts .. "]\n" ..
      body .. "\n" ..
      "\\end{tcolorbox}")
  elseif FORMAT:match("html") then
    local body_parts = {}
    for _, b in ipairs(content_blocks) do
      table.insert(body_parts, pandoc.write(pandoc.Pandoc({ b }), "html"))
    end
    local body = table.concat(body_parts, "\n")

    local html = string.format(
      '<div class="%s">\n<div class="admonition-title">%s</div>\n<div class="admonition-body">%s</div>\n</div>',
      style.htmlclass, title, body
    )
    return pandoc.RawBlock("html", html)
  else
    return nil
  end
end
