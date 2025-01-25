local draw = require 'draw_utils'

love.physics.setMeter(1)

local bubbles = function (p)
  local n = #p
  local scale = 5

  local b = {}
  local world = love.physics.newWorld()
  for i = 1, n do
    local body = love.physics.newBody(world, 0, 0, 'dynamic')
    local shape = love.physics.newCircleShape(1e-4 * scale)
    local fixt = love.physics.newFixture(body, shape)

    body:setLinearDamping(0.5)  -- Damp
    body:setAngularDamping(1.0) -- Damp a lot
    fixt:setRestitution(0.9)    -- Bounce a lot

    body:setPosition(p[i][1] * scale, p[i][2] * scale)

    b[i] = body
  end

  for i = 1, n do
    local b1 = b[i]
    local b2 = b[i % n + 1]
    local x1, y1 = b1:getPosition()
    local x2, y2 = b2:getPosition()
    local joint = love.physics.newDistanceJoint(b1, b2, x1, y1, x2, y2)
    joint:setDampingRatio(10) -- Oscillate less
    joint:setFrequency(3.0)
    joint:setLength(3e-2 * scale)
  end

  local set_pos = function (i, x, y)
    b[i]:setPosition(x * scale, y * scale)
  end

  local get_pos = function (i)
    local x, y = b[i]:getPosition()
    return x / scale, y / scale
  end
  local get_body = function (i)
    return b[i]
  end

  local imp_r = 0.05
  local imp = function (x, y)
    x = x * scale
    y = y * scale
    world:queryBoundingBox(
      x - imp_r * scale, y - imp_r * scale,
      x + imp_r * scale, y + imp_r * scale,
      function (fixt)
        local b = fixt:getBody()
        local x1, y1 = b:getPosition()
        local dx, dy = (x1 - x) / scale, (y1 - y) / scale
        local dsq = dx * dx + dy * dy
        if dsq < imp_r * imp_r then
          local d = math.sqrt(dsq)
          local t = 1 - d / imp_r
          local imp_intensity = 1 - t * t
          local imp_scale = 0.3 * scale * imp_intensity / d
          b:setLinearVelocity(dx * imp_scale, dy * imp_scale)
          b:setAwake(true)
        end
        return true
      end
    )
  end

  local update = function (dt)
    world:update(dt)
    local js = world:getJoints()
    for i = 1, #js do
      local b1, b2 = js[i]:getBodies()
      local x1, y1 = b1:getPosition()
      local x2, y2 = b2:getPosition()
      local d = math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
      -- print(js[i]:getLength(), d)
    end
  end

  return {
    set_pos = set_pos,
    get_pos = get_pos,
    get_body = get_body,
    imp = imp,
    update = update,
  }
end

-- Returns: x, y, new index
local CatmullRomSpline = function (t, pts, index)
  local n = #pts
  while index <= #pts - 4 and t > pts[index + 2].knot do
    index = index + 1
  end

  local t0, t1, t2, t3 =
    pts[index + 0].knot, pts[index + 1].knot,
    pts[index + 2].knot, pts[index + 3].knot
  local lerp = function (t, t0, t1, x0, x1)
    return ((t1 - t) * x0 + (t - t0) * x1) / (t1 - t0)
  end
  local interpolate = function (x0, x1, x2, x3)
    local a1 = lerp(t, t0, t1, x0, x1)
    local a2 = lerp(t, t1, t2, x1, x2)
    local a3 = lerp(t, t2, t3, x2, x3)
    local b1 = lerp(t, t0, t2, a1, a2)
    local b2 = lerp(t, t1, t3, a2, a3)
    local c1 = lerp(t, t1, t2, b1, b2)
    return c1
  end

  local x0, x1, x2, x3 =
    pts[index + 0].x, pts[index + 1].x,
    pts[index + 2].x, pts[index + 3].x
  local y0, y1, y2, y3 =
    pts[index + 0].y, pts[index + 1].y,
    pts[index + 2].y, pts[index + 3].y
  local x = interpolate(x0, x1, x2, x3)
  local y = interpolate(y0, y1, y2, y3)
  return x, y, index
end

return function ()
  local s = {}
  local W, H = W, H

  local dispScale = W * 0.4

  local n = 100
  local p = {}
  for i = 1, n do
    p[i] = {
      math.cos(i / n * math.pi * 2) * 0.5,
      math.sin(i / n * math.pi * 2) * 0.3,
    }
  end
  local bubbles = bubbles(p)

  s.press = function (x, y)
    local x1 = (x - W / 2) / dispScale
    local y1 = (y - H / 2) / dispScale
    bubbles.imp(x1, y1)
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
    love.graphics.setLineWidth(3)
    local x1, y1
    local x, y = bubbles.get_pos(n)
    x1 = W / 2 + x * dispScale
    y1 = H / 2 + y * dispScale
    for i = 1, n do
      local x, y = bubbles.get_pos(i)
      local x0 = W / 2 + x * dispScale
      local y0 = H / 2 + y * dispScale
      love.graphics.circle('fill', x0, y0, 2)
      -- love.graphics.line(x0, y0, x1, y1)
      x1, y1 = x0, y0
    end

    local pts = {}
    for i = 0, n + 2 do
      local x, y = bubbles.get_pos((i - 1 + n) % n + 1)
      local x0 = W / 2 + x * dispScale
      local y0 = H / 2 + y * dispScale
      pts[i] = { x = x0, y = y0, knot = (i - 1) / n }
    end
    local x1, y1, index = CatmullRomSpline(0, pts, 0, 0)
    for i = 1, 1000 do
      local t = i / 1000
      local x0, y0, index_new = CatmullRomSpline(t, pts, 0, index)
      love.graphics.line(x0, y0, x1, y1)
      x1, y1, index = x0, y0, index_new
    end
  end

  s.destroy = function ()
  end

  return s
end
