local core = require "core"
local common = require "core.common"

local utils = {}

function utils.read_file(path)
  local f, err = io.open(path, "r")
  if not f then return nil, err end
  local content = f:read("*all")
  f:close()
  return content
end

function utils.write_file(path, content)
  local f, err = io.open(path, "w")
  if not f then return false, err end
  f:write(content)
  f:close()
  return true
end

function utils.exec(cmd_table, timeout_ms)
  local proc, err = process.start(cmd_table, {
    stdout = process.REDIRECT_PIPE,
    stderr = process.REDIRECT_PIPE,
  })
  if not proc then return nil, err end

  local stdout_buf = {}
  local stderr_buf = {}
  local elapsed = 0
  timeout_ms = timeout_ms or 10000

  while proc:running() do
    local chunk = proc:read_stdout(4096)
    if chunk then stdout_buf[#stdout_buf+1] = chunk end
    local echunk = proc:read_stderr(4096)
    if echunk then stderr_buf[#stderr_buf+1] = echunk end
    elapsed = elapsed + 16
    if elapsed > timeout_ms then
      proc:kill()
      return nil, "timeout"
    end
    coroutine.yield()
  end

  local chunk = proc:read_stdout(4096)
  while chunk do
    stdout_buf[#stdout_buf+1] = chunk
    chunk = proc:read_stdout(4096)
  end
  chunk = proc:read_stderr(4096)
  while chunk do
    stderr_buf[#stderr_buf+1] = chunk
    chunk = proc:read_stderr(4096)
  end

  return table.concat(stdout_buf), table.concat(stderr_buf), proc:returncode()
end

function utils.get_extension(filename)
  return filename and filename:match("%.([^%.]+)$")
end

function utils.get_language(doc)
  if not doc or not doc.filename then return nil end
  local ext = utils.get_extension(doc.filename)
  local map = {
    lua = "lua", py = "python", js = "javascript", ts = "typescript",
    jsx = "javascript", tsx = "typescript", html = "html", css = "css",
    json = "json", yaml = "yaml", yml = "yaml", md = "markdown",
    sh = "shell", bash = "shell", zsh = "shell",
    rs = "rust", go = "go", c = "c", cpp = "cpp", h = "c",
    java = "java", rb = "ruby", php = "php",
  }
  return map[ext]
end

function utils.merge(a, b)
  a = a or {}
  if not b then return a end
  for k, v in pairs(b) do
    if type(v) == "table" and type(a[k]) == "table" then
      a[k] = utils.merge(a[k], v)
    else
      a[k] = v
    end
  end
  return a
end

return utils
