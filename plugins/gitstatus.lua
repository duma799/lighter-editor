-- mod-version:3
local core = require "core"
local common = require "core.common"
local config = require "core.config"
local style = require "core.style"
local StatusView = require "core.statusview"
local TreeView = require "plugins.treeview"

config.plugins.gitstatus = common.merge({
  color_icons = true,
  recurse_submodules = true,
  config_spec = {
    name = "Git Status",
    {
      label = "Colorize icons",
      description = "Colorize the icons as well",
      path = "color_icons",
      type = "toggle",
      default = true
    },
    {
      label = "Recurse Submodules",
      description = "Also retrieve git stats from submodules.",
      path = "recurse_submodules",
      type = "toggle",
      default = true
    }
  }
}, config.plugins.gitstatus)

style.gitstatus_addition = {common.color "#587c0c"}
style.gitstatus_modification = {common.color "#0c7d9d"}
style.gitstatus_deletion = {common.color "#94151b"}

local scan_rate = config.project_scan_rate or 5
local cached_color_for_item = {}

local function uc(n) return utf8.char(n) end

local FILE_ICONS = {
  lua   = uc(0xE620),  js    = uc(0xE74E),  ts    = uc(0xE628),
  jsx   = uc(0xE625),  tsx   = uc(0xE625),  py    = uc(0xE73C),
  html  = uc(0xE736),  css   = uc(0xE749),  scss  = uc(0xE603),
  sass  = uc(0xE603),  go    = uc(0xE724),  rs    = uc(0xE7A8),
  c     = uc(0xE61E),  cpp   = uc(0xE61D),  cs    = uc(0xE648),
  java  = uc(0xE738),  rb    = uc(0xE21E),  php   = uc(0xE608),
  swift = uc(0xE755),  kt    = uc(0xE634),  vue   = uc(0xFD42),
  json  = uc(0xE60B),  yaml  = uc(0xE6A8),  yml   = uc(0xE6A8),
  toml  = uc(0xE615),  xml   = uc(0xE619),  md    = uc(0xE609),
  txt   = uc(0xF15C),  sh    = uc(0xE795),  bash  = uc(0xE795),
  zsh   = uc(0xE795),  fish  = uc(0xE795),  sql   = uc(0xE7C4),
  db    = uc(0xE7C4),  dockerfile = uc(0xF308), gitignore = uc(0xE65D),
  env   = uc(0xF462),
}
local FILE_ICON_DEFAULT = uc(0xF15B)

local function get_file_icon(filename)
  local ext  = filename:match("%.([^%.]+)$")
  local base = filename:match("([^/\\]+)$") or filename
  return FILE_ICONS[ext] or FILE_ICONS[base:lower()] or FILE_ICON_DEFAULT
end

local treeview_get_item_text = TreeView.get_item_text
function TreeView:get_item_text(item, active, hovered)
  local text, font, color = treeview_get_item_text(self, item, active, hovered)
  if cached_color_for_item[item.abs_filename] then
    color = cached_color_for_item[item.abs_filename]
  end
  return text, font, color
end

local treeview_get_item_icon = TreeView.get_item_icon
function TreeView:get_item_icon(item, active, hovered)
  local character, font, color = treeview_get_item_icon(self, item, active, hovered)
  if item.type ~= "dir" then
    character = get_file_icon(item.abs_filename or "")
    font = style.font
  end
  if config.plugins.gitstatus and config.plugins.gitstatus.color_icons and cached_color_for_item[item.abs_filename] then
    color = cached_color_for_item[item.abs_filename]
  end
  return character, font, color
end

local treeview_draw_item = TreeView.draw_item
function TreeView:draw_item(item, active, hovered, x, y, w, h)
  if item.depth == 1 and item.type ~= "dir" then
    self:draw_item_background(item, active, hovered, x, y, w, h)
    x = x + style.padding.x
    self:draw_item_body(item, active, hovered, x, y, w, h)
  else
    treeview_draw_item(self, item, active, hovered, x, y, w, h)
  end
end

local git = {
  branch = nil,
  inserts = 0,
  deletes = 0,
}

local function exec(cmd)
  local proc = process.start(cmd)
  while proc:running() do
    coroutine.yield(0.1)
  end
  return proc:read_stdout() or ""
end


core.add_thread(function()
  while true do
    if system.get_file_info(".git") then
      git.branch = exec({"git", "rev-parse", "--abbrev-ref", "HEAD"}):match("[^\n]*")

      local inserts = 0
      local deletes = 0

      local diff = exec({"git", "diff", "--numstat"})
      if
        config.plugins.gitstatus.recurse_submodules
        and
        system.get_file_info(".gitmodules")
      then
        local diff2 = exec({"git", "submodule", "foreach", "git diff --numstat"})
        diff = diff .. diff2
      end

      cached_color_for_item = {}

      local folder = core.project_dir
      for line in string.gmatch(diff, "[^\n]+") do
        local submodule = line:match("^Entering '(.+)'$")
        if submodule then
          folder = core.project_dir .. PATHSEP .. submodule
        else
          local ins, dels, path = line:match("(%d+)%s+(%d+)%s+(.+)")
          if path then
            inserts = inserts + (tonumber(ins) or 0)
            deletes = deletes + (tonumber(dels) or 0)
            local abs_path = folder .. PATHSEP .. path
            while abs_path do
              cached_color_for_item[abs_path] = style.gitstatus_modification
              abs_path = common.dirname(abs_path)
            end
          end
        end
      end

      git.inserts = inserts
      git.deletes = deletes

    else
      git.branch = nil
    end

    coroutine.yield(scan_rate)
  end
end)


core.status_view:add_item({
  name = "status:git",
  alignment = StatusView.Item.RIGHT,
  get_item = function()
    if not git.branch then
      return {}
    end
    return {
      (git.inserts ~= 0 or git.deletes ~= 0) and style.accent or style.text,
      git.branch,
      style.dim, "  ",
      git.inserts ~= 0 and style.accent or style.text, "+", git.inserts,
      style.dim, " / ",
      git.deletes ~= 0 and style.accent or style.text, "-", git.deletes,
    }
  end,
  position = -1,
  tooltip = "branch and changes",
  separator = core.status_view.separator2
})
