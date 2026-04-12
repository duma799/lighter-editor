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

-- Horizontal scroll: only show/allow when lines overflow, with dead zone
local DocView = require "core.docview"

DocView.get_h_scrollable_size = function(self)
  if not self.doc then return 0 end
  local change_id = self.doc:get_change_id()
  if self._hscroll_cache_id == change_id then
    return self._hscroll_cache_w
  end
  local font = self:get_font()
  local _, indent_size = self.doc:get_indent_info()
  font:set_tab_size(indent_size)
  local max_w = 0
  for i = 1, math.min(#self.doc.lines, 10000) do
    local line = self.doc.lines[i]
    if line then
      local w = font:get_width(line:sub(1, -2))
      if w > max_w then max_w = w end
    end
  end
  local total = self:get_gutter_width() + max_w + style.padding.x * 2
  self._hscroll_cache_id = change_id
  self._hscroll_cache_w = total
  return total
end

-- Dead zone: horizontal scroll only fires when |dx| > 2.5 * |dy|
local _orig_on_event = core.on_event
core.on_event = function(type, ...)
  if type == "mousewheel" then
    local dy, dx = ...
    if dx and dx ~= 0 and math.abs(dx) <= math.abs(dy or 0) * 2.5 then
      return _orig_on_event(type, dy, 0)
    end
  end
  return _orig_on_event(type, ...)
end
