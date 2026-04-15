local core = require "core"
local lighter_config = require "lighter.config"

local M = {}
M.config = lighter_config
M.version = "0.1.0"
M.plugins = {}

function M.load_plugin(name, display_name)
  display_name = display_name or name
  local ok, err = pcall(require, name)
  local status = ok and "loaded" or "error"
  M.plugins[display_name] = { status = status, error = not ok and err or nil }
  if ok then
    core.log_quiet("[Lighter] Loaded: %s", display_name)
  else
    core.error("[Lighter] Failed to load %s: %s", display_name, err)
  end
  return ok
end

function M.setup()
  core.log_quiet("[Lighter] v%s starting...", M.version)

  M.load_plugin("colors." .. M.config.theme, "theme:" .. M.config.theme)
  M.load_plugin("lighter.modal", "modal-keybinds")

  M.load_plugin("lighter.plugins.ui.statusline", "statusline")
  M.load_plugin("lighter.plugins.themes.switcher", "theme-switcher")
  M.load_plugin("lighter.plugins.project_picker", "project-picker")
  M.load_plugin("lighter.plugins.ui.sourcecontrol", "source-control")
  M.load_plugin("lighter.plugins.ui.gitgutter",    "git-gutter")
  M.load_plugin("lighter.plugins.ui.tabs",         "tabs")

  M.load_plugin("lighter.plugins.formatting", "formatting")

  core.log_quiet("[Lighter] Setup complete. %d plugins loaded.", M.plugin_count())
end

function M.plugin_count()
  local count = 0
  for _, info in pairs(M.plugins) do
    if info.status == "loaded" then count = count + 1 end
  end
  return count
end

return M
