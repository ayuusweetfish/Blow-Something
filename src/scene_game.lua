local draw = require 'draw_utils'
local button = require 'button'

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

  local joints_inflating = {}
  local set_size = function (expected_r)
    for i = 1, n do
      local x = math.cos(i / n * math.pi * 2) * expected_r
      local y = math.sin(i / n * math.pi * 2) * expected_r
      x = x + (love.math.noise(x*0.6 - 15, y*0.6) - 0.5) * 7e-2 * expected_r
      y = y + (love.math.noise(x*0.6, y*0.6 + 10) - 0.5) * 7e-2 * expected_r
      b[i]:setPosition(x * scale * 0.94, y * scale * 0.94)
    end

    for i = 1, #joints_inflating do
      local j = joints_inflating[i]
      j.joint:setLength(expected_r * j.rate)
      if j.freq_rate then
        j.joint:setFrequency(j.freq_rate / expected_r^3)
      end
    end
  end

  for i = 1, n do
    local b1 = b[i]
    local x1, y1 = b1:getPosition()

    for j = 1, 3 do
      local b2 = b[(i + j - 1) % n + 1]
      local x2, y2 = b2:getPosition()
      local joint = love.physics.newDistanceJoint(b1, b2, x1, y1, x2, y2)
      joint:setDampingRatio(10) -- Oscillate less
      joints_inflating[#joints_inflating + 1] = {
        joint = joint,
        rate = 2 * math.sin(math.pi / n * j) * scale,
        freq_rate = (j == 3 and 3 or 4) * 0.1
      }
    end

    local joint = love.physics.newDistanceJoint(b1, body_cen, x1, y1, 0, 0)
    joint:setDampingRatio(0)
    joint:setFrequency(0.05)
    joints_inflating[#joints_inflating + 1] = {
      joint = joint,
      rate = 1 * scale,
      freq_rate = 0.05 * 0.1,
    }
  end
  set_size(0.1)

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

  local imp_r = 0.1

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
    set_size = set_size,
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
      math.cos(i / n * math.pi * 2) * 0.1,
      math.sin(i / n * math.pi * 2) * 0.1,
    }
  end
  local bubbles = bubbles(p)

  local STATE_INITIAL = 0
  local STATE_INFLATE = 1
  local STATE_PAINT = 2

  local state, sinceState = STATE_INITIAL, 0

  local buttons = {}
  local btnStick
  btnStick = button({ x = 128, y = 217, w = 16, h = 58 }, function ()
    print('start inflating')
    state, sinceState = STATE_INFLATE, 0
    btnStick.enabled = false
  end)
  buttons[#buttons + 1] = btnStick

  local selPaint = { 1, .19, .30 }
  -- Palette buttons
  local paletteButton = function (x, y, w, h, r, g, b)
    buttons[#buttons + 1] = button({ x = x, y = y, w = w, h = h }, function ()
      selPaint = { r, g, b }
    end)
  end
  paletteButton(46, 269, 17, 16, 1, .19, .30)
  paletteButton(64, 269, 20, 16, 1, .60, .14)
  paletteButton(85, 269, 20, 16, .72, .67, .25)
  paletteButton(46, 286, 17, 21, .58, .60, .92)
  paletteButton(64, 286, 20, 21, 1, .20, .81)
  paletteButton(85, 286, 20, 21, .62, .93, .98)
  paletteButton(106, 269, 17, 38, .5, .5, .5)

  local inflateStart = nil

  local Xc = W * 0.5
  local Yc = H * 0.46

  s.press = function (x, y)
    if state == STATE_INFLATE then
      inflateStart = sinceState
      return true
    end

    for i = 1, #buttons do if buttons[i].press(x, y) then return true end end
    local x1 = (x - Xc) / dispScale
    local y1 = (y - Yc) / dispScale

    if state == STATE_PAINT then
      bubbles.set_ptr(x1, y1)
    end
  end

  s.hover = function (x, y)
  end

  s.move = function (x, y)
    for i = 1, #buttons do if buttons[i].move(x, y) then return true end end
    local x1 = (x - Xc) / dispScale
    local y1 = (y - Yc) / dispScale

    if state == STATE_PAINT then
      bubbles.set_ptr(x1, y1)
    end
  end

  s.release = function (x, y)
    if state == STATE_INFLATE and inflateStart then
      print('start painting', sinceState - inflateStart)
      state, sinceState = STATE_PAINT, 0
    end

    for i = 1, #buttons do if buttons[i].release(x, y) then return true end end

    if state == STATE_PAINT then
      bubbles.rel_ptr()
    end
  end

  s.update = function ()
    sinceState = sinceState + 1
    if state == STATE_INFLATE and inflateStart then
      local t = (sinceState - inflateStart) / 240
      bubbles.set_size(0.1 + 0.8 * (1 - math.exp(-t))^2)
    end
    if (state == STATE_INFLATE and inflateStart) or state == STATE_PAINT then
      bubbles.update(1 / 240)
    end
  end

  local Wc, Hc = 160, 200
  local tex = love.image.newImageData(Wc, Hc, 'rgba8')
  local img = love.graphics.newImage(tex)

  local line = function (tex, x0, y0, x1, y1)
    -- Distance is less than 1
    if x0 >= 0 and x0 < Wc and y0 >= 0 and y0 < Hc then
      tex:setPixel(math.floor(x0), math.floor(y0), selPaint[1], selPaint[2], selPaint[3], 1)
    end
  end

  s.draw = function ()
    love.graphics.clear(1, 1, 1)

    love.graphics.setColor(1, 1, 1)
    draw.img('background', W / 2, 267, W, nil, 0.5, 1)
    love.graphics.setColor(0.81, 0.79, 0.76)
    love.graphics.rectangle('fill', 0, 267, W, H)

    if (state == STATE_INFLATE and inflateStart) or state == STATE_PAINT then
      -- Bubble
      -- Clear texture
      tex:mapPixel(function () return 1, 0.96, 0.92, 1 end)
      -- Draw lines onto texture
      local pts = {}
      for i = 0, n + 2 do
        local x, y = bubbles.get_pos((i - 1 + n) % n + 1)
        local x0 = Wc / 2 + x * dispScale
        local y0 = Hc / 2 + y * dispScale
        pts[i] = { x = x0, y = y0, knot = (i - 1) / n }
      end
      local x1, y1, index = CatmullRomSpline(0, pts, 0, 0)
      love.graphics.setLineWidth(1)
      love.graphics.setColor(0, 0, 0)
      for i = 1, 1000 do
        local t = i / 1000
        local x0, y0, index_new = CatmullRomSpline(t, pts, 0, index)
        line(tex, x0, y0, x1, y1)
        x1, y1, index = x0, y0, index_new
      end

      img:replacePixels(tex)
      love.graphics.setBlendMode('alpha', 'premultiplied')
      love.graphics.setColor(1, 1, 1)
      love.graphics.draw(img,
        math.floor(Xc - Wc / 2),
        math.floor(Yc - Hc / 2),
        0, dispScale * 2 / Wc)
      love.graphics.setBlendMode('alpha')

      local px, py, pr = bubbles.get_ptr()
      if px then
        love.graphics.setColor(0.8, 0.8, 0.8, 0.5)
        love.graphics.circle('fill',
          Xc + px * dispScale,
          Yc + py * dispScale,
          pr * dispScale)
      end
    end

    love.graphics.setColor(1, 1, 1)
    draw.img('cat', 10, 198)
    if state == STATE_INITIAL then
      draw.img('stick_small', 128, 217)
    end
    draw.img('bottle', 128, 217)
    draw.img('palette', 43, 266)
    draw.img('camera', 143, 263)

    if state == STATE_INFLATE then
      draw.img('stick_large', 98, 155)
    end
  end

  s.destroy = function ()
  end

  return s
end
