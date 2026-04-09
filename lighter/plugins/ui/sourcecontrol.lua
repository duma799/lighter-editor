local core     = require "core"
local common   = require "core.common"
local command  = require "core.command"
local style    = require "core.style"
local View     = require "core.view"
local treeview = require "plugins.treeview"

local C_MODIFIED  = { common.color "#e0af68" }
local C_ADDED     = { common.color "#9ece6a" }
local C_DELETED   = { common.color "#f7768e" }
local C_RENAMED   = { common.color "#7dcfff" }
local C_CONFLICT  = { common.color "#bb9af7" }
local C_UNTRACKED = { common.color "#636d97" }

local STATUS_COLOR = {
  M = C_MODIFIED, A = C_ADDED,  D = C_DELETED,
  R = C_RENAMED,  C = C_CONFLICT, U = C_CONFLICT,
  ["?"] = C_UNTRACKED,
}

local function uc(n) return utf8.char(n) end

local FILE_ICONS = {
  lua   = uc(0xE620),
  py    = uc(0xE73C),
  js    = uc(0xE74E),
  ts    = uc(0xE628),
  jsx   = uc(0xE625),
  tsx   = uc(0xE625),
  html  = uc(0xE736),
  css   = uc(0xE749),
  scss  = uc(0xE603),
  sass  = uc(0xE603),
  go    = uc(0xE724),
  rs    = uc(0xE7A8),
  c     = uc(0xE61E),
  cpp   = uc(0xE61D),
  cs    = uc(0xE648),
  java  = uc(0xE738),
  rb    = uc(0xE21E),
  php   = uc(0xE608),
  swift = uc(0xE755),
  kt    = uc(0xE634),
  vue   = uc(0xFD42),
  json  = uc(0xE60B),
  yaml  = uc(0xE6A8),
  yml   = uc(0xE6A8),
  toml  = uc(0xE615),
  xml   = uc(0xE619),
  md    = uc(0xE609),
  txt   = uc(0xF15C),
  sh    = uc(0xE795),
  bash  = uc(0xE795),
  zsh   = uc(0xE795),
  fish  = uc(0xE795),
  sql   = uc(0xE7C4),
  db    = uc(0xE7C4),
  dockerfile = uc(0xF308),
  gitignore  = uc(0xE65D),
  env   = uc(0xF462),
}
local FILE_ICON_DEFAULT = uc(0xF15B)

local function get_file_icon(filename)
  local ext = filename:match("%.([^%.]+)$")
  local base = filename:match("([^/\\]+)$") or filename
  return FILE_ICONS[ext] or FILE_ICONS[base:lower()] or FILE_ICON_DEFAULT
end

local function exec(cmd, cwd)
  local proc = process.start(cmd, cwd and { cwd = cwd } or nil)
  if not proc then return "" end
  local out = {}
  while true do
    local chunk = proc:read_stdout()
    if chunk and chunk ~= "" then
      table.insert(out, chunk)
    elseif not proc:running() then
      break
    else
      coroutine.yield(0.1)
    end
  end
  return table.concat(out)
end

local SCMView = View:extend()
function SCMView:__tostring() return "SCMView" end

local SECTION_H = math.floor(22 * SCALE)
local ITEM_H    = math.floor(21 * SCALE)
local HEADER_H  = math.floor(40 * SCALE)
local TARGET_W  = math.floor(260 * SCALE)

local function do_git_refresh(self, dir)
  if not dir then return end
  if not system.get_file_info(dir .. PATHSEP .. ".git") then
    self.branch, self.staged, self.changes, self.untracked = nil, {}, {}, {}
    core.redraw = true
    return
  end

  self.branch = exec({"git","rev-parse","--abbrev-ref","HEAD"}, dir):match("[^\n]*")

  local staged, changes, untracked = {}, {}, {}
  local out = exec({"git","status","--porcelain"}, dir)
  for line in out:gmatch("[^\n]+") do
    local xy   = line:sub(1,2)
    local path = line:sub(4)
    path = path:match("^.+ %-> (.+)$") or path
    local x, y = xy:sub(1,1), xy:sub(2,2)
    if x ~= " " and x ~= "?" then table.insert(staged,   {status=x, path=path}) end
    if y ~= " " and y ~= "?" then table.insert(changes,  {status=y, path=path}) end
    if x == "?" and y == "?" then table.insert(untracked, {status="?",path=path}) end
  end

  self.staged, self.changes, self.untracked = staged, changes, untracked
  core.redraw = true
