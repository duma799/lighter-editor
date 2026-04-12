-- Token theme for Lite XL
-- Ported from https://github.com/duma799/token (Neovim theme)
-- Dark variant

local style = require "core.style"
local common = require "core.common"

-- Dark palette
local p = {
  bg0    = "#191918",  -- darkest (panels, float bg)
  bg1    = "#1d1d1c",  -- statusline, tabline, scrollbar track
  bg2    = "#212120",  -- line number bg, sign column
  bg3    = "#262624",  -- normal background
  bg4    = "#2f2f2d",  -- cursor line, color column
  bg5    = "#383835",  -- selection, snippet, quickfix

  fg0    = "#e8e4dc",  -- normal text
  fg1    = "#d4cfc6",  -- slightly dimmed text
  fg2    = "#938e87",  -- comments, muted
  fg3    = "#5a5955",  -- most muted (indent guides, etc.)

  accent  = "#d97757", -- functions, titles (warm orange-red)
  accent2 = "#c4956a", -- keywords, booleans (warm tan)

  blue   = "#7b9ebd",
  green  = "#7da47a",
  red    = "#c67777",
  yellow = "#c4a855",
  purple = "#a68bbf",
  cyan   = "#6ba8a8",
  orange = "#d4914a",
  olive  = "#a8b56b",

  sel    = "#333331",
  match  = "#4a4030",
  line_nr = "#585855",
}

-- UI
style.background        = { common.color(p.bg3) }
style.background2       = { common.color(p.bg1) }
style.background3       = { common.color(p.bg5) }
style.text              = { common.color(p.fg0) }
style.caret             = { common.color(p.fg0) }
style.accent            = { common.color(p.accent) }
style.dim               = { common.color(p.fg2) }
style.divider           = { common.color(p.bg0) }
style.selection         = { common.color(p.sel) }
style.line_number       = { common.color(p.line_nr) }
style.line_number2      = { common.color(p.accent2) }
style.line_highlight    = { common.color(p.bg4) }
style.scrollbar         = { common.color(p.bg4) }
style.scrollbar2        = { common.color(p.bg5) }
style.scrollbar_track   = { common.color(p.bg1) }
style.nagbar            = { common.color(p.red) }
style.nagbar_text       = { common.color(p.bg3) }
style.nagbar_dim        = { common.color("#a05555") }
style.drag_overlay      = { common.color(p.bg3 .. "80") }
style.drag_overlay_tab  = { common.color(p.accent .. "40") }
style.good              = { common.color(p.green) }
style.warn              = { common.color(p.yellow) }
style.error             = { common.color(p.red) }
style.modified          = { common.color(p.yellow) }

-- Syntax
style.syntax["normal"]   = { common.color(p.fg0) }
style.syntax["symbol"]   = { common.color(p.fg0) }
style.syntax["comment"]  = { common.color(p.fg2) }
style.syntax["keyword"]  = { common.color(p.accent2) }
style.syntax["keyword2"] = { common.color(p.accent) }
style.syntax["number"]   = { common.color(p.purple) }
style.syntax["literal"]  = { common.color(p.orange) }
style.syntax["string"]   = { common.color(p.green) }
style.syntax["operator"] = { common.color(p.fg1) }
style.syntax["function"] = { common.color(p.accent) }
