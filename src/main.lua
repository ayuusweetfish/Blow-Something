W = 180
H = 320

local isMobile = (love.system.getOS() == 'Android' or love.system.getOS() == 'iOS')
local isWeb = (love.system.getOS() == 'Web')

love.window.setMode(
  isWeb and W * 2 or W * 3,
  isWeb and H * 2 or H * 3,
  { fullscreen = false, highdpi = true }
)

love.graphics.setDefaultFilter('nearest', 'nearest')

local globalScale, Wx, Hx, offsX, offsY

local updateLogicalDimensions = function ()
  love.window.setTitle('Blow Something')
  local wDev, hDev = love.graphics.getDimensions()
  globalScale = math.min(wDev / W, hDev / H)
  Wx = wDev / globalScale
  Hx = hDev / globalScale
  offsX = (Wx - W) / 2
  offsY = (Hx - H) / 2
end
updateLogicalDimensions()

-- Load font
local fontSizeFactory = function (path, preload)
  local font = {}
  if preload ~= nil then
    for i = 1, #preload do
      local size = preload[i]
      if path == nil then
        font[size] = love.graphics.newFont(size)
      else
        font[size] = love.graphics.newFont(path, size)
      end
    end
  end
  return function (size)
    if font[size] == nil then
      if path == nil then
        font[size] = love.graphics.newFont(size)
      else
        font[size] = love.graphics.newFont(path, size)
      end
    end
    return font[size]
  end
end
_G['global_font'] = fontSizeFactory('fnt/WenQuanYi_Bitmap_Song_14px.ttf', {28, 36})
love.graphics.setFont(_G['global_font'](40))

local audio = require 'audio'
local bgm, bgm_update = audio.loop(
  nil, 0,
  'aud/background.ogg', (60 * 4) * (60 / 132),
  1600 * 4
)
bgm:setVolume(1)
bgm:play()

require 'draw_utils'  -- Load
print('*finish')

-- Language button

local langNames = {'zh', 'en'}
local langIndex = 1
_G['lang'] = langNames[langIndex]

local draw = require 'draw_utils'
local button = require 'button'
_G['btnLang'] = function ()
  local btnLang
  btnLang = button(draw.get('btn_lang_' .. langNames[langIndex]), function ()
    langIndex = langIndex % 2 + 1
    btnLang.drawable = draw.get('btn_lang_' .. langNames[langIndex])
    _G['lang'] = langNames[langIndex]
    audio.sfx('bubble_pop')
  end)
  btnLang.x = 25
  btnLang.y = 20

  local drawOrig = btnLang.draw
  btnLang.draw = function ()
    if not btnLang.enabled then return end
    if btnLang.inside then
      love.graphics.setColor(0.6, 0.6, 0.6)
    else
      love.graphics.setColor(1, 1, 1)
    end
    drawOrig()
  end

  return btnLang
end

-- Scenes

_G['scene_intro'] = require 'scene_intro'
_G['scene_game'] = require 'scene_game'

local curScene = scene_intro()
local lastScene = nil
local transitionTimer = 0
local currentTransition = nil
local transitions = {}
_G['transitions'] = transitions

_G['replaceScene'] = function (newScene, transition)
  lastScene = curScene
  curScene = newScene
  transitionTimer = 0
  currentTransition = transition or transitions['fade'](0.9, 0.9, 0.9)
end

local mouseScene = nil
function love.mousepressed(x, y, button, istouch, presses)
  if button ~= 1 then return end
  if lastScene ~= nil then return end
  mouseScene = curScene
  curScene.press((x - offsX) / globalScale, (y - offsY) / globalScale)
end
function love.mousemoved(x, y, button, istouch)
  curScene.hover((x - offsX) / globalScale, (y - offsY) / globalScale)
  if mouseScene ~= curScene then return end
  curScene.move((x - offsX) / globalScale, (y - offsY) / globalScale)
end
function love.mousereleased(x, y, button, istouch, presses)
  if button ~= 1 then return end
  if mouseScene ~= curScene then return end
  curScene.release((x - offsX) / globalScale, (y - offsY) / globalScale)
  mouseScene = nil
end

local T = 0
local timeStep = 1 / 240

function love.update(dt)
  T = T + dt
  local count = 0
  bgm_update()
  audio.sfx_update(dt)
  -- No slowdown if graphics run at >= 20 FPS
  while T > timeStep and count < 12 do
    T = T - timeStep
    count = count + 1
    if lastScene ~= nil then
      lastScene:update()
      -- At most 8 ticks per update for transitions
      if count <= 8 then
        transitionTimer = transitionTimer + 1
      end
    else
      curScene:update()
    end
  end
end

transitions['fade'] = function (r, g, b)
  return {
    dur = 120,
    draw = function (x)
      local opacity = 0
      if x < 0.5 then
        lastScene:draw()
        opacity = x * 2
      else
        curScene:draw()
        opacity = 2 - x * 2
      end
      love.graphics.setColor(r, g, b, opacity)
      love.graphics.rectangle('fill', -offsX, -offsY, Wx, Hx)
    end
  }
end

function love.draw()
  love.graphics.scale(globalScale)
  love.graphics.setColor(1, 1, 1)
  love.graphics.push()
  love.graphics.translate(offsX, offsY)
  if lastScene ~= nil then
    local x = transitionTimer / currentTransition.dur
    currentTransition.draw(x)
    if x >= 1 then
      if lastScene.destroy then lastScene.destroy() end
      lastScene = nil
    end
  else
    curScene.draw()
  end
  if not true then
    love.graphics.setColor(0, 0, 0)
    love.graphics.print(love.timer.getFPS(), 2, 280)
  end
  love.graphics.pop()
end

function love.keypressed(key)
  if curScene.key then curScene.key(key) end
  if true then return end
  if key == 'lshift' then
    if not isMobile and not isWeb then
      love.window.setFullscreen(not love.window.getFullscreen())
      updateLogicalDimensions()
    end
  end
end
