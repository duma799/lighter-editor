local core    = require "core"
local command = require "core.command"
local keymap  = require "core.keymap"
local style   = require "core.style"
local View    = require "core.view"

local BASE16 = {
  {0x15, 0x17, 0x27, 255}, {0xf7, 0x76, 0x8e, 255},
  {0x9e, 0xce, 0x6a, 255}, {0xe0, 0xaf, 0x68, 255},
  {0x7a, 0xa2, 0xf7, 255}, {0xbb, 0x9a, 0xf7, 255},
  {0x7d, 0xcf, 0xff, 255}, {0xa9, 0xb1, 0xd6, 255},
  {0x41, 0x4e, 0x80, 255}, {0xff, 0x9e, 0x64, 255},
  {0x73, 0xda, 0xca, 255}, {0xe0, 0xaf, 0x68, 255},
  {0x7a, 0xa2, 0xf7, 255}, {0xbb, 0x9a, 0xf7, 255},
  {0x7d, 0xcf, 0xff, 255}, {0xc0, 0xca, 0xf5, 255},
}

local function utf8_width(s)
  local b = s:byte(1) or 0
  local cp
  if     b < 0x80 then cp = b
  elseif b < 0xE0 then cp = (b-0xC0)*64    + (s:byte(2)-0x80)
  elseif b < 0xF0 then cp = (b-0xE0)*4096  + (s:byte(2)-0x80)*64   + (s:byte(3)-0x80)
  else                  cp = (b-0xF0)*262144+ (s:byte(2)-0x80)*4096 + (s:byte(3)-0x80)*64 + (s:byte(4)-0x80)
  end
  if (cp>=0x1100  and cp<=0x115F)  or (cp>=0x2329  and cp<=0x232A)  or
     (cp>=0x2E80  and cp<=0x303E)  or (cp>=0x3040  and cp<=0xA4CF)  or
     (cp>=0xA960  and cp<=0xA97F)  or (cp>=0xAC00  and cp<=0xD7A3)  or
     (cp>=0xF900  and cp<=0xFAFF)  or (cp>=0xFE10  and cp<=0xFE6F)  or
     (cp>=0xFF01  and cp<=0xFF60)  or (cp>=0xFFE0  and cp<=0xFFE6)  or
     (cp>=0x1B000 and cp<=0x1B0FF) or (cp>=0x1F004 and cp<=0x1F0CF) or
     (cp>=0x1F300 and cp<=0x1F9FF) or (cp>=0x20000 and cp<=0x3FFFD) then
    return 2
  end
  return 1
end

local function palette(n)
  n = math.floor(n)
  if n < 16 then return BASE16[n + 1] end
  if n < 232 then
    local i = n - 16
    local function c(v) return v == 0 and 0 or math.floor(55 + v*40) end
    return {c(math.floor(i/36)), c(math.floor(i/6)%6), c(i%6), 255}
  end
  local v = math.floor(8 + (n-232)*10)
  return {v, v, v, 255}
end

local function COL_FG() return style.text    or {0xa9,0xb1,0xd6,255} end
local function COL_BG() return style.background or {0x0d,0x0e,0x1a,255} end

local Emu = {}
Emu.__index = Emu

function Emu.new(cols, rows)
  local self = setmetatable({}, Emu)
  self.cols, self.rows = cols, rows
  self.cur_r, self.cur_c = 1, 1
  self.saved_r, self.saved_c = 1, 1
  self.st, self.sb = 1, rows
  self.fg, self.bg = nil, nil
  self.bold, self.ul, self.rev = false, false, false
  self.state = "normal"
  self.ebuf = ""
  self.scrollback = {}
  self.scrollback_max = 2000
  self.grid = {}
  self:reset_grid()
  self.alt_grid  = nil
  self.alt_cur_r = 1
  self.alt_cur_c = 1
  self.utf8buf = ""
  self.utf8rem = 0
  return self
end

function Emu:blank_row()
  local r = {}
  for c = 1, self.cols do r[c] = {ch=" ",fg=nil,bg=nil,bold=false,ul=false} end
  return r
end

function Emu:reset_grid()
  self.grid = {}
  for r = 1, self.rows do self.grid[r] = self:blank_row() end
end

