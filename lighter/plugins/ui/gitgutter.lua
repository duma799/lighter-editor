local core    = require "core"
local common  = require "core.common"
local style   = require "core.style"
local Doc     = require "core.doc"
local DocView = require "core.docview"

local C_ADD = { common.color "#9ece6a" }
local C_MOD = { common.color "#e0af68" }
local C_DEL = { common.color "#f7768e" }

local BAR_W      = math.max(2, math.floor(3 * SCALE))
local BAR_W_WIDE = math.max(5, math.floor(7 * SCALE))

local NOGIT        = {}
local head_lines   = {}
local doc_marks    = setmetatable({}, { __mode = "k" })
local head_fetched = {}
local HEAD_TTL     = 30

local function exec(cmd, cwd)
  local proc = process.start(cmd, cwd and { cwd = cwd } or nil)
  if not proc then return "" end

  local out = {}
  local err = {}

  local function drain()
    while true do
      local c = proc:read_stdout()
      if c and c ~= "" then table.insert(out, c) else break end
    end
    while true do
      local c = proc.read_stderr and proc:read_stderr()
      if c and c ~= "" then table.insert(err, c) else break end
    end
  end

  while proc:running() do
    drain()
    coroutine.yield(0.02)
  end
  drain()

  local err_str = table.concat(err)
  if err_str ~= "" then
    core.log("gitgutter: %s", err_str)
  end

  return table.concat(out)
end

local function find_git_root(dir)
  local d = dir
  while d and d ~= "" do
    if system.get_file_info(d .. PATHSEP .. ".git") then return d end
    local parent = common.dirname(d)
    if parent == d then return nil end
    d = parent
  end
end