end

function SCMView:_refresh()
  local dir = core.project_dir
  core.add_thread(function()
    do_git_refresh(self, dir)
  end)
end

function SCMView:new()
  SCMView.super.new(self)
  self.scrollable  = true
  self.visible     = false
  self.init_size   = true
  self.target_size = TARGET_W

  self.branch    = nil
  self.staged    = {}
  self.changes   = {}
  self.untracked = {}

  self.expanded     = { staged = true, changes = true, untracked = true }
  self.hovered_item = nil
  self.count_lines  = 0

  core.add_thread(function()
    while true do
      coroutine.yield(self.visible and 5 or 30)
      self:_refresh()
    end
  end)
end

function SCMView:get_name() return nil end

function SCMView:set_target_size(axis, value)
  if axis == "x" then self.target_size = value; return true end
end

function SCMView:update()
  local dest = self.visible and self.target_size or 0
  if self.init_size then
    self.size.x = dest
    self.init_size = false
  else
    self:move_towards(self.size, "x", dest, nil, "treeview")
  end
  if not self.visible then return end
  SCMView.super.update(self)
end

function SCMView:get_scrollable_size()
  return self.count_lines * ITEM_H + HEADER_H + 16 * SCALE
end

local SECTIONS = {
  { key = "staged",    label = "STAGED CHANGES"  },
  { key = "changes",   label = "CHANGES"          },
  { key = "untracked", label = "UNTRACKED FILES"  },
}

