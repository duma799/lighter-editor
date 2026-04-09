local core = require "core"
local common = require "core.common"
local command = require "core.command"
local style = require "core.style"
local StatusView = require "core.statusview"
local DocView = require "core.docview"
local CommandView = require "core.commandview"

local statusline = {}

local mode_colors = {
  normal  = { common.color "#7aa2f7" },
  insert  = { common.color "#9ece6a" },
  visual  = { common.color "#bb9af7" },
  command = { common.color "#e0af68" },
}

local mode_labels = {
  normal  = " NORMAL ",
  insert  = " INSERT ",
  visual  = " VISUAL ",
  command = " COMMAND ",
}

core.add_thread(function()
  while not core.status_view do
    coroutine.yield()
  end

  local sv = core.status_view

  sv:add_item({
    name = "lighter:mode",
    alignment = StatusView.Item.LEFT,
    position = 1,
    get_item = function()
      local ok, modal = pcall(require, "lighter.modal")
      if not ok then
        return { style.text, " NORMAL " }
      end
      local mode = modal.mode or "normal"
      local color = mode_colors[mode] or style.text
      local label = mode_labels[mode] or " " .. mode:upper() .. " "
      return {
        style.background2 or style.background, style.font,
        color, style.bold_font or style.font, label,
        style.text, style.font,
      }
    end,
    separator = StatusView.separator,
  })

  sv:add_item({
    name = "lighter:git-branch",
    alignment = StatusView.Item.LEFT,
    get_item = function()
      if not statusline.git_branch then
        return {}
      end
      return {
        style.dim, style.icon_font, "g",
        style.font, " ", style.text, statusline.git_branch,
      }
    end,
    separator = StatusView.separator,
  })

  sv:add_item({
    name = "lighter:diagnostics",
    alignment = StatusView.Item.RIGHT,
    get_item = function()
      local errors = statusline.diag_errors or 0
      local warnings = statusline.diag_warnings or 0
      if errors == 0 and warnings == 0 then
        return { style.good, "✓ 0" }
      end
      local items = {}
      if errors > 0 then
        table.insert(items, style.error)
        table.insert(items, "● " .. errors)
      end
      if warnings > 0 then
        if errors > 0 then
          table.insert(items, style.text)
          table.insert(items, " ")
        end
        table.insert(items, style.warn)
        table.insert(items, "▲ " .. warnings)
      end
      return items
    end,
    separator = StatusView.separator2,
  })

  core.log_quiet("[Lighter] Statusline items registered")
end)

statusline.git_branch = nil
statusline.diag_errors = 0
statusline.diag_warnings = 0

local function update_git_branch()
  core.add_thread(function()
    while true do
      local cwd = core.project_dir
      local proc = process.start(
        { "git", "rev-parse", "--abbrev-ref", "HEAD" },
        { stdout = process.REDIRECT_PIPE, stderr = process.REDIRECT_PIPE, cwd = cwd }
      )
      if proc then
        local out = {}
        while true do
          local chunk = proc:read_stdout()
          if chunk and chunk ~= "" then table.insert(out, chunk)
          elseif not proc:running() then break
          else coroutine.yield(0.1) end
        end
        local branch = table.concat(out)
        if branch and branch ~= "" and proc:returncode() == 0 then
          statusline.git_branch = branch:match("^%s*(.-)%s*$")
        else
          statusline.git_branch = nil
        end
      end
      coroutine.yield(5)
    end
  end)
end

update_git_branch()

return statusline
