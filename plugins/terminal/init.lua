local core    = require "core"
local command = require "core.command"
local keymap  = require "core.keymap"
local style   = require "core.style"
local View    = require "core.view"

local pty = require "lighter.native.pty"

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

---------------------------------------------------------------------------
-- Emu: VT100/xterm-256color terminal emulator
---------------------------------------------------------------------------
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
  self.italic, self.strike, self.dim = false, false, false
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
  -- mode flags
  self.cursor_visible = true     -- DECTCEM (mode 25)
  self.cursor_key_mode = false   -- DECCKM (mode 1): false = normal, true = application
  self.bracketed_paste = false   -- mode 2004
  self.autowrap = true           -- DECAWM (mode 7)
  self.focus_events = false      -- mode 1004
  self.mouse_track = "off"       -- "off" | "click" (1000) | "drag" (1002) | "any" (1003)
  self.mouse_enc   = "x10"       -- "x10" (legacy) | "sgr" (1006)
  self.wrap_pending = false      -- xterm last-column deferred wrap
  self.cursor_shape = "block"    -- "block" | "underline" | "bar"
  self.cursor_blink = true       -- DECSCUSR parity (render side may ignore)
  return self
end

function Emu:blank_row()
  local r = {}
  for c = 1, self.cols do r[c] = {ch=" ",fg=nil,bg=nil,bold=false,ul=false,italic=false,strike=false,dim=false} end
  return r
end

-- Background Color Erase: produce a blank row filled with the current bg.
function Emu:blank_row_bce()
  local bg = self.bg
  if bg == nil then return self:blank_row() end
  local r = {}
  for c = 1, self.cols do r[c] = {ch=" ",fg=nil,bg=bg,bold=false,ul=false,italic=false,strike=false,dim=false} end
  return r
end

function Emu:reset_grid()
  self.grid = {}
  for r = 1, self.rows do self.grid[r] = self:blank_row() end
end

