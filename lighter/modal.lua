local core = require "core"
local keymap = require "core.keymap"
local command = require "core.command"
local config = require "core.config"
local style = require "core.style"
local DocView = require "core.docview"
local CommandView = require "core.commandview"

local modal = {}

---@alias lighter.mode "normal"|"insert"|"visual"|"command"
modal.mode = "normal"
modal.prev_mode = "normal"

modal.chord = { active = false, keys = {}, timer = 0 }
local CHORD_TIMEOUT = 1.5

local original_docview_draw_caret = DocView.draw_caret

function DocView:draw_caret(x, y)
  if modal.mode == "normal" or modal.mode == "visual" then
    local lh = self:get_line_height()
    local font = self:get_font()
    local ch_w = font:get_width(" ")
    local color = { style.caret[1], style.caret[2], style.caret[3], 180 }
    renderer.draw_rect(x, y, ch_w, lh, color)
  else
    original_docview_draw_caret(self, x, y)
  end
end

function modal.set_mode(mode)
  modal.prev_mode = modal.mode
  modal.mode = mode
  modal.chord.active = false
  modal.chord.keys = {}

  local av = core.active_view
  if av and av:is(DocView) then
    if mode == "normal" then
      av.cursor = "arrow"
    else
      av.cursor = "ibeam"
    end
  end

  core.redraw = true
end

local normal_map = {
  ["i"]     = function() modal.set_mode("insert") end,
  ["a"]     = function()
    command.perform("doc:move-to-next-char")
    modal.set_mode("insert")
  end,
  ["A"]     = function()
    command.perform("doc:move-to-end-of-line")
    modal.set_mode("insert")
  end,
  ["I"]     = function()
    command.perform("doc:move-to-start-of-indentation")
    modal.set_mode("insert")
  end,
  ["o"]     = function()
    command.perform("doc:newline-below")
    modal.set_mode("insert")
  end,
  ["O"]     = function()
    command.perform("doc:newline-above")
    modal.set_mode("insert")
  end,
  ["v"]     = function() modal.set_mode("visual") end,

  ["h"]     = "doc:move-to-previous-char",
  ["j"]     = "doc:move-to-next-line",
  ["k"]     = "doc:move-to-previous-line",
  ["l"]     = "doc:move-to-next-char",
  ["w"]     = "doc:move-to-next-word-end",
  ["b"]     = "doc:move-to-previous-word-start",
  ["0"]     = "doc:move-to-start-of-line",
  ["$"]     = "doc:move-to-end-of-line",
  ["^"]     = "doc:move-to-start-of-indentation",
  ["G"]     = "doc:move-to-end-of-doc",

  ["x"]     = "doc:delete",
  ["u"]     = "doc:undo",
  ["p"]     = "doc:paste",
  ["Y"]     = function()
    command.perform("doc:select-lines")
    command.perform("doc:copy")
    command.perform("doc:select-none")
  end,

  ["/"]     = "find-replace:find",
  ["n"]     = "find-replace:repeat-find",
  ["N"]     = "find-replace:previous-find",

  [":"]     = function()
    modal.set_mode("command")
    command.perform("core:find-command")
  end,
}

local normal_sequences = {
  ["g"] = {
    ["g"] = "doc:move-to-start-of-doc",
    ["d"] = "lsp:goto-definition",
    ["r"] = "lsp:goto-references",
    ["i"] = "lsp:goto-implementation",
  },
  ["d"] = {
    ["d"] = function()
      command.perform("doc:select-lines")
      command.perform("doc:cut")
    end,
  },
  ["y"] = {
    ["y"] = function()
      command.perform("doc:select-lines")
      command.perform("doc:copy")
      command.perform("doc:select-none")
    end,
  },
  ["z"] = {
    ["z"] = function() end,
  },
}

local leader_map = {
  ["w"]     = "doc:save",
  ["q"]     = "root:close",

  ["f"] = {
    ["f"] = "core:find-file",
    ["g"] = "find-replace:find",
    ["b"] = "core:find-command",
    ["p"] = "core:find-command",
  },

  ["l"] = {
    ["d"] = "lsp:goto-definition",
    ["r"] = "lsp:goto-references",
    ["a"] = "lsp:code-action",
    ["n"] = "lsp:rename",
    ["e"] = "lsp:show-diagnostics",
  },

  ["g"] = {
    ["g"] = "lighter:lazygit",
    ["b"] = "lighter:git-blame",
    ["s"] = "lighter:git-status",
  },

  ["e"]     = "treeview:toggle",

  ["s"] = {
    ["v"] = "root:split-right",
    ["h"] = "root:split-down",
    ["x"] = "root:close",
  },

  ["r"] = {
    ["r"] = "lighter:run-file",
    ["l"] = "lighter:run-line",
  },

  ["c"] = {
    ["g"] = "lighter:theme-gruvbox",
    ["t"] = "lighter:theme-tokyonight",
    ["n"] = "lighter:theme-nightfox",
    ["f"] = "lighter:theme-token",
  },

  ["x"] = {
    ["x"] = "lighter:diagnostics-toggle",
    ["e"] = "lighter:diagnostics-errors",
  },

  ["t"] = {
    ["t"] = "lighter:terminal-toggle",
  },

  ["m"] = "lighter:format",
}

