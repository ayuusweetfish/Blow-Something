local draw = require 'draw_utils'
local button = require 'button'
local audio = require 'audio'

return function ()
  local s = {}
  local W, H = W, H
  local font = _G['global_font']

  s.press = function (x, y)
  end

  s.hover = function (x, y)
  end

  s.move = function (x, y)
  end

  s.release = function (x, y)
    audio.sfx('refill')
    replaceScene(scene_game(), transitions['fade'](0.1, 0.1, 0.1))
  end

  s.update = function ()
  end

  s.draw = function ()
    love.graphics.clear(1, 1, 1)
    draw.img('cover', 0, 0, W, H)
  end

  s.destroy = function ()
  end

  return s
end