function Emu:resize(cols, rows)
  for r = 1, math.max(#self.grid, rows) do
    if not self.grid[r] then self.grid[r] = self:blank_row() end
    for c = #self.grid[r]+1, cols do
      self.grid[r][c] = {ch=" ",fg=nil,bg=nil,bold=false,ul=false}
    end
  end
  self.cols, self.rows = cols, rows
  self.st, self.sb = 1, rows
  self.cur_r = math.min(self.cur_r, rows)
  self.cur_c = math.min(self.cur_c, cols)
end

function Emu:set(r, c, ch)
  if r < 1 or r > self.rows or c < 1 or c > self.cols then return end
  self.grid[r][c] = {
    ch   = ch,
    fg   = self.rev and self.bg or self.fg,
    bg   = self.rev and self.fg or self.bg,
    bold = self.bold,
    ul   = self.ul,
  }
end

function Emu:scroll_up(n)
  for _ = 1, n do
    table.insert(self.scrollback, self.grid[self.st])
    if #self.scrollback > self.scrollback_max then table.remove(self.scrollback, 1) end
    table.remove(self.grid, self.st)
    table.insert(self.grid, self.sb, self:blank_row())
  end
end

function Emu:scroll_down(n)
  for _ = 1, n do
    table.remove(self.grid, self.sb)
    table.insert(self.grid, self.st, self:blank_row())
  end
end

function Emu:newline()
  if self.cur_r >= self.sb then self:scroll_up(1)
  else self.cur_r = self.cur_r + 1 end
end

function Emu:sgr(ps)
  local i = 1
  while i <= #ps do
    local p = ps[i]
    if     p == 0  then self.fg,self.bg,self.bold,self.ul,self.rev=nil,nil,false,false,false
    elseif p == 1  then self.bold=true
    elseif p == 4  then self.ul=true
    elseif p == 7  then self.rev=true
    elseif p == 22 then self.bold=false
    elseif p == 24 then self.ul=false
    elseif p == 27 then self.rev=false
    elseif p>=30 and p<=37 then self.fg=palette(p-30)
    elseif p==38 then
      if ps[i+1]==5 and ps[i+2] then self.fg=palette(ps[i+2]);i=i+2
      elseif ps[i+1]==2 and ps[i+4] then self.fg={ps[i+2],ps[i+3],ps[i+4],255};i=i+4 end
    elseif p==39 then self.fg=nil
    elseif p>=40 and p<=47 then self.bg=palette(p-40)
    elseif p==48 then
      if ps[i+1]==5 and ps[i+2] then self.bg=palette(ps[i+2]);i=i+2
      elseif ps[i+1]==2 and ps[i+4] then self.bg={ps[i+2],ps[i+3],ps[i+4],255};i=i+4 end
    elseif p==49 then self.bg=nil
    elseif p>=90 and p<=97  then self.fg=palette(p-90+8)
    elseif p>=100 and p<=107 then self.bg=palette(p-100+8)
    end
    i = i + 1
  end
end

function Emu:csi(seq)
  local pstr  = seq:match("^([%d;?]*)") or ""
  local final = seq:sub(#pstr+1, #pstr+1)
  local raw   = pstr:sub(1,1)=="?" and pstr:sub(2) or pstr
  local ps = {}
  for s in (raw..";"):gmatch("([^;]*);") do table.insert(ps, tonumber(s) or 0) end
  if #ps==0 then ps={0} end
  local p1,p2 = ps[1], ps[2] or 0
  local n1 = p1==0 and 1 or p1

  if     final=="A" then self.cur_r=math.max(self.st,self.cur_r-n1)
  elseif final=="B" then self.cur_r=math.min(self.sb,self.cur_r+n1)
  elseif final=="C" then self.cur_c=math.min(self.cols,self.cur_c+n1)
  elseif final=="D" then self.cur_c=math.max(1,self.cur_c-n1)
  elseif final=="E" then self.cur_r=math.min(self.rows,self.cur_r+n1);self.cur_c=1
  elseif final=="F" then self.cur_r=math.max(1,self.cur_r-n1);self.cur_c=1
  elseif final=="G" then self.cur_c=math.min(self.cols,math.max(1,n1))
  elseif final=="H" or final=="f" then
    self.cur_r=math.min(self.rows,math.max(1,p1==0 and 1 or p1))
    self.cur_c=math.min(self.cols,math.max(1,p2==0 and 1 or p2))
  elseif final=="J" then
    if p1==0 then
      for c=self.cur_c,self.cols do self:set(self.cur_r,c," ") end
      for r=self.cur_r+1,self.rows do self.grid[r]=self:blank_row() end
    elseif p1==1 then
      for r=1,self.cur_r-1 do self.grid[r]=self:blank_row() end
      for c=1,self.cur_c do self:set(self.cur_r,c," ") end
    elseif p1==2 or p1==3 then
      self:reset_grid()
      if p1==2 then self.cur_r,self.cur_c=1,1 end
    end
  elseif final=="K" then
    if     p1==0 then for c=self.cur_c,self.cols do self:set(self.cur_r,c," ") end
    elseif p1==1 then for c=1,self.cur_c do self:set(self.cur_r,c," ") end
    elseif p1==2 then self.grid[self.cur_r]=self:blank_row()
    end
  elseif final=="L" then
    for _=1,n1 do table.remove(self.grid,self.sb);table.insert(self.grid,self.cur_r,self:blank_row()) end
  elseif final=="M" then
    for _=1,n1 do table.remove(self.grid,self.cur_r);table.insert(self.grid,self.sb,self:blank_row()) end
  elseif final=="P" then
    local row=self.grid[self.cur_r]
    for c=self.cur_c,self.cols-n1 do row[c]=row[c+n1] or {ch=" ",fg=nil,bg=nil,bold=false,ul=false} end
    for c=self.cols-n1+1,self.cols do row[c]={ch=" ",fg=nil,bg=nil,bold=false,ul=false} end
  elseif final=="S" then self:scroll_up(n1)
  elseif final=="T" then self:scroll_down(n1)
  elseif final=="X" then
    for c=self.cur_c,math.min(self.cur_c+n1-1,self.cols) do self:set(self.cur_r,c," ") end
  elseif final=="d" then self.cur_r=math.min(self.rows,math.max(1,n1))
  elseif final=="m" then self:sgr(ps)
  elseif final=="r" then
    self.st=p1==0 and 1 or p1; self.sb=p2==0 and self.rows or p2
    self.cur_r,self.cur_c=1,1
  elseif final=="s" then self.saved_r,self.saved_c=self.cur_r,self.cur_c
  elseif final=="u" then self.cur_r,self.cur_c=self.saved_r,self.saved_c
  elseif final=="h" then
    if p1==1049 then  -- enter alternate screen
      self.alt_grid  = self.grid
      self.alt_cur_r = self.cur_r
      self.alt_cur_c = self.cur_c
      self.grid = {}
      for r = 1, self.rows do self.grid[r] = self:blank_row() end
      self.cur_r, self.cur_c = 1, 1
    end
  elseif final=="l" then
    if p1==1049 then  -- exit alternate screen
      if self.alt_grid then
        self.grid  = self.alt_grid
        self.cur_r = self.alt_cur_r
        self.cur_c = self.alt_cur_c
        self.alt_grid = nil
      end
    end
  elseif final=="@" then
    local row=self.grid[self.cur_r]
    for c=self.cols,self.cur_c+n1,-1 do row[c]=row[c-n1] or {ch=" ",fg=nil,bg=nil,bold=false,ul=false} end
    for c=self.cur_c,self.cur_c+n1-1 do row[c]={ch=" ",fg=nil,bg=nil,bold=false,ul=false} end
  end
end

function Emu:write(data)
  local i = 1
  while i <= #data do
    local ch = data:sub(i,i)
    local b  = ch:byte()

    if self.state=="normal" then
      if     b==27 then self.state="esc"; self.ebuf=""
      elseif b==13 then self.cur_c=1
      elseif b==10 or b==11 or b==12 then self:newline()
      elseif b==8  then self.cur_c=math.max(1,self.cur_c-1)
      elseif b==9  then self.cur_c=math.min(self.cols,math.floor((self.cur_c-1)/8)*8+9)
      elseif b==7 or b==0 then  -- BEL/NUL ignore
      elseif b>=0xC0 then  -- UTF-8 lead byte (2-4 byte sequence)
        self.utf8buf = ch
        self.utf8rem = b>=0xF0 and 3 or b>=0xE0 and 2 or 1
      elseif b>=0x80 then  -- UTF-8 continuation byte
        if self.utf8rem > 0 then
          self.utf8buf = self.utf8buf .. ch
          self.utf8rem = self.utf8rem - 1
          if self.utf8rem == 0 then
            local w = utf8_width(self.utf8buf)
            self:set(self.cur_r, self.cur_c, self.utf8buf)
            if w == 2 and self.cur_c + 1 <= self.cols then
              -- blank the second half-cell so old content doesn't bleed through
              self.grid[self.cur_r][self.cur_c + 1] = {ch=" ",fg=nil,bg=nil,bold=false,ul=false}
            end
            self.cur_c = self.cur_c + w
            if self.cur_c > self.cols then self.cur_c=1; self:newline() end
            self.utf8buf = ""
          end
        end
      elseif b>=32 then
        self.utf8buf = ""; self.utf8rem = 0
        self:set(self.cur_r,self.cur_c,ch)
        self.cur_c=self.cur_c+1
        if self.cur_c>self.cols then self.cur_c=1; self:newline() end
      end
    elseif self.state=="esc" then
      if     ch=="[" then self.state="csi"; self.ebuf=""
      elseif ch=="]" then self.state="osc"; self.ebuf=""
      elseif ch=="(" or ch==")" or ch=="*" or ch=="+" then self.state="cset"
      elseif ch=="7" then self.saved_r,self.saved_c=self.cur_r,self.cur_c; self.state="normal"
      elseif ch=="8" then self.cur_r,self.cur_c=self.saved_r,self.saved_c; self.state="normal"
      elseif ch=="M" then
        if self.cur_r==self.st then self:scroll_down(1) else self.cur_r=math.max(1,self.cur_r-1) end
        self.state="normal"
      elseif ch=="c" then
        self:reset_grid(); self.cur_r,self.cur_c=1,1
        self.fg,self.bg,self.bold,self.ul,self.rev=nil,nil,false,false,false
        self.st,self.sb=1,self.rows; self.state="normal"
      else self.state="normal" end
    elseif self.state=="cset" then self.state="normal"
    elseif self.state=="csi" then
      if b>=0x40 and b<=0x7E then
        self:csi(self.ebuf..ch); self.state="normal"; self.ebuf=""
      else
        self.ebuf=self.ebuf..ch
        if #self.ebuf>256 then self.state="normal"; self.ebuf="" end
      end
    elseif self.state=="osc" then
      if b==7 then self.state="normal"; self.ebuf=""
      elseif b==27 then self.state="osc_st"
      else
        self.ebuf=self.ebuf..ch
        if #self.ebuf>512 then self.state="normal"; self.ebuf="" end
      end
    elseif self.state=="osc_st" then
      self.state="normal"; self.ebuf=""
    end

    i = i + 1
  end
end

local TermView = View:extend()

local PAD       = math.floor(6 * (SCALE or 1))
local DIVIDER_H = math.floor(20 * (SCALE or 1))
local BTN_W     = math.floor(20 * (SCALE or 1))

function TermView:new()
  TermView.super.new(self)
  self.visible     = false
  self.init_size   = true
  self.target_size = math.floor(220 * (SCALE or 1))
  self.sb_offset   = 0
  self.proc        = nil
  self.emu         = nil
  self.cols        = 80
  self.rows        = 24
  self._prev_cols  = 0
  self._prev_rows  = 0
end

function TermView:get_name() return "Terminal" end

function TermView:set_target_size(axis, value)
  if axis == "y" then self.target_size = value; return true end
end

function TermView:font()
  if not self._term_font then
    local base = style.code_font or style.font
    local fallback_path = "/System/Library/Fonts/Apple Symbols.ttf"
    local f = io.open(fallback_path, "r")
    if f then
      f:close()
      local size = base:get_size()
      local fb = renderer.font.load(fallback_path, size, { antialiasing = "subpixel", hinting = "slight" })
      self._term_font = renderer.font.group({ base, fb })
    else
      self._term_font = base
    end
  end
  return self._term_font
end

function TermView:cell_wh()
  local f = self:font()
  return f:get_width("M"), math.ceil(f:get_height() * 1.2)
end

function TermView:start_shell()
  local shell = os.getenv("SHELL") or "/bin/zsh"
  local cwd   = core.project_dir or os.getenv("HOME")
  local py = "import pty,os,sys; os.environ.setdefault('TERM','xterm-256color'); pty.spawn(sys.argv[1:])"
  local ok, res = pcall(process.start,
    {"/usr/bin/python3", "-c", py, shell, "--login", "-i"},
    { cwd = cwd }
  )
  if not ok or not res then
    ok, res = pcall(process.start,
      {"/usr/bin/env", "python3", "-c", py, shell, "--login", "-i"},
      { cwd = cwd }
    )
  end
  if not ok or not res then
    core.error("[Terminal] Could not start shell: %s", tostring(res))
    return
  end
  self.proc = res
  self.emu  = Emu.new(self.cols, self.rows)
  core.add_thread(function()
    while self.proc do
      if not self.proc:running() then
        if self.emu then self.emu:write("\r\n\027[90m[process exited]\027[0m\r\n") end
        self.proc = nil; core.redraw = true; return
      end
      local chunk = self.proc:read_stdout()
      if not chunk or chunk=="" then chunk = self.proc:read_stderr() end
      if chunk and chunk~="" then
        self.emu:write(chunk); core.redraw = true
      else
        coroutine.yield(0.016)
      end
    end
  end)
end

function TermView:send(data)
  if self.proc and self.proc:running() then
    pcall(function() self.proc:write(data) end)
    self.sb_offset = 0
  end
end

function TermView:update()
  local dest = self.visible and self.target_size or 0
  if self.init_size then
    self.size.y = dest; self.init_size = false
  else
    self:move_towards(self.size, "y", dest, nil, "terminal")
  end

  if not self.visible or self.size.y < 4 then return end

  if self.emu then
    local fw, fh = self:cell_wh()
    local nc = math.max(1, math.floor((self.size.x - PAD*2) / fw))
    local nr = math.max(1, math.floor((self.size.y - DIVIDER_H - PAD*2) / fh))
    if nc ~= self._prev_cols or nr ~= self._prev_rows then
      self._prev_cols, self._prev_rows = nc, nr
      self.cols, self.rows = nc, nr
      self.emu:resize(nc, nr)
    end
  end

  TermView.super.update(self)
end

function TermView:restart_shell()
  if self.proc then
    pcall(function() self.proc:kill() end)
    self.proc = nil
  end
  self.emu = nil
  self._prev_cols, self._prev_rows = 0, 0
  self.sb_offset = 0
  self:start_shell()
end

function TermView:draw()
  if self.size.y < 2 then return end
  self:draw_background(COL_BG())

  local dx, dy = self.position.x, self.position.y
  local dw = self.size.x
  local divider_bg = (self._divider_hover or self._dragging)
    and (style.background3 or style.background2 or COL_BG())
    or  (style.background2 or COL_BG())
  renderer.draw_rect(dx, dy, dw, DIVIDER_H, divider_bg)
  local divider_line = (self._divider_hover or self._dragging)
    and (style.accent or style.dim)
    or  (style.divider or style.dim)
  renderer.draw_rect(dx, dy, dw, 1, divider_line)

  local bx = dx + dw - BTN_W - PAD
  local ui_font = style.font or style.code_font
  local label = "\u{21BB}"  -- ↻
  local hover = self._restart_hover
  local col = hover and (style.text or {0xff,0xff,0xff,255}) or (style.dim or {0x70,0x78,0x98,255})
  local lw = ui_font:get_width(label)
  local lh = ui_font:get_height()
  renderer.draw_text(ui_font, label,
    bx + math.floor((BTN_W - lw) / 2),
    dy + math.floor((DIVIDER_H - lh) / 2),
    col)

  self._restart_rect = { x = bx, y = dy, w = BTN_W, h = DIVIDER_H }

  if not self.emu or not self.visible or self.size.y < DIVIDER_H + PAD*2 + 4 then return end

  local font = self:font()
  local fw, fh = self:cell_wh()
  local rows = self.emu.rows
  local sb   = self.emu.scrollback
  local off  = math.min(self.sb_offset, #sb)

  local content_y = self.position.y + DIVIDER_H
  local content_h = self.size.y - DIVIDER_H
  core.push_clip_rect(self.position.x, content_y, self.size.x, content_h)

  for vr = 1, rows do
    local y = content_y + PAD + (vr-1)*fh
    local row_data
    if off > 0 then
      local si = #sb - off + vr
      if si >= 1 and si <= #sb then row_data = sb[si]
      elseif vr > off then row_data = self.emu.grid[vr-off] end
    else
      row_data = self.emu.grid[vr]
    end
    if row_data then
      for vc = 1, self.emu.cols do
        local cell = row_data[vc]
        if cell then
          local x = self.position.x + PAD + (vc-1)*fw
          if cell.bg then
            renderer.draw_rect(x, y, fw, fh, cell.bg)
          end
          -- cursor
          if off==0 and vr==self.emu.cur_r and vc==self.emu.cur_c
             and core.active_view==self then
            local cc = style.caret or {166, 166, 217, 255}
            renderer.draw_rect(x, y, fw, fh, {cc[1], cc[2], cc[3], 217})
          end
          local ch = cell.ch or " "
          if ch ~= " " then
            local fg = cell.fg or COL_FG()
            renderer.draw_text(font, ch, x, y+math.floor((fh-font:get_height())*0.5), fg)
          end
          if cell.ul then
            renderer.draw_rect(x, y+fh-1, fw, 1, cell.fg or COL_FG())
          end
        end
      end
    end
  end

  core.pop_clip_rect()
end

local KEY_SEQS = {
  ["return"]="  \r", ["tab"]="\t", ["escape"]="\027", ["backspace"]="\127",
  ["delete"]="\027[3~",
  ["up"]="\027[A", ["down"]="\027[B", ["right"]="\027[C", ["left"]="\027[D",
  ["home"]="\027[H", ["end"]="\027[F",
  ["pageup"]="\027[5~", ["pagedown"]="\027[6~",
  ["f1"]="\027OP",  ["f2"]="\027OQ",  ["f3"]="\027OR",  ["f4"]="\027OS",
  ["f5"]="\027[15~",["f6"]="\027[17~",["f7"]="\027[18~",["f8"]="\027[19~",
  ["f9"]="\027[20~",["f10"]="\027[21~",["f11"]="\027[23~",["f12"]="\027[24~",
}
KEY_SEQS["return"] = "\r"

function TermView:on_mouse_moved(x, y, ...)
  if self._dragging then
    local delta = self._drag_start_y - y
    self.target_size = math.max(DIVIDER_H + 40, self._drag_start_size + delta)
    self.size.y = self.target_size
    core.redraw = true
    return true
  end

  local on_divider = self.visible
    and y >= self.position.y and y < self.position.y + DIVIDER_H
    and x >= self.position.x and x < self.position.x + self.size.x

  local r = self._restart_rect
  local hover = r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
  if hover ~= self._restart_hover or on_divider ~= self._divider_hover then
    self._restart_hover = hover
    self._divider_hover = on_divider
    core.redraw = true
  end
  return TermView.super.on_mouse_moved(self, x, y, ...)
end

function TermView:on_mouse_pressed(button, x, y, clicks)
  local r = self._restart_rect
  if r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
    self:restart_shell()
    return true
  end
  if self.visible and y >= self.position.y and y < self.position.y + DIVIDER_H then
    self._dragging = true
    self._drag_start_y = y
    self._drag_start_size = self.size.y
    return true
  end
  core.set_active_view(self)
  return TermView.super.on_mouse_pressed(self, button, x, y, clicks)
end

function TermView:on_mouse_released(button, x, y)
  if self._dragging then
    self._dragging = false
    return true
  end
  return TermView.super.on_mouse_released and TermView.super.on_mouse_released(self, button, x, y)
end

function TermView:on_text_input(text)
  if self.visible and core.active_view == self then self:send(text) end
end

function TermView:on_key_pressed(key)
  if not self.visible or core.active_view ~= self then return false end
  local skip = { ["backspace"]=1,["delete"]=1,["return"]=1,["tab"]=1,
                 ["escape"]=1,["up"]=1,["down"]=1,["left"]=1,["right"]=1 }
  if skip[key] then return false end
  local seq = KEY_SEQS[key]
  if seq then self:send(seq); return true end
  return false
end

function TermView:on_mouse_wheel(dy)
  if not self.visible or not self.emu then return end
  if dy > 0 then
    self.sb_offset = math.min(self.sb_offset+3, #self.emu.scrollback)
  else
    self.sb_offset = math.max(0, self.sb_offset-3)
  end
  core.redraw = true
  return true
end

local term_view = TermView()
local term_node = nil

local function ensure_node()
  if term_node and term_node.views then return end
  local node = core.root_view:get_primary_node()
  term_node = node:split("down", term_view, {y=true})
end

command.add(nil, {
  ["lighter:terminal-toggle"] = function()
    if term_view.visible then
      term_view.visible = false
      local prev = core.last_active_view
      if prev and prev ~= term_view then
        core.set_active_view(prev)
      end
    else
      ensure_node()
      term_view.visible  = true
      term_view.init_size = true
      if not term_view.proc then term_view:start_shell() end
      core.set_active_view(term_view)
    end
    core.redraw = true
  end,
})

local function term_active()
  return term_view.visible and core.active_view == term_view
end

command.add(term_active, {
  ["terminal:backspace"]  = function() term_view:send("\x7f") end,
  ["terminal:delete"]     = function() term_view:send("\027[3~") end,
  ["terminal:return"]     = function() term_view:send("\r") end,
  ["terminal:tab"]        = function() term_view:send("\t") end,
  ["terminal:escape"]     = function() term_view:send("\027") end,
  ["terminal:up"]         = function() term_view:send("\027[A") end,
  ["terminal:down"]       = function() term_view:send("\027[B") end,
  ["terminal:right"]      = function() term_view:send("\027[C") end,
  ["terminal:left"]       = function() term_view:send("\027[D") end,
  ["terminal:ctrl-c"] = function() term_view:send("\x03") end,
  ["terminal:ctrl-d"] = function() term_view:send("\x04") end,
  ["terminal:ctrl-l"] = function() term_view:send("\x0c") end,
  ["terminal:ctrl-z"] = function() term_view:send("\x1a") end,
  ["terminal:ctrl-a"] = function() term_view:send("\x01") end,
  ["terminal:ctrl-e"] = function() term_view:send("\x05") end,
  ["terminal:ctrl-k"] = function() term_view:send("\x0b") end,
  ["terminal:ctrl-u"] = function() term_view:send("\x15") end,
  ["terminal:ctrl-w"] = function() term_view:send("\x17") end,
  ["terminal:ctrl-b"] = function() term_view:send("\x02") end,
  ["terminal:ctrl-f"] = function() term_view:send("\x06") end,
  ["terminal:ctrl-t"] = function() term_view:send("\x14") end,
  ["terminal:ctrl-p"] = function() term_view:send("\x10") end,
  ["terminal:ctrl-r"] = function() term_view:send("\x12") end,
  ["terminal:paste"] = function()
    local text = system.get_clipboard()
    if text and text ~= "" then term_view:send(text) end
  end,
})

keymap.add({
  ["backspace"] = "terminal:backspace",
  ["delete"]    = "terminal:delete",
  ["return"]    = "terminal:return",
  ["tab"]       = "terminal:tab",
  ["escape"]    = "terminal:escape",
  ["up"]        = "terminal:up",
  ["down"]      = "terminal:down",
  ["right"]     = "terminal:right",
  ["left"]      = "terminal:left",
  ["ctrl+c"] = "terminal:ctrl-c",
  ["ctrl+d"] = "terminal:ctrl-d",
  ["ctrl+l"] = "terminal:ctrl-l",
  ["ctrl+z"] = "terminal:ctrl-z",
  ["ctrl+a"] = "terminal:ctrl-a",
  ["ctrl+e"] = "terminal:ctrl-e",
  ["ctrl+k"] = "terminal:ctrl-k",
  ["ctrl+u"] = "terminal:ctrl-u",
  ["ctrl+w"] = "terminal:ctrl-w",
  ["ctrl+b"] = "terminal:ctrl-b",
  ["ctrl+f"] = "terminal:ctrl-f",
  ["ctrl+t"] = "terminal:ctrl-t",
  ["ctrl+p"] = "terminal:ctrl-p",
  ["ctrl+r"] = "terminal:ctrl-r",
  ["cmd+v"]  = "terminal:paste",
})

return term_view
