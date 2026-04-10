local core = require "core"
local config = require "core.config"
local style = require "core.style"

local StatusView = require "core.statusview"
local orig_show = StatusView.show_message
StatusView.show_message = function() end

local userdir = USERDIR
package.path  = userdir .. "/?.lua;" .. userdir .. "/?/init.lua;" .. package.path
package.cpath = userdir .. "/?.dylib;" .. userdir .. "/?.so;" .. package.cpath

config.indent_size = 4
config.tab_type = "soft"
config.line_height = 1.2
config.scroll_past_end = true
config.highlight_current_line = true
config.max_tabs = 10
config.always_show_tabs = true
config.max_project_files = 100000
config.mouse_wheel_scroll = 20 * SCALE

if not config.plugins then config.plugins = {} end
config.plugins.toolbarview = false
config.plugins.workspace   = false

config.plugins.ai = {
  gemini_api_key = ""
}

local font_mono = userdir .. "/fonts/MesloLGSNerdFontMono-Regular.ttf"
local font_ui   = userdir .. "/fonts/MesloLGSNerdFont-Regular.ttf"
local font_opts = { antialiasing = "subpixel", hinting = "slight" }

local f = io.open(font_mono, "r")
if f then
  f:close()
  style.code_font = renderer.font.load(font_mono, 16 * SCALE, font_opts)
end
f = io.open(font_ui, "r")
if f then
  f:close()
  style.font = renderer.font.load(font_ui, 14 * SCALE, font_opts)
end

core.recent_projects = {}

local lighter = require "lighter.core"
lighter.setup()

local keymap = require "core.keymap"
keymap.add_direct { ["ctrl+n"] = "lighter:sidebar-toggle" }
keymap.add_direct { ["ctrl+g"] = "lighter:git-status" }
