local box_styles = {
  note = {
    colback      = "blue!5",
    coltitle     = "white",
    colbacktitle = "blue!75!black",
    htmlclass    = "admonition note",
    latexicon    = "InfoCircle",
    htmlicon     = "ℹ️ ",
  },
  caution = {
    colback      = "yellow!5",
    coltitle     = "black",
    colbacktitle = "yellow!70!black",
    htmlclass    = "admonition caution",
    latexicon    = "ExclamationTriangle",
    htmlicon     = "⚠️ ",
  },
  warning = {
    colback      = "red!5",
    coltitle     = "white",
    colbacktitle = "red!75!black",
    htmlclass    = "admonition warning",
    latexicon    = "ExclamationTriangle",
    htmlicon     = "⚠️ ",
  },
  important = {
    colback      = "orange!5",
    coltitle     = "white",
    colbacktitle = "orange!70!black",
    htmlclass    = "admonition important",
    latexicon    = "ExclamationTriangle",
    htmlicon     = "❗ ",
  },
  tip = {
    colback      = "green!5",
    coltitle     = "white",
    colbacktitle = "green!60!black",
    htmlclass    = "admonition tip",
    latexicon    = "Lightbulb",
    htmlicon     = "💡 ",
  },
  info = {
    colback      = "gray!5",
    coltitle     = "black",
    colbacktitle = "gray!60!black",
    htmlclass    = "admonition info",
    latexicon    = "InfoCircle",
    htmlicon     = "ℹ️ ",
  },
}

function Div(el)
  if #el.classes == 0 then return nil end
  local style = box_styles[el.classes[1]]
  if not style then return nil end
  if not (el.content[1] and el.content[1].t == "Div" and el.content[1].classes:includes("title")) then return el end
  local title_div_content = el.content[1].content
  if #title_div_content ~= 1 or title_div_content[1].t ~= "Para" then return el end
  local title = pandoc.utils.stringify(table.remove(title_div_content, 1))
  local body_parts = {}
  for i, block in ipairs(el.content) do
    table.insert(body_parts, block)
  end
  if FORMAT:match("latex") then
    local opts = string.format(
      "enhanced, breakable, colback=%s, colframe=%s, coltitle=%s, colbacktitle=%s, title={%s}",
      style.colback, style.colbacktitle, style.coltitle, style.colbacktitle, "\\fa" .. style.latexicon .. "\\ " .. title
    )
    local body = pandoc.write(pandoc.Pandoc(body_parts), "latex")
    return pandoc.RawBlock("latex",
      "\\begin{tcolorbox}[" .. opts .. "]\n" ..
      body .. "\n\\end{tcolorbox}")
  elseif FORMAT:match("html") then
    local body = pandoc.write(pandoc.Pandoc(body_parts), "html")
    local html = string.format(
      '<div class="%s">\n<div class="admonition-title">%s %s</div>\n<div class="admonition-body">%s</div>\n</div>',
      style.htmlclass, style.htmlicon, title, body
    )
    return pandoc.RawBlock("html", html)
  end
  return el
end
