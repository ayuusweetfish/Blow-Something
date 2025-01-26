local draw = require 'draw_utils'
local button = require 'button'
local unpack = unpack or table.unpack

local networkThread = love.thread.newThread('src/network.lua')
networkThread:start()
local chReq = love.thread.getChannel('network-req')
local chResp = love.thread.getChannel('network-resp')

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

  local expected_r

  local joints_inflating = {}
  local set_size = function (r)
    expected_r = r
    for i = 1, n do
      local x = math.cos(i / n * math.pi * 2) * expected_r
      local y = math.sin(i / n * math.pi * 2) * expected_r
      x = x + (love.math.noise(x*0.6 - 15, y*0.6) - 0.5) * 7e-2 * expected_r
      y = y + (love.math.noise(x*0.6, y*0.6 + 10) - 0.5) * 7e-2 * expected_r
      b[i]:setPosition(x * scale * 0.94, y * scale * 0.94)
      b[i]:setLinearVelocity(0, 0)
      b[i]:setAngularVelocity(0)
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
        freq_rate = (j == 3 and 3 or 4) * 0.2
      }
    end

    local joint = love.physics.newDistanceJoint(b1, body_cen, x1, y1, 0, 0)
    joint:setDampingRatio(0)
    joint:setFrequency(0.05)
    joints_inflating[#joints_inflating + 1] = {
      joint = joint,
      rate = 1 * scale,
      freq_rate = 0.05 * 0.2,
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

  local check_inside = function (x, y)
    x, y = x * scale, y * scale
    -- http://alienryderflex.com/polygon/
    local x1, y1 = b[n]:getPosition()
    local parity = false
    for i = 1, n do
      local x0, y0 = b[i]:getPosition()
      if ((y0 < y and y1 >= y) or (y1 < y) and (y0 >= y)) and
        (x0 <= x or x1 <= x)
      then
        local w = (x0 + (y - y0) / (y1 - y0) * (x1 - x0) < x)
        parity = not (parity == w)
      end
      x1, y1 = x0, y0
    end
    return parity
  end

  local imp_r = 0.1

  local px, py = nil, nil
  local p_start_inside = false
  local plx, ply = nil, nil -- Last position of effect
  local set_ptr = function (x, y)
    if px == nil then
      p_start_inside = check_inside(x, y)
      plx, ply = x * scale, y * scale
    end
    px, py = x * scale, y * scale
  end
  local rel_ptr = function ()
    px, py = nil, nil
    plx, ply = nil, nil
  end
  local get_ptr = function ()
    if px then return px / scale, py / scale, imp_r end
    return nil
  end

  local update = function (dt)
    if px ~= nil then
      local effective = (check_inside(px / scale, py / scale) == p_start_inside)
      if effective then
        plx, ply = px, py
      else
        -- Nudge effective position towards pointer
        -- TODO if time allows: if `(plx, ply)` is valid, nudge it towards pointer;
        -- otherwise, nudge it against
      end
      if effective then
        world:queryBoundingBox(
          plx - imp_r * scale, ply - imp_r * scale,
          plx + imp_r * scale, ply + imp_r * scale,
          function (fixt)
            local b = fixt:getBody()
            local x1, y1 = b:getPosition()
            local dx, dy = (x1 - plx) / scale, (y1 - ply) / scale
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
    end

    -- Repulsive force among close points to prevent self-intersection
    local rep_r = 3.0 * (math.pi * 2 / n * expected_r) * scale
    -- Scan and find near pairs
    local p = {}
    for i = 1, n do
      p[i] = { i = i, x = b[i]:getX(), y = b[i]:getY() }
    end
    table.sort(p, function (a, b) return a.x < b.x end)
    -- Sliding window
    local j = 1
    for i = 1, n do
      while j < i and p[j].x < p[i].x - rep_r do j = j + 1 end
      for k = j, i - 1 do
        local dx = p[i].x - p[k].x
        local dy = p[i].y - p[k].y
        local dsq = dx * dx + dy * dy
        local rep_r_cur = rep_r
        local indexDiff = math.abs(p[i].i - p[k].i)
        indexDiff = math.min(indexDiff, n - indexDiff)
        if indexDiff < 5 then
          rep_r_cur = rep_r / 5 * indexDiff
        end
        if dsq < rep_r_cur * rep_r_cur then
          local d = math.sqrt(dsq)
          local intensity = 1 - (d / rep_r_cur) ^ 2
          local rep_scale = 5e-1 * scale * intensity / d
          b[p[i].i]:applyForce(dx * rep_scale, dy * rep_scale)
          b[p[k].i]:applyForce(-dx * rep_scale, -dy * rep_scale)
        end
      end
    end

    world:update(dt)
  end

  return {
    set_pos = set_pos,
    get_pos = get_pos,
    get_body = get_body,
    set_size = set_size,
    check_inside = check_inside,
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

local particles = function ()
  local ps = {}

  -- p: {{x, y} * n}
  local pop = function (p, r, g, b)
    local n = #p
    local yMin, yMax = 1e8, -1e8
    local xCen, yCen = 0, 0
    for i = 1, n do
      local x, y = unpack(p[i])
      yMin = math.min(yMin, y)
      yMax = math.max(yMax, y)
      xCen = xCen + x
      yCen = yCen + y
    end
    xCen = xCen / n
    yCen = yCen / n
    -- http://alienryderflex.com/polygon_fill/
    local yStep = math.max(6, (yMax - yMin) / math.ceil((yMax - yMin) / 10))
    local xDensity = yStep
    for y = yMin, yMax, yStep do
      local xs = {}
      local x1, y1 = unpack(p[n])
      for i = 1, n do
        local x0, y0 = unpack(p[i])
        if (y0 < y and y1 >= y) or (y1 < y and y0 >= y) then
          xs[#xs + 1] = x0 + (y - y0) / (y1 - y0) * (x1 - x0)
        end
        x1, y1 = x0, y0
      end
      table.sort(xs)
      for i = 1, #xs - 1, 2 do
        if xs[i] >= W then break end
        if xs[i + 1] >= 0 then
          local xMin = math.max(0, xs[i])
          local xMax = math.min(W, xs[i + 1])
          local count = math.ceil((xMax - xMin) / xDensity)
          for t = 1, count do
            local px = xMin + math.random() * (xMax - xMin)
            local py = y + (math.random() - 0.5) * yStep
            local vScale = 0.2 + math.random() * 0.2
            ps[#ps + 1] = {
              x0 = px, y0 = py,
              x = px, y = py,
              vx = (px - xCen) * vScale,
              vy = (py - yCen) * vScale,
              r = r, g = g, b = b, a = 1,
              t = 0, ttl = 120 + math.random() * 120,
            }
            -- print(px, py)
          end
        end
      end
    end
  end

  local update = function ()
    local dt = 1 / 240
    local i = 1
    while i <= #ps do
      local p = ps[i]
      local expProgress = math.exp(-p.t / p.ttl * 6)
      local alpha = expProgress * (1 - p.t / p.ttl)
      -- Wow such particles
      p.x = p.x0 + p.vx * (1 - expProgress)
      p.y = p.y0 + p.vy * (1 - expProgress) + (p.t / 240) * (p.vy * 4 + (p.t / 240) * 100)
      p.t = p.t + 1
      p.a = alpha
      if p.t >= p.ttl then
        ps[i] = ps[#ps]
        ps[#ps] = nil
      else
        i = i + 1
      end
    end
  end

  local draw = function ()
    for i = 1, #ps do
      love.graphics.setColor(ps[i].r, ps[i].g, ps[i].b, ps[i].a)
      love.graphics.rectangle('fill',
        math.floor(ps[i].x + 0.5),
        math.floor(ps[i].y + 0.5),
        1, 1)
    end
  end

  return {
    pop = pop,
    update = update,
    draw = draw,
  }
end

local borderSlice9 = function (tex, borderWidth)
  local w, h = tex:getDimensions()
  local quads = {}
  local quadDimensions = {}
  local xs = {0, borderWidth, w - borderWidth, w}
  local ys = {0, borderWidth, h - borderWidth, h}
  for r = 1, 3 do
    for c = 1, 3 do
      local i = (r - 1) * 3 + c
      quads[i] = love.graphics.newQuad(
        xs[c], ys[r], xs[c + 1] - xs[c], ys[r + 1] - ys[r], w, h)
      quadDimensions[i] = {xs[c + 1] - xs[c], ys[r + 1] - ys[r]}
    end
  end

  local draw = function (x, y, w, h)
    local xs = {0, borderWidth, w - borderWidth, w}
    local ys = {0, borderWidth, h - borderWidth, h}
    for r = 1, 3 do
      for c = 1, 3 do
        local i = (r - 1) * 3 + c
        local qw, qh = unpack(quadDimensions[i])
        love.graphics.draw(tex, quads[i],
          x + xs[c], y + ys[r], 0,
          (xs[c + 1] - xs[c]) / qw,
          (ys[r + 1] - ys[r]) / qh)
      end
    end
  end

  return {
    draw = draw,
  }
end

local targetWords = {
  '大象', '蘑菇', '狗', '太阳', '月亮', '红绿灯',
  '苹果', '橘子', '水母', '树', '房子', '水滴',
}

return function ()
  local s = {}
  local W, H = W, H

  local dispScale = 72

  local n = 100
  local p = {}
  for i = 1, n do
    p[i] = {
      math.cos(i / n * math.pi * 2) * 0.1,
      math.sin(i / n * math.pi * 2) * 0.1,
    }
  end
  local bubbles = bubbles(p)

  local bubblesRemaining = 3

  local targetWord, targetWordText
  local setTargetWord = function (word)
    targetWord = word
    targetWordText = love.graphics.newText(_G['global_font'](14), word)
  end

  local STATE_INITIAL = 0
  local STATE_INFLATE = 1
  local STATE_PAINT = 2
  local STATE_FINAL = 3

  local state, sinceState = STATE_INITIAL, 0

  local inflateStart = nil
  local paintPressStart = nil
  local paintPressX0, paintPressY0

  local buttons = {}
  local btnStick
  btnStick = button({ x = 131, y = 197, w = 18, h = 79 }, function ()
    print('start inflating')
    bubblesRemaining = bubblesRemaining - 1
    state, sinceState = STATE_INFLATE, 0
    inflateStart = nil
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
  paletteButton(45, 266, 18, 17, 1, .19, .30)
  paletteButton(65, 266, 21, 17, 1, .60, .14)
  paletteButton(87, 266, 22, 17, .72, .67, .25)
  paletteButton(45, 284, 18, 23, .58, .60, .92)
  paletteButton(65, 284, 21, 23, 1, .20, .81)
  paletteButton(87, 284, 22, 23, .62, .93, .98)
  paletteButton(106, 269, 17, 38, .5, .5, .5)

  local speechBubbles = {
    borderSlice9(draw.get('speech_1'), 7),
    borderSlice9(draw.get('speech_2'), 7),
    borderSlice9(draw.get('speech_3'), 7),
    borderSlice9(draw.get('speech_4'), 7),
  }

  local rewardPositions = {
    {17, 300},
    {106, 285},
    {132, 279},
    {159, 227},
    {150, 291},
    {131, 297},
    {16, 278},
    {108, 268},
    {3, 276},
    {0, 224},
  }
  local rewardCount = 0

  local Xc = W * 0.5
  local Yc = 156
  local blitCurrentBubbleOntoCanvas

  local particles = particles()
  local bubblePolygon = function (Xc, Yc, WcEx, HcEx)
    local p = {}
    for i = 1, n do
      local x0, y0 = bubbles.get_pos(i)
      x0 = Xc + x0 * dispScale + WcEx
      y0 = Yc + y0 * dispScale + HcEx
      p[i] = { x0, y0 }
    end
    return p
  end

  local recognitionResult
  local recognitionResultText

  s.press = function (x, y)
    -- Check the buttons first, in case the player changes colour before inflation
    for i = 1, #buttons do if buttons[i].press(x, y) then return true end end

    if state == STATE_INFLATE then
      inflateStart = sinceState
      return true
    end

    local x1 = (x - Xc) / dispScale
    local y1 = (y - Yc) / dispScale

    if state == STATE_PAINT then
      bubbles.set_ptr(x1, y1)
      paintPressStart = sinceState
      paintPressX0, paintPressY0 = x, y
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

  local texCanvas

  local catThinkFrame = -1
  local catAnswerSeq, catAnswerFrame = -1, -1
  local catAnswerSpeechBubble = 1
  local catBingoFrame = -1
  local catBingoSince = -1  -- Record ticks for differently paced animations, see below

  local slotPullSince = -1

  s.release = function (x, y)
    if state == STATE_INFLATE and inflateStart then
      print('start painting', sinceState - inflateStart)
      state, sinceState = STATE_PAINT, 0
      -- Pull the slot at the first bubble release
      if bubblesRemaining == 2 then
        slotPullSince = 0
        setTargetWord(targetWords[math.random(#targetWords)])
      end
    end

    for i = 1, #buttons do if buttons[i].release(x, y) then return true end end

    if state == STATE_PAINT then
      bubbles.rel_ptr()
      if paintPressStart and sinceState - paintPressStart <= 120 and
        (x - paintPressX0) * (x - paintPressX0) +
        (y - paintPressY0) * (y - paintPressY0) <= 20
      then
        local x1 = (x - Xc) / dispScale
        local y1 = (y - Yc) / dispScale
        -- Is inside?
        if bubbles.check_inside(x1, y1) then
          -- Pop the bubble
          blitCurrentBubbleOntoCanvas()
          particles.pop(bubblePolygon(Xc, Yc, 0, 0), selPaint[1], selPaint[2], selPaint[3])
          -- Encode image and send to server
          local imageFileData = texCanvas:encode('png')
          local s = imageFileData:getString()
          chReq:push(s)
          -- Thinking
          catThinkFrame = 1
          -- Move on
          if bubblesRemaining > 0 then
            state, sinceState = STATE_INITIAL, 0
            btnStick.enabled = true
          else
            state, sinceState = STATE_FINAL, 0
          end
        end
      end
    end
  end

  local T = 0
  local catTailFrame = 1
  local catTailStop = -1

  s.update = function ()
    T = T + 1
    if T % 30 == 0 then
      -- Cat animations
      -- Tail
      if catTailStop >= 0 then
        catTailStop = catTailStop - 1
      else
        catTailFrame = catTailFrame % 8 + 1
        if catTailFrame == 1 or catTailFrame == 5 then
          if math.random(3) ~= 0 then
            -- Stop
            catTailStop = 10 + math.random(20)
          end
        end
      end

      -- Thinking
      if catThinkFrame > 0 then
        catThinkFrame = catThinkFrame % 10 + 1
      end
      -- Answering
      if catAnswerFrame > 0 then
        catAnswerFrame = catAnswerFrame + 1
        if catAnswerFrame > 24 then
          catAnswerSeq, catAnswerFrame = -1, -1
        end
      end
      -- Bingo
      if catBingoFrame > 0 then
        catBingoFrame = catBingoFrame + 1
        if catBingoFrame > 14 then
          catBingoFrame = -1
        end
      end
    end
    if catBingoSince >= 0 then catBingoSince = catBingoSince + 1 end
    if slotPullSince >= 0 then
      slotPullSince = slotPullSince + 1
      if slotPullSince >= 720 then slotPullSince = -1 end
    end

    sinceState = sinceState + 1
    if state == STATE_INFLATE and inflateStart then
      local t = (sinceState - inflateStart) / 240
      bubbles.set_size(0.1 + 0.8 * (1 - math.exp(-t))^2)
    end
    if (state == STATE_INFLATE and inflateStart) or state == STATE_PAINT then
      bubbles.update(1 / 240)
    end

    particles.update()

    local resp = chResp:pop()
    if resp ~= nil then
      recognitionResult = resp
      recognitionResultText = love.graphics.newText(_G['global_font'](14), resp)
      catThinkFrame = -1
      -- Is correct?
      if state == STATE_FINAL then
        catBingoFrame = 1
        catBingoSince = 0
        rewardCount = rewardCount + 1
      else
        catAnswerSeq = math.random(2)
        catAnswerFrame = 1
      end
      catAnswerSpeechBubble = math.random(#speechBubbles)
    end
  end

  s.key = function (key)
    if key == 'space' then rewardCount = rewardCount + 1 end
  end

  local Wc, Hc = 144, 180
  local WcEx, HcEx = 10, 10
  local tex = love.image.newImageData(Wc + WcEx * 2, Hc + HcEx * 2, 'rgba8')
  local img = love.graphics.newImage(tex)

  texCanvas = love.image.newImageData(Wc, Hc, 'rgba8')
  local imgCanvas = love.graphics.newImage(texCanvas)

  local drawBubbleOutline = function (tex, WcEx, HcEx, paintR, paintG, paintB)
    local pts = {}
    for i = 0, n + 2 do
      local x, y = bubbles.get_pos((i - 1 + n) % n + 1)
      local x0 = Wc / 2 + x * dispScale + WcEx
      local y0 = Hc / 2 + y * dispScale + HcEx
      pts[i] = { x = x0, y = y0, knot = (i - 1) / n }
    end
    local x1, y1, index = CatmullRomSpline(0, pts, 0, 0)
    for i = 1, 1000 do
      local t = i / 1000
      local x0, y0, index_new = CatmullRomSpline(t, pts, 0, index)
      -- Distance is less than 1
      if x0 >= 0 and x0 < Wc + WcEx * 2 and y0 >= 0 and y0 < Hc + HcEx then
        tex:setPixel(math.floor(x0), math.floor(y0), paintR, paintG, paintB, 1)
      end
      x1, y1, index = x0, y0, index_new
    end
  end

  blitCurrentBubbleOntoCanvas = function ()
    drawBubbleOutline(texCanvas, 0, 0, selPaint[1], selPaint[2], selPaint[3])
    imgCanvas:replacePixels(texCanvas)
  end

  local confetti = draw.get('confetti')
  local confettiW, confettiH = confetti:getDimensions()
  local confettiQuads = {}
  for i = 1, 20 do
    confettiQuads[i] = love.graphics.newQuad(
      confettiW / 5 * (i % 5),
      confettiH / 4 * math.floor(i / 5),
      confettiW / 5,
      confettiH / 4,
      confettiW,
      confettiH
    )
  end

  s.draw = function ()
    love.graphics.clear(1, 1, 1)

    love.graphics.setColor(1, 1, 1)
    local backgroundFrame = 0
    if catBingoSince >= 0 then
      backgroundFrame = 1 + math.floor(catBingoSince / 30)
      if backgroundFrame >= 8 then backgroundFrame = 0 end
    end
    draw.img('background/' .. tostring(backgroundFrame), 0, 32)

    -- Canvas background
    draw.img('blackboard', 15, 59)
    -- love.graphics.setColor(1, 0.96, 0.92, 0.8)
    -- love.graphics.rectangle('fill', Xc - Wc / 2, Yc - Hc / 2, Wc, Hc)

    -- Previous bubbles
    love.graphics.setBlendMode('alpha')
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(imgCanvas,
      math.floor(Xc - Wc / 2),
      math.floor(Yc - Hc / 2),
      0, dispScale * 2 / Wc)

    local paintR, paintG, paintB = selPaint[1], selPaint[2], selPaint[3]

    if (state == STATE_INFLATE and inflateStart) or state == STATE_PAINT then
      -- Bubble
      local bubbleOpacity = 0.7
      if state == STATE_PAINT then
        bubbleOpacity = 0.3 + 0.4 * math.exp(-sinceState / 960)
      end
      -- Clear texture
      tex:mapPixel(function () return 0, 0, 0, 0 end)
      -- Blit polygon onto texture
      local p = bubblePolygon(Wc / 2, Hc / 2, WcEx, HcEx)
      -- http://alienryderflex.com/polygon_fill/
      for y = 0, Hc + HcEx * 2 - 1 do
        local xs = {}
        local x1, y1 = unpack(p[n])
        for i = 1, n do
          local x0, y0 = unpack(p[i])
          if (y0 < y and y1 >= y) or (y1 < y and y0 >= y) then
            xs[#xs + 1] = x0 + (y - y0) / (y1 - y0) * (x1 - x0)
          end
          x1, y1 = x0, y0
        end
        table.sort(xs)
        for i = 1, #xs - 1, 2 do
          if xs[i] >= Wc + WcEx * 2 then break end
          if xs[i + 1] >= 0 then
            for x = math.max(0, math.floor(xs[i])), math.min(Wc + WcEx * 2 - 1, math.floor(xs[i + 1])) do
              local a = bubbleOpacity * (0.7 + 0.3 * love.math.noise(x / 50, T / 360, y / 50))
              tex:setPixel(x, y, paintR, paintG, paintB, a)
            end
          end
        end
      end
      -- Draw lines onto texture
      drawBubbleOutline(tex, HcEx, WcEx, paintR, paintG, paintB)

      img:replacePixels(tex)
      love.graphics.setBlendMode('alpha')
      love.graphics.setColor(1, 1, 1)
      love.graphics.draw(img,
        math.floor(Xc - Wc / 2 - WcEx),
        math.floor(Yc - Hc / 2 - HcEx),
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

    -- More screen elements
    love.graphics.setColor(1, 1, 1)

    draw.img('top', 0, 0)
    local slotFrame = 1
    if slotPullSince >= 0 then
      local t = slotPullSince / 80
      local n = math.max(0, math.min(1, t, 5 - t))
      slotFrame = (n >= 1 and 3 or (n > 0 and 2 or 1))
    end
    draw.img('slot_' .. tostring(slotFrame), 52, 10)

    if targetWordText then
      local progress = 1
      if slotPullSince >= 0 then
        progress = math.max(0, math.min(1, (slotPullSince - 480) / 40))
      end
      love.graphics.setColor(0.53, 0.25, 0.36, progress)
      love.graphics.draw(targetWordText, math.floor(88 - targetWordText:getWidth() / 2), 19)
    end

    love.graphics.setColor(1, 1, 1)
    local drawTail = function ()
      draw.img('cat_tail/' .. tostring(catTailFrame), 10 - 32, 198)
    end
    if catThinkFrame > 0 then
      drawTail()
      draw.img('cat_think/' .. tostring(catThinkFrame), 10 - 19, 198 - 20)
    elseif catAnswerFrame > 0 then
      drawTail()
      local mappedFrame = math.max(1, math.min(3, catAnswerFrame, 25 - catAnswerFrame))
      draw.img('cat_answ/' .. tostring(catAnswerSeq) .. '_' ..
        tostring(mappedFrame), 10 - 19, 198 - 20)
    elseif catBingoFrame > 0 then
      if catBingoFrame >= 10 and catBingoFrame <= 12 then
        -- Empty frame
      else
        local mappedFrame = catBingoFrame - (catBingoFrame > 12 and 3 or 0)
        draw.img('cat_bingo/' .. tostring(mappedFrame), 10 - 19, 198 - 20)
      end
    else
      drawTail()
      local catBodyFrame = math.floor(T / 30) % 4 + 1
      draw.img('cat_idle/' .. tostring(catBodyFrame), 10 - 19, 198 - 20)
    end

    for i = 1, bubblesRemaining do
      draw.img('stick_small', 132 + (i - 1) * 2, 198)
    end
    draw.img('bottle', 132, 237)
    draw.img('palette', 42, 262)
    draw.img('camera', 143, 263)

    -- Rewards
    -- Fish task goes behind others
    if rewardCount >= 10 then
      local frame = math.floor(T / 60) % 10 + 1
      draw.img('rewards/10_' .. tostring(frame), rewardPositions[10][1], rewardPositions[10][2])
    end
    for i = 1, math.min(9, rewardCount) do
      draw.img('rewards/' .. tostring(i), rewardPositions[i][1], rewardPositions[i][2])
    end

    if state == STATE_INFLATE then
      draw.img('stick_large', 98, 155)
    end

    particles.draw()

    if catBingoSince >= 0 and catBingoSince < 400 then
      local frame = math.floor(catBingoSince / 20) + 1
      love.graphics.setColor(1, 1, 1)
      love.graphics.draw(confetti, confettiQuads[frame], 0, 0, 0, W / (confettiW / 5))
    end

    if catAnswerFrame >= 0 and recognitionResult ~= nil then
      local t = math.min(1, catAnswerFrame / 4)
      local w = recognitionResultText:getWidth() * t + 14
      love.graphics.setColor(1, 1, 1)
      speechBubbles[catAnswerSpeechBubble].draw(10, 158, math.floor(w + 0.5), 24)
      if catAnswerFrame >= 6 then
        love.graphics.setColor(0, 0, 0)
        love.graphics.draw(recognitionResultText, 18, 163)
      end
    end
  end

  s.destroy = function ()
  end

  return s
end
