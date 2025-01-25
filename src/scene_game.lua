local draw = require 'draw_utils'

love.physics.setMeter(1)

local bubbles = function (p)
  local n = #p
  local scale = 20

  local b = {}
  local world = love.physics.newWorld()
  for i = 1, n do
    local body = love.physics.newBody(world, 0, 0, 'dynamic')
    local shape = love.physics.newCircleShape(1e-6)
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
    joint:setDampingRatio(0.4)  -- Keep a lot of oscillations
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

  local imp_r = 0.1
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
          local imp_scale = 0.4 * scale * imp_intensity / d
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
      local fx, fy = js[i]:getReactionForce(1 / 240)
      if fx * fx + fy * fy >= 1e-6 then print(i, x, y) end
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
    for i = 1, n do
      local awake = bubbles.get_body(i):isAwake()
      love.graphics.setColor(0, 0, 0, awake and 1 or 0.2)
      local x, y = bubbles.get_pos(i)
      local x0 = W / 2 + x * dispScale
      local y0 = H / 2 + y * dispScale
      love.graphics.circle('fill', x0, y0, 2)
    end
  end

  s.destroy = function ()
  end

  return s
end
