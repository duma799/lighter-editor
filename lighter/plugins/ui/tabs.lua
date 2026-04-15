local style = require "core.style"
local common = require "core.common"
local Node = require "core.node"

local radius = 8
local tab_gap = 6

local function draw_rounded_rect_top(x, y, w, h, r, color, mask_color)
  renderer.draw_rect(x, y + r, w, h - r, color)
  renderer.draw_rect(x + r, y, w - r * 2, r, color)
  for i = 0, r - 1 do
    local dy = r - i - 0.5
    local dx = math.floor(r - math.sqrt(r * r - dy * dy) + 0.5)
    renderer.draw_rect(x + dx, y + i, r - dx, 1, color)
    renderer.draw_rect(x + w - r, y + i, r - dx, 1, color)
    if dx > 0 then
      renderer.draw_rect(x, y + i, dx, 1, mask_color)
      renderer.draw_rect(x + w - dx, y + i, dx, 1, mask_color)
    end
  end
end


function Node:draw_tab_borders(view, is_active, is_hovered, x, y, w, h, standalone)
  local ds = style.divider_size
  local gap = math.floor(tab_gap / 2)

  if standalone then
    renderer.draw_rect(x - 1, y - 1, w + 2, h + 2, style.background2)
  end

  if is_active then
    draw_rounded_rect_top(x + gap, y, w - gap * 2, h, radius, style.background, style.background2)
  else
    local padding_y = style.padding.y
    renderer.draw_rect(x + w, y + padding_y, ds, h - padding_y * 2, style.dim)
  end

  return x + gap + ds, y, w - gap * 2 - ds * 2, h
end