local function fetch_head(path)
  local now = system.get_time()
  if head_fetched[path] and now - head_fetched[path] < HEAD_TTL then return end
  head_fetched[path] = now

  local git_root = find_git_root(common.dirname(path))
  if not git_root then
    head_lines[path] = NOGIT
    return
  end

  local rel = path:sub(#git_root + 2)
  local out = exec({"git", "show", "HEAD:" .. rel}, git_root)

  if out == "" then
    head_lines[path] = false
  else
    local lines = {}
    for line in (out .. "\n"):gmatch("([^\n]*)\n") do
      table.insert(lines, (line:gsub("\r$", "")))
    end
    if lines[#lines] == "" and out:sub(-1) == "\n" then
      table.remove(lines)
    end
    head_lines[path] = lines
  end
end

local function lua_diff(a, b)
  local marks = {}
  local n, m = #a, #b

  local lo = 1
  while lo <= n and lo <= m and a[lo] == b[lo] do lo = lo + 1 end

  local hi_a, hi_b = n, m
  while hi_a >= lo and hi_b >= lo and a[hi_a] == b[hi_b] do
    hi_a = hi_a - 1; hi_b = hi_b - 1
  end

  local del = hi_a - lo + 1
  local add = hi_b - lo + 1

  if add <= 0 and del <= 0 then return marks end

  if del <= 0 then
    for l = lo, hi_b do marks[l] = "add" end
    return marks
  end
  if add <= 0 then
    marks[math.max(1, lo)] = "del"
    return marks
  end

  if del * add <= 16000000 then
    local dp = {}
    local add1 = add + 1
    local total = (del + 1) * add1 - 1
    for i = 0, total do dp[i] = 0 end

    for i = 1, del do
      local ai = a[lo + i - 1]
      local i_add1 = i * add1
      local im1_add1 = (i - 1) * add1
      for j = 1, add do
        if ai == b[lo + j - 1] then
          dp[i_add1 + j] = dp[im1_add1 + j - 1] + 1
        else
          local v1 = dp[im1_add1 + j]
          local v2 = dp[i_add1 + j - 1]
          dp[i_add1 + j] = v1 > v2 and v1 or v2
        end
      end
    end

    local unchanged, lcs_size = {}, 0
    local i, j = del, add
    while i > 0 and j > 0 do
      if a[lo+i-1] == b[lo+j-1] then
        unchanged[lo+j-1] = true
        lcs_size = lcs_size + 1
        i, j = i-1, j-1
      elseif dp[(i-1)*add1 + j] >= dp[i*add1 + j-1] then
        i = i - 1
      else
        j = j - 1
      end
    end

    local mod_budget = math.min(del - lcs_size, add - lcs_size)
    for bi = lo, hi_b do
      if not unchanged[bi] then
        if mod_budget > 0 then
          marks[bi] = "mod"; mod_budget = mod_budget - 1
        else
          marks[bi] = "add"
        end
      end
    end
    if del - lcs_size > add - lcs_size then
      local del_pos = math.max(1, hi_b)
      if not marks[del_pos] then marks[del_pos] = "del" end
    end
  else
    marks[lo] = "mod"
    if hi_b > lo then marks[hi_b] = "mod" end
  end

  return marks
end

local function recompute_marks(doc)
  local path = doc.filename and system.absolute_path(doc.filename)
  if not path then doc_marks[doc] = {}; return end

  local hl = head_lines[path]
  if hl == nil or hl == NOGIT then doc_marks[doc] = {}; return end

  if hl == false then
    local marks = {}
    for i = 1, #doc.lines do marks[i] = "add" end
    doc_marks[doc] = marks
    return
  end

  local dl = {}
  for i, line in ipairs(doc.lines) do
    dl[i] = line:gsub("[\r\n]+$", "")
  end
  local full_line_count = #dl
  if #dl > 0 and dl[#dl] == "" then dl[#dl] = nil end

  local marks = lua_diff(hl, dl)
  if full_line_count > #dl and #hl < full_line_count then
    marks[full_line_count] = "add"
  end
  doc_marks[doc] = marks
end

local function on_doc_changed(doc)
  if not doc.filename then return end
  local path = system.absolute_path(doc.filename)
  if not path then return end
  local hl = head_lines[path]
  if hl == nil or hl == NOGIT then return end
  recompute_marks(doc)
  core.redraw = true
end

local orig_raw_insert = Doc.raw_insert
function Doc:raw_insert(line, col, text, undo, time)
  orig_raw_insert(self, line, col, text, undo, time)
  on_doc_changed(self)
end

local orig_raw_remove = Doc.raw_remove
function Doc:raw_remove(line1, col1, line2, col2, undo, time)
  orig_raw_remove(self, line1, col1, line2, col2, undo, time)
  on_doc_changed(self)
end

core.add_thread(function()
  while true do
    coroutine.yield(2)

    local ok, err = xpcall(function()
      local now = system.get_time()

      local function walk(node)
        if not node then return end
        if node.type == "leaf" then
          for _, v in ipairs(node.views or {}) do
            if v.is and v:is(DocView) and v.doc and v.doc.filename then
              local doc = v.doc
              local path = system.absolute_path(doc.filename)
              if not path then return end
              local stale = not head_fetched[path]
                         or now - head_fetched[path] > HEAD_TTL
              if stale then
                fetch_head(path)
                recompute_marks(doc)
                core.redraw = true
              end
            end
          end
        else
          walk(node.a); walk(node.b)
        end
      end

      if core.root_view then walk(core.root_view.root_node) end
    end, debug.traceback)

    if not ok then
      core.log("gitgutter: " .. tostring(err))
    end
  end
end)

local orig_mouse_moved = DocView.on_mouse_moved
function DocView:on_mouse_moved(x, y, ...)
  orig_mouse_moved(self, x, y, ...)
  if self.hovering_gutter then
    local _, oy = self:get_content_offset()
    self._gutter_hover_line =
      math.floor((y - oy - style.padding.y) / self:get_line_height()) + 1
  else
    self._gutter_hover_line = nil
  end
end

local orig_draw_gutter = DocView.draw_line_gutter
function DocView:draw_line_gutter(line, x, y, width)
  local lh = self:get_line_height()
  orig_draw_gutter(self, line, x, y, width)

  local marks = self.doc and doc_marks[self.doc]
  if not marks then return lh end

  local mark = marks[line]
  if not mark then return lh end

  local color   = mark == "add" and C_ADD or mark == "mod" and C_MOD or C_DEL
  local hovered = (self._gutter_hover_line == line)
  local bw      = hovered and BAR_W_WIDE or BAR_W

  renderer.draw_rect(x, y, bw, lh, color)
  return lh
end

local orig_get_gutter_width = DocView.get_gutter_width
function DocView:get_gutter_width()
  local w, pad = orig_get_gutter_width(self)
  return w + BAR_W_WIDE, pad
end
