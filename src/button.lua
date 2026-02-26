return function (drawable, fn)
  local s = {}
  local W, H = W, H

  s.x = 0
  s.y = 0
  s.s = 1
  s.enabled = true
  s.drawable = drawable

  local w, h
  if drawable.getDimensions then
    w, h = drawable:getDimensions()
  else
    w = drawable.w
    h = drawable.h
    if drawable.x then
      s.x = drawable.x + w/2
      s.y = drawable.y + h/2
    end
  end
  local scale = 1

  local held = false
  s.inside = false

  s.press = function (x, y)
    if not s.enabled then return false end
    if x >= s.x - w/2 and x <= s.x + w/2 and
       y >= s.y - h/2 and y <= s.y + h/2 then
      held = true
      s.inside = true
      return true
    else
      return false
    end
  end

  s.move = function (x, y)
    if not held then return false end
    s.inside =
      x >= s.x - w/2 and x <= s.x + w/2 and
      y >= s.y - h/2 and y <= s.y + h/2
    return true
  end

  s.release = function (x, y)
    if not held then return false end
    if s.inside then fn() s.inside = false end
    held = false
    return true
  end

  s.update = function ()
  end

  s.draw = function ()
    if not s.enabled then return end
    if s.inside then
      love.graphics.setColor(0.6, 0.6, 0.6)
    else
      love.graphics.setColor(1, 1, 1)
    end
    local sc = scale * s.s
    local x, y, sc = s.x - w/2 * sc, s.y - h/2 * sc, sc
    if s.drawable.draw then
      s.drawable:draw(x, y, sc)
    else
      love.graphics.draw(s.drawable, x, y, 0, sc)
    end
  end

  return s
end