local visual_map = {
  ["h"]     = "doc:select-to-previous-char",
  ["j"]     = "doc:select-to-next-line",
  ["k"]     = "doc:select-to-previous-line",
  ["l"]     = "doc:select-to-next-char",
  ["w"]     = "doc:select-to-next-word-end",
  ["b"]     = "doc:select-to-previous-word-start",
  ["0"]     = "doc:select-to-start-of-line",
  ["$"]     = "doc:select-to-end-of-line",
  ["G"]     = "doc:select-to-end-of-doc",
  ["d"]     = function()
    command.perform("doc:cut")
    modal.set_mode("normal")
  end,
  ["y"]     = function()
    command.perform("doc:copy")
    command.perform("doc:select-none")
    modal.set_mode("normal")
  end,
  ["x"]     = function()
    command.perform("doc:cut")
    modal.set_mode("normal")
  end,
}

local pending_seq = nil
local pending_timer = 0

local function resolve_key(key)
  if key == "escape" then
    if modal.mode ~= "normal" then
      modal.set_mode("normal")
      command.perform("doc:select-none")
      return true
    end
    pending_seq = nil
    modal.chord.active = false
    modal.chord.keys = {}
    return true
  end

  if modal.mode == "insert" then
    return false
  end

  if modal.mode == "command" then
    return false
  end

  local map = modal.mode == "visual" and visual_map or normal_map

  if modal.chord.active then
    local chord_map = leader_map
    for _, k in ipairs(modal.chord.keys) do
      if type(chord_map) == "table" and chord_map[k] then
        chord_map = chord_map[k]
      else
        modal.chord.active = false
        modal.chord.keys = {}
        return true
      end
    end
    if type(chord_map) == "table" and chord_map[key] then
      local action = chord_map[key]
      if type(action) == "table" then
        table.insert(modal.chord.keys, key)
        return true
      elseif type(action) == "function" then
        action()
        modal.chord.active = false
        modal.chord.keys = {}
        return true
      elseif type(action) == "string" then
        command.perform(action)
        modal.chord.active = false
        modal.chord.keys = {}
        return true
      end
    end
    modal.chord.active = false
    modal.chord.keys = {}
    return true
  end

  if pending_seq then
    local seq_map = pending_seq
    pending_seq = nil
    if seq_map[key] then
      local action = seq_map[key]
      if type(action) == "function" then
        action()
      elseif type(action) == "string" then
        command.perform(action)
      end
      return true
    end
    return true
  end

  if (key == " " or key == "space") and modal.mode == "normal" then
    modal.chord.active = true
    modal.chord.keys = {}
    return true
  end

  if modal.mode == "normal" and normal_sequences[key] then
    pending_seq = normal_sequences[key]
    return true
  end

  local action = map[key]
  if action then
    if type(action) == "function" then
      action()
    elseif type(action) == "string" then
      command.perform(action)
    end
    return true
  end

  return false
end

local original_on_event = core.on_event

function core.on_event(type, ...)
  if type == "textinput" then
    if modal.mode == "normal" or modal.mode == "visual" then
      local text = ...
      if resolve_key(text) then
        return true
      end
      return true
    end
  end

  if type == "keypressed" then
    local key = ...
    if key == "escape" then
      if resolve_key("escape") then
        return true
      end
    end
    if modal.mode == "normal" or modal.mode == "visual" then
      if keymap.modkeys["ctrl"] or keymap.modkeys["cmd"] or keymap.modkeys["alt"] then
        return original_on_event(type, ...)
      end
    end
  end

  return original_on_event(type, ...)
end

local original_commandview_exit = CommandView.exit
function CommandView:exit(submitted, inexplicit)
  if modal.mode == "command" then
    modal.set_mode("normal")
  end
  return original_commandview_exit(self, submitted, inexplicit)
end

command.add(nil, {
  ["lighter:enter-normal-mode"] = function()
    modal.set_mode("normal")
  end,
  ["lighter:enter-insert-mode"] = function()
    modal.set_mode("insert")
  end,
})

keymap.add({
  ["ctrl+["] = "lighter:enter-normal-mode",
}, true)

return modal