function SCMView:each_item()
  return coroutine.wrap(function()
    local ox, oy = self:get_content_offset()
    local w = self.size.x
    local y = oy
    local lines = 0

    coroutine.yield({ type = "header" }, ox, y, w, HEADER_H)
    y = y + HEADER_H
    lines = lines + 1

    for _, sec in ipairs(SECTIONS) do
      local items = self[sec.key]
      if #items > 0 then
        local expanded = self.expanded[sec.key]
        coroutine.yield(
          { type = "section", key = sec.key, label = sec.label,
            expanded = expanded, count = #items },
          ox, y, w, SECTION_H)
        y = y + SECTION_H
        lines = lines + 1

        if expanded then
          for _, item in ipairs(items) do
            coroutine.yield({ type = "item", item = item }, ox, y, w, ITEM_H)
            y = y + ITEM_H
            lines = lines + 1
          end
        end
      end
    end

    self.count_lines = lines
  end)
end

function SCMView:on_mouse_moved(px, py, ...)
  if not self.visible then return end
  if SCMView.super.on_mouse_moved(self, px, py, ...) then
    self.hovered_item = nil
    return
  end
  self.hovered_item = nil
  for entry, x, y, w, h in self:each_item() do
    if px >= x and py >= y and px < x + w and py < y + h then
      self.hovered_item = entry
      break
    end
  end
end

function SCMView:on_mouse_pressed(button, px, py, clicks)
  if not self.visible then return end
  for entry, x, y, w, h in self:each_item() do
    if px >= x and py >= y and px < x + w and py < y + h then
      if entry.type == "section" then
        self.expanded[entry.key] = not self.expanded[entry.key]
        core.redraw = true
        return true
      elseif entry.type == "item" then
        local full = core.project_dir .. PATHSEP .. entry.item.path
        if system.get_file_info(full) then
          core.root_view:open_doc(core.open_doc(full))
        end
        return true
      elseif entry.type == "header" then
        self:_refresh()
        return true
      end
    end
  end
  return SCMView.super.on_mouse_pressed(self, button, px, py, clicks)
end

function SCMView:draw()
  if not self.visible then return end
  self:draw_background(style.background)

  local PAD = style.padding.x
  local ox, oy = self:get_content_offset()
  local w = self.size.x

  core.push_clip_rect(self.position.x, self.position.y, w, self.size.y)

  for entry, x, y, ew, eh in self:each_item() do
    local hovered = (self.hovered_item == entry)

    if entry.type == "header" then
      renderer.draw_rect(x, y, ew, eh, style.background2 or style.background)

      local title_y = y + math.floor((eh - style.font:get_height()) / 2)
      renderer.draw_text(style.font, "SOURCE CONTROL", x + PAD, title_y, style.text)

      if self.branch and #self.branch > 0 then
        local btext = " " .. self.branch
        local bw = style.font:get_width(btext) + PAD
        local bx = x + ew - bw - PAD
        renderer.draw_text(style.font, btext, bx, title_y, style.dim)
      end

      renderer.draw_rect(x, y + eh - 1, ew, 1, style.divider or style.dim)

    elseif entry.type == "section" then
      local bg = hovered and (style.line_highlight or style.background2)
                         or  (style.background2 or style.background)
      renderer.draw_rect(x, y, ew, eh, bg)

      local chevron = entry.expanded and "-" or "+"
      local cx = x + PAD
      common.draw_text(style.icon_font, style.dim, chevron, nil, cx, y, 0, eh)
      local icon_w = style.icon_font:get_width(chevron) + PAD

      local label = entry.label .. " (" .. entry.count .. ")"
      local lx = cx + icon_w
      local ty = y + math.floor((eh - style.font:get_height()) / 2)
      renderer.draw_text(style.font, label, lx, ty, style.text)

    elseif entry.type == "item" then
      local bg = hovered and (style.line_highlight or style.background2)
                         or  style.background
      renderer.draw_rect(x, y, ew, eh, bg)

      local item  = entry.item
      local color = STATUS_COLOR[item.status] or style.text
      local ty    = y + math.floor((eh - style.font:get_height()) / 2)

      local icon_char = get_file_icon(item.path)
      local ix = x + PAD
      common.draw_text(style.font, style.dim, icon_char, nil, ix, y, 0, eh)
      ix = ix + style.font:get_width(icon_char) + math.floor(12 * SCALE)

      local badge_text = item.status == "?" and "U" or item.status
      local badge_w    = style.font:get_width(badge_text)
      local badge_x    = x + ew - badge_w - PAD * 2
      renderer.draw_text(style.font, badge_text, badge_x, ty, color)

      local name   = common.basename(item.path)
      local name_w = badge_x - ix - PAD
      if name_w > 0 then
        common.draw_text(style.font,
          hovered and style.accent or style.text,
          name, "left", ix, y, name_w, eh)
      end
    end
  end

  core.pop_clip_rect()
  self:draw_scrollbar()
end

local scm_view = SCMView()

local tv_leaf = core.root_view.root_node:get_node_for_view(treeview)
if not tv_leaf then
  core.error("[Lighter] source-control: could not find treeview leaf node")
  return scm_view
end

do
  local saved = tv_leaf.locked
  tv_leaf.locked = nil
  tv_leaf:add_view(scm_view)
  tv_leaf.locked = saved
  tv_leaf:set_active_view(treeview)
end

local tv_node = tv_leaf

scm_view:_refresh()

local _orig_tv_update = treeview.update
treeview.update = function(self)
  _orig_tv_update(self)
  if self._scm_switch_pending and self.size.x < 1 then
    self._scm_switch_pending = false
    tv_node:set_active_view(scm_view)
    scm_view.visible = true
    scm_view:_refresh()
  end
end

command.add(nil, {
  ["lighter:git-status"] = function()
    if scm_view.visible then
      scm_view.visible = false
      tv_node:set_active_view(treeview)
    elseif treeview.visible then
      treeview._scm_switch_pending = true
      treeview.visible = false
    else
      tv_node:set_active_view(scm_view)
      scm_view.visible = true
    end

    if scm_view.visible then
      scm_view:_refresh()
    end
  end,
})

return scm_view
