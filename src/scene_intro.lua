local draw = require 'draw_utils'
local button = require 'button'
local audio = require 'audio'

return function ()
  local s = {}
  local W, H = W, H
  local font = _G['global_font']

  local btnLang = _G['btnLang']() -- See `main.lua`

  s.press = function (x, y)
    if btnLang.press(x, y) then return true end
  end

  s.hover = function (x, y)
  end

  s.move = function (x, y)
    if btnLang.move(x, y) then return true end
  end

  s.release = function (x, y)
    if btnLang.release(x, y) then return true end

    audio.sfx('refill')
    replaceScene(scene_game(), transitions['fade'](0.1, 0.1, 0.1))
  end

  s.update = function ()
  end

  s.draw = function ()
    love.graphics.clear(0, 0, 0)
    draw.img('cover', 0, 0, W, H)
    btnLang.draw()
  end

  s.destroy = function ()
  end

  return s
end
