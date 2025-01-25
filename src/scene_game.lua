local draw = require 'draw_utils'

local bubbles = function (n)
  local p = {}
  for i = 1, n do p[i] = { x = 0, y = 0, lx = 0, ly = 0 } end
  p[n + 1] = p[1]

  local d_limit = 2e-2
  local d_limit_sq = d_limit * d_limit
  local d_scale = 100
  local tension = function (x0, y0, x1, y1)
    local dx, dy = x1 - x0, y1 - y0
    local dsq = dx * dx + dy * dy
    local d = math.sqrt(dsq)
    local intensity
    if dsq < d_limit_sq then
      -- intensity = 1 * d_limit / d
      intensity = -(d - d_limit) * d_scale
    else
      intensity = (d - d_limit) * d_scale
    end
    local scale = intensity / d
    return dx * scale, dy * scale
  end

  local update = function (dt)
    local xp, yp
    local x0, y0 = p[n].x, p[n].y
    local xn, yn = p[1].x, p[1].y
    for i = 1, n do
      xp, yp, x0, y0 = x0, y0, xn, yn
      xn, yn = p[i + 1].x, p[i + 1].y
      -- Acceleration
      local axp, ayp = tension(x0, y0, xp, yp)
      local axn, ayn = tension(x0, y0, xn, yn)
      local ax, ay = axp + axn, ayp + ayn
      -- print(ax, ay, axp, ayp, axn, ayn)
      -- Verlet integration
      p[i].x = 2 * x0 - p[i].lx + ax * dt * dt
      p[i].y = 2 * y0 - p[i].ly + ay * dt * dt
      p[i].lx, p[i].ly = x0, y0
    end
  end

  return {
    p = p,
    update = update,
  }
end

return function ()
  local s = {}
  local W, H = W, H

  local n = 200
  local bubbles = bubbles(n)
  local p = bubbles.p
  for i = 1, n do
    p[i].x = math.cos(i / n * math.pi * 2) * 0.5
    p[i].y = math.sin(i / n * math.pi * 2) * 0.3
    p[i].lx, p[i].ly = p[i].x, p[i].y
  end

  s.press = function (x, y)
  end

  s.hover = function (x, y)
  end

  s.move = function (x, y)
  end

  s.release = function (x, y)
  end

  s.update = function ()
    bubbles.update(1 / 240)
  end

  s.draw = function ()
    love.graphics.clear(1, 1, 1)
    love.graphics.setColor(0, 0, 0)
    for i = 1, n do
      local x0 = W / 2 + p[i].x * (W * 0.4)
      local y0 = H / 2 + p[i].y * (W * 0.4)
      love.graphics.circle('fill', x0, y0, 2)
    end
  end

  s.destroy = function ()
  end

  return s
end
