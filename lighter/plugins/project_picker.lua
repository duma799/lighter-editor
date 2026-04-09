local core      = require "core"
local common    = require "core.common"
local command   = require "core.command"
local keymap    = require "core.keymap"
local style     = require "core.style"
local View      = require "core.view"
local RootView  = require "core.rootview"
local EmptyView = require "core.emptyview"

local overlay = nil

local orig_empty_draw = EmptyView.draw
EmptyView.draw = function(self)
  if overlay then
    self:draw_background(style.background)
  else
    orig_empty_draw(self)
  end
end

local HISTORY_FILE  = USERDIR .. "/lighter_history.lua"
local MAX_HISTORY   = 10

local function load_history()
  local ok, data = pcall(dofile, HISTORY_FILE)
  if ok and type(data) == "table" then return data end
  return {}
end

local function save_history(list)
  local f = io.open(HISTORY_FILE, "w")
  if not f then return end
  f:write("return {\n")
  for _, p in ipairs(list) do
    f:write(string.format("  %q,\n", p))
  end
  f:write("}\n")
  f:close()
end

local function push_history(path)
  local list = load_history()
  for i = #list, 1, -1 do
    if list[i] == path then table.remove(list, i) end
  end
  table.insert(list, 1, path)
  if #list > MAX_HISTORY then list[MAX_HISTORY + 1] = nil end
  save_history(list)
end

local PickerView = View:extend()

local BTN_W   = 200
local BTN_H   = 40
local ROW_H   = 46
local PAD     = 12
local LABEL_H = 30

function PickerView:new(on_select)
  PickerView.super.new(self)
  self.on_select  = on_select
  self.hovering   = false
  self.hover_idx  = nil
  self.choosing   = false
  self.history    = load_history()
end

function PickerView:get_name() return "Open Project" end

function PickerView:btn_y()
  return self.position.y + math.floor(self.size.y * 0.28)
end

function PickerView:btn_rect()
  local cx = self.position.x + self.size.x / 2
  local by = self:btn_y()
  return cx - BTN_W / 2, by, BTN_W, BTN_H
end

function PickerView:history_start_y()
  local _, by, _, bh = self:btn_rect()
  return by + bh + 32
end

function PickerView:row_rect(i)
  local rw   = math.min(500, self.size.x - PAD * 4)
  local rx   = self.position.x + (self.size.x - rw) / 2
  local ry   = self:history_start_y() + (i - 1) * ROW_H
  return rx, ry, rw, ROW_H
end

local CARD_W = 360

function PickerView:card_rect()
  local sw, sh = self.size.x, self.size.y
  local history_rows = #self.history
  local ch = 180 + LABEL_H + math.max(history_rows, 1) * ROW_H + 40
  local cx = self.position.x + (sw - CARD_W) / 2
  local cy = self.position.y + (sh - ch) / 2
  return cx, cy, CARD_W, ch
end

function PickerView:btn_rect()
  local cx, cy = self:card_rect()
  local bx = cx + (CARD_W - BTN_W) / 2
  local by = cy + 130
  return bx, by, BTN_W, BTN_H
end

function PickerView:history_start_y()
  local _, by, _, bh = self:btn_rect()
  return by + bh + 28
end

function PickerView:row_rect(i)
  local cx, _ = self:card_rect()
  local ry = self:history_start_y() + LABEL_H + (i - 1) * ROW_H
  return cx + PAD, ry, CARD_W - PAD * 2, ROW_H
end

function PickerView:draw()
  renderer.draw_rect(self.position.x, self.position.y,
    self.size.x, self.size.y, style.background)

  local cx, cy, cw, ch = self:card_rect()
  renderer.draw_rect(cx, cy, cw, ch, style.background2 or style.background)
  renderer.draw_rect(cx, cy, cw, 1, style.divider or style.dim)
  renderer.draw_rect(cx, cy + ch - 1, cw, 1, style.divider or style.dim)
  renderer.draw_rect(cx, cy, 1, ch, style.divider or style.dim)
  renderer.draw_rect(cx + cw - 1, cy, 1, ch, style.divider or style.dim)

  local font = style.big_font or style.font
  common.draw_text(font, style.text, "Open Project",
    "center", cx, cy + 20, cw, font:get_height())

  common.draw_text(style.font, style.dim, "Choose the folder you want to work in",
    "center", cx, cy + 20 + font:get_height() + 18, cw, style.font:get_height())

  local bx, by, bw, bh = self:btn_rect()
  local bg = self.hovering
    and (style.accent or style.selection)
    or  (style.selection or style.background3 or style.background)
  renderer.draw_rect(bx, by, bw, bh, bg)
  local label  = self.choosing and "Opening…" or "Open Folder"
  local lcolor = self.hovering and (style.background or style.text) or style.text
  common.draw_text(style.font, lcolor, label, "center", bx, by, bw, bh)

  local hy = self:history_start_y()
  renderer.draw_rect(cx + PAD, hy - 12, cw - PAD * 2, 1, style.divider or style.dim)

  if #self.history > 0 then
    common.draw_text(style.font, style.dim, "Recent",
      "center", cx, hy, cw, LABEL_H)
    for i, path in ipairs(self.history) do
      local rx, ry, rw, rh = self:row_rect(i)
      if self.hover_idx == i then
        renderer.draw_rect(rx, ry, rw, rh, style.line_highlight or style.selection)
      end
      local name = path:match("[^/\\]+$") or path
      common.draw_text(style.font, style.text, name, "center", rx, ry, rw, rh)
    end
  else
    common.draw_text(style.font, style.dim, "No recent projects",
      "center", cx, hy, cw, style.font:get_height())
  end
