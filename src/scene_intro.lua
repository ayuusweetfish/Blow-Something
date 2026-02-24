local draw = require 'draw_utils'
local button = require 'button'
local audio = require 'audio'

return function ()
  local s = {}
  local W, H = W, H
  local font = _G['global_font']

  local langNames = {'zh', 'en'}
  local lang = 1

  local btnLang
  btnLang = button(draw.get('btn_lang_' .. langNames[lang]), function ()
    lang = lang % 2 + 1
    btnLang.drawable = draw.get('btn_lang_' .. langNames[lang])
    audio.sfx('bubble_pop')
  end)
  btnLang.x = 25
  btnLang.y = 20

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
    replaceScene(scene_game(langNames[lang]), transitions['fade'](0.1, 0.1, 0.1))
  end

  s.update = function ()
  end

  s.draw = function ()
    love.graphics.clear(1, 1, 1)
    draw.img('cover', 0, 0, W, H)
    if btnLang.inside then
      love.graphics.setColor(0.6, 0.6, 0.6)
    else
      love.graphics.setColor(1, 1, 1)
    end
    btnLang.draw()
  end

  s.destroy = function ()
  end

  return s
end
