local draw = require 'draw_utils'

love.physics.setMeter(1)

local bubbles = function (p)
  local n = #p
  local scale = 5

  local b = {}
  local world = love.physics.newWorld()
  for i = 1, n do
    local x, y = p[i][1] * scale, p[i][2] * scale

    local body = love.physics.newBody(world, x, y, 'dynamic')
    local shape = love.physics.newCircleShape(1e-4 * scale)
    local fixt = love.physics.newFixture(body, shape)

    body:setMass(1)
    body:setLinearDamping(0.5)  -- Damp
    body:setAngularDamping(1.0) -- Damp a lot
    fixt:setRestitution(0.9)    -- Bounce a lot

    b[i] = body
  end

  local body_cen = love.physics.newBody(world, 0, 0, 'dynamic')
  local shape = love.physics.newCircleShape(1e-4 * scale)
  local fixt = love.physics.newFixture(body_cen, shape)
  body_cen:setMass(10)

  local expected_r = 0.5

  for i = 1, n do
    local b1 = b[i]
    local x1, y1 = b1:getPosition()

    for j = 1, 3 do
      local b2 = b[(i + j - 1) % n + 1]
      local x2, y2 = b2:getPosition()
      local joint = love.physics.newDistanceJoint(b1, b2, x1, y1, x2, y2)
      joint:setDampingRatio(10) -- Oscillate less
      joint:setFrequency(j == 3 and 3 or 4)
      joint:setLength(expected_r * 2 * math.sin(math.pi / n * j) * scale)
    end

    local joint = love.physics.newDistanceJoint(b1, body_cen, x1, y1, 0, 0)
    joint:setDampingRatio(0)
    joint:setFrequency(0.05)
    joint:setLength(expected_r * scale)
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

  local imp_r = 0.075

  local px, py = nil, nil
  local set_ptr = function (x, y) px, py = x * scale, y * scale end
  local rel_ptr = function () px, py = nil, nil end
  local get_ptr = function ()
    if px then return px / scale, py / scale, imp_r end
    return nil
  end

  local update = function (dt)
    if px ~= nil then
      world:queryBoundingBox(
        px - imp_r * scale, py - imp_r * scale,
        px + imp_r * scale, py + imp_r * scale,
        function (fixt)
          local b = fixt:getBody()
          local x1, y1 = b:getPosition()
          local dx, dy = (x1 - px) / scale, (y1 - py) / scale
          local dsq = dx * dx + dy * dy
          if dsq < imp_r * imp_r then
            local d = math.sqrt(dsq)
            local t = 1 - d / imp_r
            local imp_intensity = 1 - t * t
            local imp_scale = 2.5 * scale * imp_intensity / d
            b:applyForce(dx * imp_scale, dy * imp_scale)
          end
          return true
        end
      )
    end

    world:update(dt)
  end

  return {
    set_pos = set_pos,
    get_pos = get_pos,
    get_body = get_body,
    set_ptr = set_ptr,
    rel_ptr = rel_ptr,
    get_ptr = get_ptr,
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

  local dispScale = 80

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
    bubbles.set_ptr(x1, y1)
  end

  s.hover = function (x, y)
  end

  s.move = function (x, y)
    local x1 = (x - W / 2) / dispScale
    local y1 = (y - H / 2) / dispScale
    bubbles.set_ptr(x1, y1)
  end

  s.release = function (x, y)
    bubbles.rel_ptr()
  end

  s.update = function ()
    bubbles.update(1 / 240)
  end

  local Wc, Hc = 160, 160
  local tex = love.image.newImageData(Wc, Hc, 'rgba8')
  local img = love.graphics.newImage(tex)

  local line = function (tex, x0, y0, x1, y1)
    if x0 >= 0 and x0 < Wc and y0 >= 0 and y0 < Hc then
      tex:setPixel(math.floor(x0), math.floor(y0), 0, 0, 0, 1)
    end
  end

  s.draw = function ()
    love.graphics.clear(1, 1, 1)

    love.graphics.setColor(1, 1, 1)
    draw.img('background', W / 2, 267, W, nil, 0.5, 1)
    love.graphics.setColor(0.81, 0.79, 0.76)
    love.graphics.rectangle('fill', 0, 267, W, H)

    -- Clear texture
    tex:mapPixel(function () return 1, 0.96, 0.92, 1 end)
    local pts = {}
    for i = 0, n + 2 do
      local x, y = bubbles.get_pos((i - 1 + n) % n + 1)
      local x0 = Wc / 2 + x * (Wc / 2)
      local y0 = Hc / 2 + y * (Hc / 2)
      pts[i] = { x = x0, y = y0, knot = (i - 1) / n }
    end
    local x1, y1, index = CatmullRomSpline(0, pts, 0, 0)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0, 0, 0)
    for i = 1, 1000 do
      local t = i / 1000
      local x0, y0, index_new = CatmullRomSpline(t, pts, 0, index)
      -- love.graphics.line(x0, y0, x1, y1)
      line(tex, x0, y0, x1, y1)
      x1, y1, index = x0, y0, index_new
    end

    img:replacePixels(tex)
    love.graphics.setBlendMode('alpha', 'premultiplied')
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(img, W / 2, H / 2, 0,
      dispScale * 2 / Wc, dispScale * 2 / Hc, Wc / 2, Hc / 2)

    love.graphics.setBlendMode('alpha')
    if false then
      love.graphics.setColor(0.4, 0.4, 0)
      local x1, y1
      local x, y = bubbles.get_pos(n)
      x1 = W / 2 + x * dispScale
      y1 = H / 2 + y * dispScale
      for i = 1, n do
        local x, y = bubbles.get_pos(i)
        local x0 = W / 2 + x * dispScale
        local y0 = H / 2 + y * dispScale
        love.graphics.circle('fill', x0, y0, 2)
        x1, y1 = x0, y0
      end
    end

    local px, py, pr = bubbles.get_ptr()
    if px then
      love.graphics.setColor(1, 0.7, 0.7, 0.7)
      love.graphics.circle('fill',
        W / 2 + px * dispScale,
        H / 2 + py * dispScale,
        pr * dispScale)
    end

    love.graphics.setColor(1, 1, 1)
    draw.img('cat', 10, 198)
    draw.img('stick_small', 128, 217)
    draw.img('bottle', 128, 217)
    draw.img('palette', 43, 266)
    draw.img('camera', 143, 263)
    -- draw.img('stick_large', 98, 155)
  end

  s.destroy = function ()
  end

  return s
end