end

function PickerView:point_in_btn(x, y)
  local bx, by, bw, bh = self:btn_rect()
  return x >= bx and x <= bx + bw and y >= by and y <= by + bh
end

function PickerView:history_idx_at(x, y)
  for i in ipairs(self.history) do
    local rx, ry, rw, rh = self:row_rect(i)
    if x >= rx and x <= rx + rw and y >= ry and y <= ry + rh then
      return i
    end
  end
end

function PickerView:on_mouse_moved(x, y)
  self.hovering  = self:point_in_btn(x, y)
  self.hover_idx = self:history_idx_at(x, y)
end

function PickerView:on_mouse_pressed(button, x, y)
  if button ~= "left" then return end
  if self:point_in_btn(x, y) then
    self:pick(); return true
  end
  local i = self:history_idx_at(x, y)
  if i then
    self.on_select(self.history[i]); return true
  end
end

local native_ok, fspicker = pcall(require, "lighter.native.fspicker")

function PickerView:pick()
  if self.choosing then return end
  self.choosing = true

  core.add_thread(function()
    local path

    if native_ok then
      path = fspicker.pick_folder()

    elseif PLATFORM == "Windows" then
      local script = "Add-Type -AssemblyName System.Windows.Forms;" ..
        "$f=New-Object System.Windows.Forms.FolderBrowserDialog;" ..
        "if($f.ShowDialog() -eq 'OK'){$f.SelectedPath}"
      local proc = process.start(
        { "powershell", "-NoProfile", "-Command", script },
        { stdout = process.REDIRECT_PIPE, stderr = process.REDIRECT_PIPE })
      if proc then
        while proc:running() do coroutine.yield() end
        local out = proc:read_stdout(4096) or ""
        path = out:match("^%s*(.-)%s*$")
        if path == "" then path = nil end
      end

    else
      local proc = process.start(
        { "osascript", "-e",
          'POSIX path of (choose folder with prompt "Choose project folder")' },
        { stdout = process.REDIRECT_PIPE, stderr = process.REDIRECT_PIPE })
      if proc then
        while proc:running() do coroutine.yield() end
        if proc:returncode() == 0 then
          local out = proc:read_stdout(4096) or ""
          path = out:match("^%s*(.-)%s*$")
          if path == "" then path = nil end
        end
      end

      if not path then
        local proc2 = process.start(
          { "zenity", "--file-selection", "--directory",
            "--title=Choose project folder" },
          { stdout = process.REDIRECT_PIPE, stderr = process.REDIRECT_PIPE })
        if proc2 then
          while proc2:running() do coroutine.yield() end
          if proc2:returncode() == 0 then
            local out = proc2:read_stdout(4096) or ""
            path = out:match("^%s*(.-)%s*$")
            if path == "" then path = nil end
          end
        end
      end
    end

    self.choosing = false
    if path then self.on_select(path) end
  end)
end

command.add(function()
  if core.active_view and core.active_view:is(PickerView) then
    return true, core.active_view
  end
end, {
  ["picker:open-dialog"] = function(v) v:pick() end,
})

keymap.add { ["return"] = "picker:open-dialog" }

local picker = {}

local function get_treeview()
  local ok, tv = pcall(require, "plugins.treeview")
  if ok then return tv end
end

local function open_project(path)
  if not path or path == "" then return end
  path = path:gsub("[/\\]+$", "")
  local info = system.get_file_info(path)
  if not info then
    local ok, err = system.mkdir(path)
    if not ok then core.error("Cannot create folder: %s", err or path); return end
  elseif info.type ~= "dir" then
    core.error("Not a directory: %s", path); return
  end
  push_history(path)
  core.add_thread(function()
    coroutine.yield(0)
    local tv = get_treeview()
    if tv then tv.visible = true; tv.cache = {} end
    core.project_directories = {}
    core.open_folder_project(path)
  end)
end

local orig_rv_draw = RootView.draw
RootView.draw = function(self)
  orig_rv_draw(self)
  if overlay then
    overlay.position.x = self.position.x
    overlay.position.y = self.position.y
    overlay.size.x     = self.size.x
    overlay.size.y     = self.size.y
    overlay:draw()
  end
end

local orig_rv_mouse_moved = RootView.on_mouse_moved
RootView.on_mouse_moved = function(self, x, y, dx, dy)
  if overlay then overlay:on_mouse_moved(x, y); return end
  orig_rv_mouse_moved(self, x, y, dx, dy)
end

local orig_rv_mouse_pressed = RootView.on_mouse_pressed
RootView.on_mouse_pressed = function(self, button, x, y, clicks)
  if overlay then overlay:on_mouse_pressed(button, x, y, clicks); return end
  orig_rv_mouse_pressed(self, button, x, y, clicks)
end

function picker.show()
  core.root_view:close_all_docviews()
  local node = core.root_view:get_primary_node()
  if node then
    for i = #node.views, 1, -1 do
      node:close_view(core.root_view.root_node, node.views[i])
    end
  end
  local tv = get_treeview()
  if tv then tv.visible = false end

  overlay = PickerView(function(path)
    overlay = nil
    open_project(path)
  end)
  core.set_active_view(overlay)
end

function picker.hide()
  overlay = nil
end

command.add(nil, { ["lighter:open-project"] = picker.show })
keymap.add_direct { ["ctrl+o"] = "lighter:open-project" }

picker.show()

return picker
