-- Convert styled admonition Div blocks (e.g. note, warning, tip) into
-- corresponding HTML or LaTeX representations with icons, colors, and titles.
-- Uses predefined visual styles from `box_styles` for consistent formatting.
-- luacheck: globals FORMAT pandoc
-- https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts
-- https://tug.ctan.org/info/symbols/comprehensive/symbols-a4.pdf
local box_styles = {
  note = {
    -- gfm : blue circled i
    html  = {
      icon = "ℹ️",
    },
    latex = {
      icon      = "InfoCircle",
      back      = "blue!5",
      title     = "white",
      backtitle = "blue!75!black",
    },
  },
  tip = {
    -- gfm : green lightbulb
    html  = {
      icon = "💡",
    },
    latex = {
      icon      = "Lightbulb",
      back      = "green!5",
      title     = "white",
      backtitle = "green!60!black",
    },
  },
  important = {
    -- gfm : purple speech bubble exclamation
    html  = {
      icon = "❕",
    },
    latex = {
      icon      = "Bullhorn",
      back      = "orange!5",
      title     = "white",
      backtitle = "orange!70!black",
    },
  },
  warning = {
    -- gfm : yellow triangle exclamation
    html  = {
      icon = "⚠️",
    },
    latex = {
      icon      = "ExclamationTriangle",
      back      = "red!5",
      title     = "white",
      backtitle = "red!75!black",
    },
  },
  caution = {
    -- gfm : red circled exclamation mark
    html  = {
      icon = "❗",
    },
    latex = {
      icon      = "Exclamation",
      back      = "yellow!5",
      title     = "black",
      backtitle = "yellow!70!black",
    },
  },
}

function Div(el)
  if #el.classes == 0 then return nil end
  local admon_type = el.classes[1]
  local style = box_styles[admon_type]
  if not style then return nil end
  if not (el.content[1] and el.content[1].t == "Div" and el.content[1].classes:includes("title")) then return el end
  local title_div_content = el.content[1].content
  if #title_div_content ~= 1 or title_div_content[1].t ~= "Para" then return el end
  local title = pandoc.utils.stringify(table.remove(title_div_content, 1))
  local body_parts = {}
  for _, block in ipairs(el.content) do
    table.insert(body_parts, block)
  end
  if FORMAT:match("latex") then
    style = style.latex
    local opts = string.format(
      "enhanced, breakable, colback=%s, colframe=%s, coltitle=%s, colbacktitle=%s, title={\\fa%s\\ %s}",
      style.back, style.backtitle, style.title, style.backtitle, style.icon, title
    )
    local body = pandoc.write(pandoc.Pandoc(body_parts), "latex")
    return pandoc.RawBlock("latex",
      "\\begin{tcolorbox}[" .. opts .. "]\n" ..
      body .. "\n\\end{tcolorbox}")
  elseif FORMAT:match("html") then
    local body = pandoc.write(pandoc.Pandoc(body_parts), "html")
    local html = string.format(
      '<div class="admonition %s">\n<div class="admonition-title">%s %s</div>\n<div class="admonition-body">%s</div>\n</div>',
      admon_type, style.html.icon, title, body
    )
    return pandoc.RawBlock("html", html)
  end
  return el
end