function Emu:resize(cols, rows)
  -- grow or pad existing rows to new column count
  for r = 1, math.min(#self.grid, rows) do
    for c = #self.grid[r]+1, cols do
      self.grid[r][c] = {ch=" ",fg=nil,bg=nil,bold=false,ul=false,italic=false,strike=false,dim=false}
    end
  end
  -- add missing rows
  for r = #self.grid+1, rows do
    self.grid[r] = self:blank_row()
  end
  -- trim excess rows so the grid has exactly `rows` entries
  while #self.grid > rows do
    table.remove(self.grid)
  end
  self.cols, self.rows = cols, rows
  self.st, self.sb = 1, rows
  self.cur_r = math.min(self.cur_r, rows)
  self.cur_c = math.min(self.cur_c, cols)
end

function Emu:set(r, c, ch)
  if r < 1 or r > self.rows or c < 1 or c > self.cols then return end
  self.grid[r][c] = {
    ch     = ch,
    fg     = self.rev and self.bg or self.fg,
    bg     = self.rev and self.fg or self.bg,
    bold   = self.bold,
    ul     = self.ul,
    italic = self.italic,
    strike = self.strike,
    dim    = self.dim,
  }
end

function Emu:scroll_up(n)
  for _ = 1, n do
    -- only save to scrollback on the main screen, not the alternate screen
    if not self.alt_grid then
      table.insert(self.scrollback, self.grid[self.st])
      if #self.scrollback > self.scrollback_max then table.remove(self.scrollback, 1) end
    end
    table.remove(self.grid, self.st)
    table.insert(self.grid, self.sb, self:blank_row_bce())
  end
end

function Emu:scroll_down(n)
  for _ = 1, n do
    table.remove(self.grid, self.sb)
    table.insert(self.grid, self.st, self:blank_row_bce())
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
    if     p == 0  then
      self.fg,self.bg=nil,nil
      self.bold,self.ul,self.rev=false,false,false
      self.italic,self.strike,self.dim=false,false,false
    elseif p == 1  then self.bold=true
    elseif p == 2  then self.dim=true
    elseif p == 3  then self.italic=true
    elseif p == 4  then self.ul=true
    elseif p == 7  then self.rev=true
    elseif p == 9  then self.strike=true
    elseif p == 22 then self.bold=false; self.dim=false
    elseif p == 23 then self.italic=false
    elseif p == 24 then self.ul=false
    elseif p == 27 then self.rev=false
    elseif p == 29 then self.strike=false
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

-- DA response callback: set by TermView so Emu can send replies back to the PTY
Emu.reply = nil
-- Set by TermView: called with the new window title string.
Emu.on_title = nil
-- Set by TermView: called with decoded clipboard text (OSC 52 "set" op).
Emu.on_clipboard_set = nil
-- Set by TermView: called with no args, must return clipboard text (OSC 52 "get" op).
Emu.on_clipboard_get = nil

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64IDX = {}
for i = 1, #B64 do B64IDX[B64:byte(i)] = i - 1 end

local function b64_decode(s)
  s = s:gsub("[^A-Za-z0-9+/=]", "")
  local out = {}
  for i = 1, #s, 4 do
    local a = B64IDX[s:byte(i)]     or 0
    local b = B64IDX[s:byte(i+1)]   or 0
    local c = s:byte(i+2) and B64IDX[s:byte(i+2)] or 0
    local d = s:byte(i+3) and B64IDX[s:byte(i+3)] or 0
    local n = a*262144 + b*4096 + c*64 + d
    out[#out+1] = string.char(math.floor(n/65536) % 256)
    if s:byte(i+2) and s:sub(i+2,i+2) ~= "=" then
      out[#out+1] = string.char(math.floor(n/256) % 256)
    end
    if s:byte(i+3) and s:sub(i+3,i+3) ~= "=" then
      out[#out+1] = string.char(n % 256)
    end
  end
  return table.concat(out)
end

local function b64_encode(s)
  local out = {}
  for i = 1, #s, 3 do
    local a = s:byte(i) or 0
    local b = s:byte(i+1) or 0
    local c = s:byte(i+2) or 0
    local n = a*65536 + b*256 + c
    out[#out+1] = B64:sub(math.floor(n/262144)+1, math.floor(n/262144)+1)
    out[#out+1] = B64:sub(math.floor(n/4096)%64+1, math.floor(n/4096)%64+1)
    out[#out+1] = s:byte(i+1) and B64:sub(math.floor(n/64)%64+1, math.floor(n/64)%64+1) or "="
    out[#out+1] = s:byte(i+2) and B64:sub(n%64+1, n%64+1) or "="
  end
  return table.concat(out)
end

function Emu:osc(payload)
  local ps, rest = payload:match("^(%d+);(.*)$")
  if not ps then return end
  local code = tonumber(ps)
  if code == 0 or code == 2 then
    -- Set icon name + window title / set window title
    if self.on_title then self.on_title(rest) end
  elseif code == 52 then
    -- Manipulate selection data: "52;<selection>;<base64|?>"
    local sel, data = rest:match("^([^;]*);(.*)$")
    if not data then return end
    if data == "?" then
      if self.on_clipboard_get and self.reply then
        local text = self.on_clipboard_get() or ""
        self.reply(string.format("\027]52;%s;%s\027\\", sel, b64_encode(text)))
      end
    else
      if self.on_clipboard_set then
        local ok, decoded = pcall(b64_decode, data)
        if ok then self.on_clipboard_set(decoded) end
      end
    end
  end
end

function Emu:csi(seq)
  local pstr  = seq:match("^([%d;?]*)") or ""
  local final = seq:sub(#pstr+1, #pstr+1)
  local is_private = pstr:sub(1,1) == "?"
  local raw   = is_private and pstr:sub(2) or pstr
  local ps = {}
  for s in (raw..";"):gmatch("([^;]*);") do table.insert(ps, tonumber(s) or 0) end
  if #ps==0 then ps={0} end
  local p1,p2 = ps[1], ps[2] or 0
  local n1 = p1==0 and 1 or p1
  -- Any CSI that touches cursor or screen breaks deferred-wrap state
  self.wrap_pending = false

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
      for r=self.cur_r+1,self.rows do self.grid[r]=self:blank_row_bce() end
    elseif p1==1 then
      for r=1,self.cur_r-1 do self.grid[r]=self:blank_row_bce() end
      for c=1,self.cur_c do self:set(self.cur_r,c," ") end
    elseif p1==2 or p1==3 then
      for r=1,self.rows do self.grid[r]=self:blank_row_bce() end
      if p1==2 then self.cur_r,self.cur_c=1,1 end
    end
  elseif final=="K" then
    if     p1==0 then for c=self.cur_c,self.cols do self:set(self.cur_r,c," ") end
    elseif p1==1 then for c=1,self.cur_c do self:set(self.cur_r,c," ") end
    elseif p1==2 then self.grid[self.cur_r]=self:blank_row_bce()
    end
  elseif final=="L" then
    for _=1,n1 do table.remove(self.grid,self.sb);table.insert(self.grid,self.cur_r,self:blank_row_bce()) end
  elseif final=="M" then
    for _=1,n1 do table.remove(self.grid,self.cur_r);table.insert(self.grid,self.sb,self:blank_row_bce()) end
  elseif final=="P" then
    local row=self.grid[self.cur_r]
    local fill = function() return {ch=" ",fg=nil,bg=self.bg,bold=false,ul=false,italic=false,strike=false,dim=false} end
    for c=self.cur_c,self.cols-n1 do row[c]=row[c+n1] or fill() end
    for c=self.cols-n1+1,self.cols do row[c]=fill() end
  elseif final=="S" then self:scroll_up(n1)
  elseif final=="T" then self:scroll_down(n1)
  elseif final=="X" then
    for c=self.cur_c,math.min(self.cur_c+n1-1,self.cols) do self:set(self.cur_r,c," ") end
  elseif final=="d" then self.cur_r=math.min(self.rows,math.max(1,n1))
  elseif final=="m" then self:sgr(ps)
  elseif final=="n" then
    -- Device Status Report
    if p1 == 6 and self.reply then
      self.reply(string.format("\027[%d;%dR", self.cur_r, self.cur_c))
    end
  elseif final=="c" then
    -- Device Attributes (DA1)
    if not is_private and self.reply then
      self.reply("\027[?62;22c")  -- VT220 with ANSI color
    end
  elseif final=="r" then
    self.st=p1==0 and 1 or p1; self.sb=p2==0 and self.rows or p2
    self.cur_r,self.cur_c=1,1
  elseif final=="s" then self.saved_r,self.saved_c=self.cur_r,self.cur_c
  elseif final=="u" then self.cur_r,self.cur_c=self.saved_r,self.saved_c
  elseif final=="h" then
    -- Set Mode
    if is_private then
      for _, m in ipairs(ps) do
        if     m == 1    then self.cursor_key_mode = true
        elseif m == 7    then self.autowrap = true
        elseif m == 25   then self.cursor_visible = true
        elseif m == 47 or m == 1047 or m == 1049 then
          if not self.alt_grid then
            self.alt_grid  = self.grid
            self.alt_cur_r = self.cur_r
            self.alt_cur_c = self.cur_c
            self.grid = {}
            for r = 1, self.rows do self.grid[r] = self:blank_row() end
            self.cur_r, self.cur_c = 1, 1
          end
        elseif m == 1048 then
          self.saved_r, self.saved_c = self.cur_r, self.cur_c
        elseif m == 1000 then self.mouse_track = "click"
        elseif m == 1002 then self.mouse_track = "drag"
        elseif m == 1003 then self.mouse_track = "any"
        elseif m == 1006 then self.mouse_enc = "sgr"
        elseif m == 1004 then self.focus_events = true
        elseif m == 2004 then self.bracketed_paste = true
        end
      end
    end
  elseif final=="l" then
    -- Reset Mode
    if is_private then
      for _, m in ipairs(ps) do
        if     m == 1    then self.cursor_key_mode = false
        elseif m == 7    then self.autowrap = false
        elseif m == 25   then self.cursor_visible = false
        elseif m == 47 or m == 1047 or m == 1049 then
          if self.alt_grid then
            self.grid  = self.alt_grid
            self.cur_r = self.alt_cur_r
            self.cur_c = self.alt_cur_c
            self.alt_grid = nil
          end
        elseif m == 1048 then
          self.cur_r, self.cur_c = self.saved_r, self.saved_c
        elseif m == 1000 or m == 1002 or m == 1003 then self.mouse_track = "off"
        elseif m == 1006 then self.mouse_enc = "x10"
        elseif m == 1004 then self.focus_events = false
        elseif m == 2004 then self.bracketed_paste = false
        end
      end
    end
  elseif final=="@" then
    local row=self.grid[self.cur_r]
    local fill = function() return {ch=" ",fg=nil,bg=self.bg,bold=false,ul=false,italic=false,strike=false,dim=false} end
    for c=self.cols,self.cur_c+n1,-1 do row[c]=row[c-n1] or fill() end
    for c=self.cur_c,self.cur_c+n1-1 do row[c]=fill() end
  elseif final=="q" and seq:find(" q", 1, true) then
    -- DECSCUSR: CSI Ps SP q
    local n = p1
    if     n == 0 or n == 1 then self.cursor_shape, self.cursor_blink = "block", true
    elseif n == 2            then self.cursor_shape, self.cursor_blink = "block", false
    elseif n == 3            then self.cursor_shape, self.cursor_blink = "underline", true
    elseif n == 4            then self.cursor_shape, self.cursor_blink = "underline", false
    elseif n == 5            then self.cursor_shape, self.cursor_blink = "bar", true
    elseif n == 6            then self.cursor_shape, self.cursor_blink = "bar", false
    end
  end
end

function Emu:write(data)
  local i = 1
  while i <= #data do
    local ch = data:sub(i,i)
    local b  = ch:byte()

    if self.state=="normal" then
      if     b==27 then self.state="esc"; self.ebuf=""
      elseif b==13 then self.cur_c=1; self.wrap_pending=false
      elseif b==10 or b==11 or b==12 then self:newline(); self.wrap_pending=false
      elseif b==8  then self.cur_c=math.max(1,self.cur_c-1); self.wrap_pending=false
      elseif b==9  then
        self.cur_c=math.min(self.cols,math.floor((self.cur_c-1)/8)*8+9)
        self.wrap_pending=false
      elseif b==7 or b==0 then  -- BEL/NUL ignore
      elseif b>=0xC0 then  -- UTF-8 lead byte
        self.utf8buf = ch
        self.utf8rem = b>=0xF0 and 3 or b>=0xE0 and 2 or 1
      elseif b>=0x80 then  -- UTF-8 continuation byte
        if self.utf8rem > 0 then
          self.utf8buf = self.utf8buf .. ch
          self.utf8rem = self.utf8rem - 1
          if self.utf8rem == 0 then
            local w = utf8_width(self.utf8buf)
            -- deferred wrap: consume pending wrap before the next printable char
            if self.wrap_pending and self.autowrap then
              self.cur_c = 1; self:newline(); self.wrap_pending = false
            end
            self:set(self.cur_r, self.cur_c, self.utf8buf)
            if w == 2 and self.cur_c + 1 <= self.cols then
              self.grid[self.cur_r][self.cur_c + 1] = {ch=" ",fg=nil,bg=nil,bold=false,ul=false,italic=false,strike=false,dim=false}
            end
            if self.cur_c + w - 1 >= self.cols then
              -- cursor stays at the last column; next printable char will wrap
              self.cur_c = self.cols
              if self.autowrap then self.wrap_pending = true end
            else
              self.cur_c = self.cur_c + w
            end
            self.utf8buf = ""
          end
        end
      elseif b>=32 then
        self.utf8buf = ""; self.utf8rem = 0
        if self.wrap_pending and self.autowrap then
          self.cur_c = 1; self:newline(); self.wrap_pending = false
        end
        self:set(self.cur_r,self.cur_c,ch)
        if self.cur_c >= self.cols then
          self.cur_c = self.cols
          if self.autowrap then self.wrap_pending = true end
        else
          self.cur_c = self.cur_c + 1
        end
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
        self.st,self.sb=1,self.rows
        self.cursor_visible=true; self.cursor_key_mode=false
        self.bracketed_paste=false; self.autowrap=true
        self.state="normal"
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
      if b==7 then self:osc(self.ebuf); self.state="normal"; self.ebuf=""
      elseif b==27 then self.state="osc_st"
      else
        self.ebuf=self.ebuf..ch
        -- OSC 52 carries clipboard payloads that can be large; allow up to ~1 MiB.
        if #self.ebuf>1048576 then self.state="normal"; self.ebuf="" end
      end
    elseif self.state=="osc_st" then
      -- We saw ESC inside an OSC; the expected terminator is ESC \ (String Terminator).
      self:osc(self.ebuf); self.state="normal"; self.ebuf=""
    end

    i = i + 1
  end
end

---------------------------------------------------------------------------
-- TermView
---------------------------------------------------------------------------
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
  self.pty_handle  = nil
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

function TermView:italic_font()
  if self._term_italic_font ~= nil then return self._term_italic_font end
  -- look for an italic variant next to the main font
  local candidates = {
    (USERDIR or "") .. "/fonts/JetBrainsMonoNerdFontMono-BoldItalic.ttf",
    (USERDIR or "") .. "/fonts/MesloLGSNerdFontMono-Italic.ttf",
    (USERDIR or "") .. "/fonts/MesloLGSNerdFont-Italic.ttf",
  }
  local base = style.code_font or style.font
  local size = base:get_size()
  for _, path in ipairs(candidates) do
    local f = io.open(path, "r")
    if f then
      f:close()
      self._term_italic_font = renderer.font.load(path, size, { antialiasing = "subpixel", hinting = "slight" })
      return self._term_italic_font
    end
  end
  self._term_italic_font = false  -- sentinel: searched, none found
  return false
end

function TermView:cell_wh()
  local f = self:font()
  return f:get_width("M"), math.ceil(f:get_height() * 1.2)
end

function TermView:start_shell()
  local shell = os.getenv("SHELL") or "/bin/zsh"
  local cwd   = core.project_dir or os.getenv("HOME")

  local ok, handle = pcall(pty.spawn, {shell, "--login", "-i"}, cwd, self.cols, self.rows)
  if not ok or not handle then
    core.error("[Terminal] Could not start shell: %s", tostring(handle))
    return
  end

  self.pty_handle = handle
  self.emu = Emu.new(self.cols, self.rows)

  -- wire up reply callback so Emu can respond to DA queries
  local h = self.pty_handle
  self.emu.reply = function(data)
    pcall(pty.write, h, data)
  end
  self.emu.on_title = function(t) self._title = t; core.redraw = true end
  self.emu.on_clipboard_set = function(text)
    if system and system.set_clipboard then
      pcall(system.set_clipboard, text)
    end
  end
  self.emu.on_clipboard_get = function()
    if system and system.get_clipboard then
      local ok, text = pcall(system.get_clipboard)
      if ok then return text end
    end
    return ""
  end

  core.add_thread(function()
    while self.pty_handle ~= nil do
      local alive = pty.running(self.pty_handle)
      local chunk = pty.read(self.pty_handle)

      if chunk and chunk ~= "" then
        self.emu:write(chunk); core.redraw = true
      elseif not alive then
        if self.emu then self.emu:write("\r\n\027[90m[process exited]\027[0m\r\n") end
        pcall(pty.close, self.pty_handle)
        self.pty_handle = nil; core.redraw = true; return
      else
        coroutine.yield(0.016)
      end
    end
  end)
end

function TermView:send(data)
  if self.pty_handle and pty.running(self.pty_handle) then
    pcall(pty.write, self.pty_handle, data)
    self.sb_offset = 0
  end
end

function TermView:paste(text)
  if not text or text == "" then return end
  if self.emu and self.emu.bracketed_paste then
    self:send("\027[200~" .. text .. "\027[201~")
  else
    self:send(text)
  end
end

function TermView:update()
  local dest = self.visible and self.target_size or 0
  if self.init_size then
    self.size.y = dest; self.init_size = false
  else
    self:move_towards(self.size, "y", dest, nil, "terminal")
  end

  -- Focus events (DEC mode 1004): emit \x1b[I on gain, \x1b[O on loss
  local is_focused = self.visible and core.active_view == self
  if self.emu and self.emu.focus_events and is_focused ~= self._was_focused then
    self:send(is_focused and "\027[I" or "\027[O")
  end
  self._was_focused = is_focused

  if not self.visible or self.size.y < 4 then return end

  if self.emu then
    local fw, fh = self:cell_wh()
    local nc = math.max(1, math.floor((self.size.x - PAD*2) / fw))
    local nr = math.max(1, math.floor((self.size.y - DIVIDER_H - PAD*2) / fh))
    if nc ~= self._prev_cols or nr ~= self._prev_rows then
      self._prev_cols, self._prev_rows = nc, nr
      self.cols, self.rows = nc, nr
      self.emu:resize(nc, nr)
      -- signal PTY about the new size
      if self.pty_handle then
        pcall(pty.resize, self.pty_handle, nc, nr)
      end
    end
  end

  TermView.super.update(self)
end

function TermView:restart_shell()
  if self.pty_handle then
    pcall(pty.close, self.pty_handle)
    self.pty_handle = nil
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

  -- OSC 0/2 window title, rendered left-aligned in the divider
  if self._title and self._title ~= "" then
    local tcol = style.dim or {0x70,0x78,0x98,255}
    local available = bx - (dx + PAD) - PAD
    local title = self._title
    -- crude char-wise truncation (divider is one line)
    while ui_font:get_width(title) > available and #title > 1 do
      title = title:sub(1, -2)
    end
    renderer.draw_text(ui_font, title,
      dx + PAD,
      dy + math.floor((DIVIDER_H - lh) / 2),
      tcol)
  end

  if not self.emu or not self.visible or self.size.y < DIVIDER_H + PAD*2 + 4 then return end

  local font = self:font()
  local italic_font = self:italic_font() or nil
  local fw, fh = self:cell_wh()
  local rows = self.emu.rows
  local cols = self.emu.cols
  local sb   = self.emu.scrollback
  local in_alt = self.emu.alt_grid ~= nil
  -- disable scrollback viewing when in alternate screen (nvim, htop, etc.)
  local off  = in_alt and 0 or math.min(self.sb_offset, #sb)

  local content_y = self.position.y + DIVIDER_H
  local content_h = self.size.y - DIVIDER_H
  local bg = COL_BG()
  local fg_default = COL_FG()

  core.push_clip_rect(self.position.x, content_y, self.size.x, content_h)

  -- Color-equality helper. Colors may be shared refs or identical tables.
  local function col_eq(a, b)
    if a == b then return true end
    if not a or not b then return false end
    return a[1]==b[1] and a[2]==b[2] and a[3]==b[3] and a[4]==b[4]
  end

  local cur_r_emu = self.emu.cur_r
  local cur_c_emu = self.emu.cur_c
  local show_cursor = off==0 and core.active_view==self and self.emu.cursor_visible
  local shape = self.emu.cursor_shape or "block"
  local cc = style.caret or {166, 166, 217, 255}
  local glyph_y_offset = math.floor((fh-font:get_height())*0.5)
  local italic_y_offset = italic_font and math.floor((fh-italic_font:get_height())*0.5) or 0

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
      local base_x = self.position.x + PAD
      local is_cursor_row = show_cursor and vr == cur_r_emu

      -- Pass 1: background runs
      local run_start, run_bg = 1, row_data[1] and (row_data[1].bg or bg) or bg
      for vc = 2, cols + 1 do
        local cell = row_data[vc]
        local this_bg = cell and (cell.bg or bg) or bg
        if vc == cols + 1 or not col_eq(this_bg, run_bg) then
          renderer.draw_rect(base_x + (run_start-1)*fw, y, (vc-run_start)*fw, fh, run_bg)
          run_start, run_bg = vc, this_bg
        end
      end

      -- Solid block cursor cell paint (under glyph for invert effect)
      if is_cursor_row and shape == "block" then
        local x = base_x + (cur_c_emu-1)*fw
        renderer.draw_rect(x, y, fw, fh, cc)
      end

      -- Pass 2: glyph runs. Break on fg change, italic change, dim change, cursor cell, or space gap.
      local i = 1
      while i <= cols do
        local cell = row_data[i]
        if not cell or cell.ch == nil or cell.ch == " " then
          i = i + 1
        else
          local use_italic = cell.italic and italic_font and true or false
          local col
          if is_cursor_row and i == cur_c_emu and shape == "block" then
            col = cell.bg or bg
          else
            col = cell.fg or fg_default
            if cell.dim then
              col = {col[1], col[2], col[3], math.floor((col[4] or 255) * 0.55)}
            end
          end
          local j = i
          local chars = { cell.ch }
          while j < cols do
            local nxt = row_data[j+1]
            if not nxt or nxt.ch == nil or nxt.ch == " " then break end
            if (nxt.italic and italic_font and true or false) ~= use_italic then break end
            if nxt.dim ~= cell.dim then break end
            -- cursor cell requires its own color (inverted), break the run before it
            if is_cursor_row and (j+1) == cur_c_emu and shape == "block" then break end
            local nxt_col = nxt.fg or fg_default
            if nxt.dim then
              nxt_col = {nxt_col[1], nxt_col[2], nxt_col[3], math.floor((nxt_col[4] or 255) * 0.55)}
            end
            if not col_eq(nxt_col, col) then break end
            j = j + 1
            chars[#chars+1] = nxt.ch
          end
          local gf = use_italic and italic_font or font
          local gy = use_italic and italic_y_offset or glyph_y_offset
          renderer.draw_text(gf, table.concat(chars), base_x + (i-1)*fw, y + gy, col)
          i = j + 1
        end
      end

      -- Pass 3: underline + strike runs (color-coalesced)
      local ul_start, ul_col = nil, nil
      local st_start, st_col = nil, nil
      for vc = 1, cols + 1 do
        local cell = row_data[vc]
        local has_ul = cell and cell.ul
        local has_st = cell and cell.strike
        local u_col = has_ul and (cell.fg or fg_default) or nil
        local s_col = has_st and (cell.fg or fg_default) or nil

        if ul_start and (not has_ul or not col_eq(u_col, ul_col)) then
          renderer.draw_rect(base_x + (ul_start-1)*fw, y+fh-1, (vc-ul_start)*fw, 1, ul_col)
          ul_start = nil
        end
        if has_ul and not ul_start then ul_start, ul_col = vc, u_col end

        if st_start and (not has_st or not col_eq(s_col, st_col)) then
          renderer.draw_rect(base_x + (st_start-1)*fw, y+math.floor(fh*0.55), (vc-st_start)*fw, 1, st_col)
          st_start = nil
        end
        if has_st and not st_start then st_start, st_col = vc, s_col end
      end

      -- Thin cursor variants drawn on top of everything
      if is_cursor_row and shape ~= "block" then
        local x = base_x + (cur_c_emu-1)*fw
        if shape == "underline" then
          local h = math.max(2, math.floor(fh*0.15))
          renderer.draw_rect(x, y+fh-h, fw, h, cc)
        elseif shape == "bar" then
          renderer.draw_rect(x, y, math.max(2, math.floor(fw*0.2)), fh, cc)
        end
      end
    end
  end

  core.pop_clip_rect()
end

-- xterm modifier value: shift=1, alt=2, ctrl=4, meta/cmd=8; the wire value is bits+1
local function mod_bits()
  local m = keymap.modkeys
  if not m then return 0 end
  local b = 0
  if m["shift"] then b = b + 1 end
  if m["alt"]   then b = b + 2 end
  if m["ctrl"]  then b = b + 4 end
  if m["cmd"]   then b = b + 8 end
  return b
end

-- Arrow key sequences depend on DECCKM mode and modifier state
function TermView:arrow_seq(dir)
  local b = mod_bits()
  if b > 0 then
    return string.format("\027[1;%d%s", b + 1, dir)
  end
  if self.emu and self.emu.cursor_key_mode then
    local map = { A="\027OA", B="\027OB", C="\027OC", D="\027OD" }
    return map[dir]
  else
    return "\027[" .. dir
  end
end

-- Fn/navigation keys that accept a modifier-encoded form
-- format: either "\027O<final>" (F1-F4) or "\027[<code>~" (F5+, pageup/down, delete)
local KEY_PLAIN = {
  ["return"]="\r", ["tab"]="\t", ["escape"]="\027", ["backspace"]="\127",
  ["home"]="\027[H", ["end"]="\027[F",
  ["delete"]="\027[3~", ["pageup"]="\027[5~", ["pagedown"]="\027[6~",
  ["f1"]="\027OP",  ["f2"]="\027OQ",  ["f3"]="\027OR",  ["f4"]="\027OS",
  ["f5"]="\027[15~",["f6"]="\027[17~",["f7"]="\027[18~",["f8"]="\027[19~",
  ["f9"]="\027[20~",["f10"]="\027[21~",["f11"]="\027[23~",["f12"]="\027[24~",
}
-- numeric codes for CSI <n>;<mod>~ form
local KEY_CSI_CODE = {
  delete=3, pageup=5, pagedown=6,
  f5=15, f6=17, f7=18, f8=19, f9=20, f10=21, f11=23, f12=24,
}
-- finals for CSI 1;<mod><final> form (F1-F4 and home/end)
local KEY_CSI_FINAL = {
  home="H", ["end"]="F", f1="P", f2="Q", f3="R", f4="S",
}

local function key_seq(name, mod)
  if mod == 0 then return KEY_PLAIN[name] end
  local code = KEY_CSI_CODE[name]
  if code then return string.format("\027[%d;%d~", code, mod + 1) end
  local final = KEY_CSI_FINAL[name]
  if final then return string.format("\027[1;%d%s", mod + 1, final) end
  return KEY_PLAIN[name]  -- no modifier form for this key
end

-- Convert pixel (x,y) to terminal cell (col,row), both 1-based.
-- Returns nil if outside the terminal content area.
function TermView:pixel_to_cell(x, y)
  if not self.emu then return nil end
  local fw, fh = self:cell_wh()
  local cx = x - self.position.x - PAD
  local cy = y - self.position.y - DIVIDER_H - PAD
  if cx < 0 or cy < 0 then return nil end
  local col = math.floor(cx / fw) + 1
  local row = math.floor(cy / fh) + 1
  if col < 1 or col > self.emu.cols or row < 1 or row > self.emu.rows then
    return nil
  end
  return col, row
end

-- Encode a mouse event and send it over the PTY.
-- `button_code`: 0=left, 1=middle, 2=right, 3=release (x10), 64/65=wheel up/down, 32+n=motion with n held
-- `action`: "press" | "release" | "motion"
function TermView:send_mouse(button_code, col, row, action)
  local e = self.emu
  if not e or e.mouse_track == "off" then return false end
  if action == "motion" and e.mouse_track ~= "drag" and e.mouse_track ~= "any" then return false end
  if action == "motion" and e.mouse_track == "drag" and not self._mouse_btn_down then return false end

  -- Add modifier bits (shift=4, alt=8, ctrl=16)
  local mods = 0
  local mk = keymap.modkeys
  if mk then
    if mk["shift"] then mods = mods + 4 end
    if mk["alt"]   then mods = mods + 8 end
    if mk["ctrl"]  then mods = mods + 16 end
  end
  local cb = button_code + mods

  if e.mouse_enc == "sgr" then
    -- CSI < Cb ; Cx ; Cy M/m
    local final = action == "release" and "m" or "M"
    self:send(string.format("\027[<%d;%d;%d%s", cb, col, row, final))
  else
    -- X10/normal: CSI M <Cb+32> <Cx+32> <Cy+32>, release reports button 3
    if action == "release" then cb = 3 + mods end
    local bx = math.min(255, col + 32)
    local by = math.min(255, row + 32)
    self:send(string.format("\027[M%s%s%s", string.char(cb + 32), string.char(bx), string.char(by)))
  end
  return true
end

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
  local bhover = r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
  if bhover ~= self._restart_hover or on_divider ~= self._divider_hover then
    self._restart_hover = bhover
    self._divider_hover = on_divider
    core.redraw = true
  end

  -- Mouse motion reporting
  if self.emu and (self.emu.mouse_track == "drag" or self.emu.mouse_track == "any") then
    local col, row = self:pixel_to_cell(x, y)
    if col and (col ~= self._last_mouse_col or row ~= self._last_mouse_row) then
      self._last_mouse_col, self._last_mouse_row = col, row
      local btn = self._mouse_btn_down or 3  -- 3 = no button (motion without drag)
      self:send_mouse(32 + btn, col, row, "motion")
    end
  end

  return TermView.super.on_mouse_moved(self, x, y, ...)
end

local BTN_CODE = { left = 0, middle = 1, right = 2 }

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

  -- Mouse reporting (consume the event so parent doesn't also select)
  if self.emu and self.emu.mouse_track ~= "off" then
    local col, row = self:pixel_to_cell(x, y)
    local bc = BTN_CODE[button]
    if col and bc then
      self._mouse_btn_down = bc
      self:send_mouse(bc, col, row, "press")
      return true
    end
  end

  return TermView.super.on_mouse_pressed(self, button, x, y, clicks)
end

function TermView:on_mouse_released(button, x, y)
  if self._dragging then
    self._dragging = false
    return true
  end
  if self.emu and self.emu.mouse_track ~= "off" then
    local col, row = self:pixel_to_cell(x, y)
    local bc = BTN_CODE[button]
    if col and bc then
      self:send_mouse(bc, col, row, "release")
      self._mouse_btn_down = nil
      return true
    end
  end
  self._mouse_btn_down = nil
  return TermView.super.on_mouse_released and TermView.super.on_mouse_released(self, button, x, y)
end

function TermView:on_text_input(text)
  if self.visible and core.active_view == self then self:send(text) end
end

function TermView:on_key_pressed(key)
  if not self.visible or core.active_view ~= self then return false end
  local mod = mod_bits()

  -- Arrows with modifiers: xterm "CSI 1;<m>A" form.
  -- Plain arrows are dispatched via keymap command, so fall through when mod == 0.
  local arrow_dir = ({up="A", down="B", right="C", left="D"})[key]
  if arrow_dir then
    if mod > 0 then self:send(self:arrow_seq(arrow_dir)); return true end
    return false
  end

  -- Shift+Tab -> reverse tab
  if key == "tab" and keymap.modkeys and keymap.modkeys["shift"] then
    self:send("\027[Z"); return true
  end

  -- Navigation / Fn keys. Return false for keys also bound in keymap (plain forms)
  -- so the keymap command handles them; the view only handles the modifier forms.
  if KEY_PLAIN[key] then
    if mod == 0 then
      -- keymap owns the plain variants it has bound
      local keymap_owned = { ["backspace"]=1,["delete"]=1,["return"]=1,
                             ["tab"]=1,["escape"]=1 }
      if keymap_owned[key] then return false end
      self:send(KEY_PLAIN[key]); return true
    end
    local seq = key_seq(key, mod)
    if seq then self:send(seq); return true end
  end

  return false
end

function TermView:on_mouse_wheel(dy, ...)
  if not self.visible or not self.emu then return end

  -- When an app is tracking the mouse (nvim, tmux, less), forward wheel as button 64/65.
  -- Otherwise fall back to scrollback viewing.
  if self.emu.mouse_track ~= "off" then
    local mx, my = core.root_view.mouse and core.root_view.mouse.x, core.root_view.mouse and core.root_view.mouse.y
    local col, row = 1, 1
    if mx and my then
      local c, r = self:pixel_to_cell(mx, my)
      if c then col, row = c, r end
    end
    local btn = dy > 0 and 64 or 65
    self:send_mouse(btn, col, row, "press")
    return true
  end

  -- in alternate screen, don't scroll through main-screen scrollback
  if self.emu.alt_grid then return true end
  if dy > 0 then
    self.sb_offset = math.min(self.sb_offset+3, #self.emu.scrollback)
  else
    self.sb_offset = math.max(0, self.sb_offset-3)
  end
  core.redraw = true
  return true
end

---------------------------------------------------------------------------
-- Singleton + commands
---------------------------------------------------------------------------
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
      if not term_view.pty_handle then term_view:start_shell() end
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
  ["terminal:up"]         = function() term_view:send(term_view:arrow_seq("A")) end,
  ["terminal:down"]       = function() term_view:send(term_view:arrow_seq("B")) end,
  ["terminal:right"]      = function() term_view:send(term_view:arrow_seq("C")) end,
  ["terminal:left"]       = function() term_view:send(term_view:arrow_seq("D")) end,
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
    term_view:paste(text)
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
