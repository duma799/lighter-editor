local core = require "core"
local command = require "core.command"
local style = require "core.style"
local common = require "core.common"
local lighter_config = require "lighter.config"

local switcher = {}
switcher.current_theme = lighter_config.theme
switcher.transparency_enabled = false

function switcher.set_theme(name)
  local ok, err = pcall(function()
    core.reload_module("colors." .. name)
  end)
  if ok then
    switcher.current_theme = name
    if switcher.transparency_enabled then
      switcher.apply_transparency(lighter_config.transparency_alpha)
    end
    core.log_quiet("[Lighter] Theme: %s", name)
  else
    core.error("[Lighter] Failed to load theme '%s': %s", name, err)
  end
end

function switcher.apply_transparency(alpha)
  local a = math.floor((alpha or 0.95) * 255)
  local bg_keys = {
    "background", "background2", "background3",
    "line_highlight", "scrollbar_track", "drag_overlay",
  }
  for _, key in ipairs(bg_keys) do
    if style[key] and type(style[key]) == "table" and #style[key] >= 3 then
      style[key][4] = a
    end
  end
  switcher.transparency_enabled = true
end

function switcher.remove_transparency()
  switcher.transparency_enabled = false
  switcher.set_theme(switcher.current_theme)
end

function switcher.toggle_transparency()
  if switcher.transparency_enabled then
    switcher.remove_transparency()
    core.log_quiet("[Lighter] Transparency off")
  else
    switcher.apply_transparency(lighter_config.transparency_alpha)
    core.log_quiet("[Lighter] Transparency on")
  end
end

command.add(nil, {
  ["lighter:theme-gruvbox"] = function()
    switcher.set_theme("gruvbox")
  end,
  ["lighter:theme-tokyonight"] = function()
    switcher.set_theme("tokyonight")
  end,
  ["lighter:theme-nightfox"] = function()
    switcher.set_theme("nightfox")
  end,
  ["lighter:theme-token"] = function()
    switcher.set_theme("token")
  end,
  ["lighter:theme-ultraviolet"] = function()
    switcher.set_theme("ultraviolet")
  end,
  ["lighter:theme-toggle-transparency"] = function()
    switcher.toggle_transparency()
  end,
  ["lighter:theme-select"] = function()
    local themes = { "tokyonight", "gruvbox", "nightfox", "token", "ultraviolet" }
    core.command_view:enter("Select Theme", {
      submit = function(text, item)
        switcher.set_theme(item and item.text or text)
      end,
      suggest = function(text)
        local res = {}
        for _, name in ipairs(themes) do
          if name:find(text, 1, true) then
            table.insert(res, name)
          end
        end
        return res
      end,
    })
  end,
})

return switcher
