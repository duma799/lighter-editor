local core = require "core"
local config = require "core.config"
local command = require "core.command"
local Doc = require "core.doc"
local lighter_config = require "lighter.config"
local utils = require "lighter.utils"

local formatting = {}

local function get_formatter(doc)
  local lang = utils.get_language(doc)
  if not lang then return nil end
  return lighter_config.formatters[lang], lang
end

function formatting.format_doc(doc)
  local fmt, lang = get_formatter(doc)
  if not fmt then return end

  local check = io.popen("which " .. fmt.cmd .. " 2>/dev/null")
  if check then
    local path = check:read("*l")
    check:close()
    if not path or path == "" then
      core.log("[Lighter] Formatter '%s' not found for %s", fmt.cmd, lang)
      return
    end
  end

  local args = { fmt.cmd }
  if fmt.args then
    for _, arg in ipairs(fmt.args) do
      table.insert(args, arg:gsub("{file}", doc.filename or ""))
    end
  end

  local uses_stdin = false
  for _, arg in ipairs(args) do
    if arg == "-" then uses_stdin = true; break end
  end

  if uses_stdin then
    local text = doc:get_text(1, 1, #doc.lines, #doc.lines[#doc.lines])

    core.add_thread(function()
      local proc, err = process.start(args, {
        stdin = process.REDIRECT_PIPE,
        stdout = process.REDIRECT_PIPE,
        stderr = process.REDIRECT_PIPE,
      })
      if not proc then
        core.error("[Lighter] Format failed: %s", err or "unknown error")
        return
      end

      proc:write(text)
      proc:close_stream(process.STREAM_STDIN)

      local out_buf = {}
      local err_buf = {}
      while proc:running() do
        local chunk = proc:read_stdout(4096)
        if chunk then out_buf[#out_buf+1] = chunk end
        local echunk = proc:read_stderr(4096)
        if echunk then err_buf[#err_buf+1] = echunk end
        coroutine.yield()
      end

      local chunk = proc:read_stdout(4096)
      while chunk do out_buf[#out_buf+1] = chunk; chunk = proc:read_stdout(4096) end
      chunk = proc:read_stderr(4096)
      while chunk do err_buf[#err_buf+1] = chunk; chunk = proc:read_stderr(4096) end

      local output = table.concat(out_buf)
      local errors = table.concat(err_buf)
      local code = proc:returncode()

      if code == 0 and #output > 0 then
        local line1, col1 = 1, 1
        local line2 = #doc.lines
        local col2 = #doc.lines[line2]

        if output ~= text then
          local cursor_line, cursor_col = doc:get_selection()

          doc:remove(line1, col1, line2, col2)
          doc:insert(1, 1, output)
          doc:clean()

          cursor_line = math.min(cursor_line, #doc.lines)
          cursor_col = math.min(cursor_col, #doc.lines[cursor_line])
          doc:set_selection(cursor_line, cursor_col)

          core.log_quiet("[Lighter] Formatted with %s", fmt.cmd)
        end
      elseif #errors > 0 then
        core.error("[Lighter] Format error (%s): %s", fmt.cmd, errors:sub(1, 200))
      end
    end)
  else
    core.add_thread(function()
      local proc = process.start(args, {
        stdout = process.REDIRECT_PIPE,
        stderr = process.REDIRECT_PIPE,
      })
      if not proc then return end
      while proc:running() do coroutine.yield() end
      local code = proc:returncode()
      if code == 0 then
        doc:reload()
        core.log_quiet("[Lighter] Formatted with %s", fmt.cmd)
      else
        local err = proc:read_stderr(4096) or ""
        core.error("[Lighter] Format error (%s): %s", fmt.cmd, err:sub(1, 200))
      end
    end)
  end
end

local original_save = Doc.save
function Doc:save(filename, abs_filename)
  original_save(self, filename, abs_filename)
  formatting.format_doc(self)
end

command.add("core.docview", {
  ["lighter:format"] = function(dv)
    formatting.format_doc(dv.doc)
  end,
})

return formatting
