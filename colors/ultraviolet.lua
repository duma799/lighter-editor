-- ultraViolet theme for Lite XL
-- Ported from ultraViolet by Gurvir (Zed theme)
-- Dark variant

local style = require "core.style"
local common = require "core.common"

local p = {
  bg0    = "#0B0C10",  -- darkest (panels, terminal, title bar)
  bg1    = "#0E0E11",  -- elevated surfaces, inactive tabs
  bg2    = "#111115",  -- editor background, tab bar, scrollbar track
  bg3    = "#1B1B1F",  -- element hover, indent guides, active line
  bg4    = "#222226",  -- borders, selection, search match
  bg5    = "#393940",  -- element active, indent guide active

  fg0    = "#F2F4F8",  -- normal text, icons
  fg1    = "#DCD8ED",  -- terminal foreground, variables
  fg2    = "#9AA1AB",  -- muted text, comments, line numbers
  fg3    = "#3A3A3A",  -- invisibles, most muted

  accent  = "#6F78FF", -- primary accent (keywords, titles, modified)
  accent2 = "#C58FFF", -- secondary accent (tags, types, link hover)

  blue    = "#6F78FF",
  green   = "#08BD8A",
  red     = "#FF6FAE",
  yellow  = "#E297DB",
  purple  = "#C58FFF",
  cyan    = "#B3BCEF",
  orange  = "#AF9CFF",
  olive   = "#08BDBA",

  sel     = "#222226",
  match   = "#222226",
  line_nr = "#9AA1AB",
}

-- UI
style.background        = { common.color(p.bg2) }
style.background2       = { common.color(p.bg1) }
style.background3       = { common.color(p.bg4) }
style.text              = { common.color(p.fg0) }
style.caret             = { common.color(p.fg0) }
style.accent            = { common.color(p.accent) }
style.dim               = { common.color(p.fg2) }
style.divider           = { common.color(p.bg4) }
style.selection         = { common.color(p.sel) }
style.line_number       = { common.color(p.line_nr) }
style.line_number2      = { common.color(p.fg0) }
style.line_highlight    = { common.color(p.bg3) }
style.scrollbar         = { common.color(p.bg3) }
style.scrollbar2        = { common.color(p.bg4) }
style.scrollbar_track   = { common.color(p.bg2) }
style.nagbar            = { common.color(p.red) }
style.nagbar_text       = { common.color(p.bg2) }
style.nagbar_dim        = { common.color("#a6416e") }
style.drag_overlay      = { common.color(p.bg2 .. "80") }
style.drag_overlay_tab  = { common.color(p.accent .. "40") }
style.good              = { common.color(p.green) }
style.warn              = { common.color(p.yellow) }
style.error             = { common.color(p.red) }
style.modified          = { common.color(p.accent) }

-- Syntax
style.syntax["normal"]   = { common.color(p.fg1) }
style.syntax["symbol"]   = { common.color(p.fg1) }
style.syntax["comment"]  = { common.color(p.fg2) }
style.syntax["keyword"]  = { common.color(p.accent) }
style.syntax["keyword2"] = { common.color(p.accent2) }
style.syntax["number"]   = { common.color(p.green) }
style.syntax["literal"]  = { common.color(p.red) }
style.syntax["string"]   = { common.color(p.olive) }
style.syntax["operator"] = { common.color("#DFDFE0") }
style.syntax["function"] = { common.color(p.orange) }
