local draw = require 'draw_utils'
local button = require 'button'
local audio = require 'audio'
local unpack = unpack or table.unpack

local enqueueRequest, fetchResponse
if love.system.getOS() == 'Web' then
  local id = 0
  local fetchFiles = {}
  enqueueRequest = function (s)
    id = (id + 1) % 1000
    local idStr = string.format('%10d%03d', os.time(), id)
    -- https://emscripten.org/docs/api_reference/Filesystem-API.html
    -- `/tmp` is autmoatically mounted as an MEMFS
    local fetchFile = '/tmp/' .. idStr
    local encoded = {'^'}
    encoded[#encoded + 1] = fetchFile
    encoded[#encoded + 1] = '^'
    for i = 1, #s do
      encoded[#encoded + 1] = string.format('%02x', string.byte(s, i))
    end
    print(table.concat(encoded))
    fetchFiles[#fetchFiles + 1] = fetchFile
  end
  fetchResponse = function ()
    if #fetchFiles > 0 then
      -- Check the first entry
      local path = fetchFiles[1]
      local f = io.open(path, 'rb')
      if f then
        local content = f:read('*a')
        table.remove(fetchFiles, 1)
        f:close()
        os.remove(path)
        return content
      end
    end
  end
else
  -- Local run
  local networkThread = love.thread.newThread('src/network.lua')
  networkThread:start()
  local chReq = love.thread.getChannel('network-req')
  local chResp = love.thread.getChannel('network-resp')
  enqueueRequest = function (s) chReq:push(s) end
  fetchResponse = function () return chResp:pop() end
end

love.physics.setMeter(1)

local createBubbles = function (n, max_x, max_y)
  local scale = 5

  local world = love.physics.newWorld()

  max_x = max_x * scale
  max_y = max_y * scale
  local body_bound = love.physics.newBody(world, 0, 0, 'static')
  local pts = {{-max_x, -max_y}, {-max_x, max_y}, {max_x, max_y}, {max_x, -max_y}, {-max_x, -max_y}}
  for i = 1, 4 do
    local shape = love.physics.newEdgeShape(
      pts[i][1], pts[i][2],
      pts[i + 1][1], pts[i + 1][2]
    )
    local fixt = love.physics.newFixture(body_bound, shape)
    fixt:setRestitution(0.9)  -- Bounce a lot
  end

  local b = {}
  local b_id = {}

  for i = 1, n do
    local x = math.cos(i / n * math.pi * 2) * 1
    local y = math.sin(i / n * math.pi * 2) * 1

    local body = love.physics.newBody(world, x, y, 'dynamic')
    local shape = love.physics.newCircleShape(1e-4 * scale)
    local fixt = love.physics.newFixture(body, shape)

    body:setMass(1)
    body:setLinearDamping(0.5)  -- Damp
    body:setAngularDamping(1.0) -- Damp a lot
    fixt:setRestitution(0.9)    -- Bounce a lot

    b[i] = body
    b_id[body] = i
  end

  local body_cen = love.physics.newBody(world, 0, 0, 'dynamic')
  local shape = love.physics.newCircleShape(1e-4 * scale)
  local fixt = love.physics.newFixture(body_cen, shape)
  body_cen:setMass(10)

  local expected_r

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
  end

  local remove_joints = function ()
    local js = world:getJoints()
    for i = 1, #js do js[i]:destroy() end
  end

  local rebuild_joints = function ()
    remove_joints()
    for i = 1, n do
      local b1 = b[i]
      local x1, y1 = b1:getPosition()

      for j = 1, 3 do
        local b2 = b[(i + j - 1) % n + 1]
        local x2, y2 = b2:getPosition()
        local joint = love.physics.newDistanceJoint(b1, b2, x1, y1, x2, y2)
        joint:setDampingRatio(10) -- Oscillate less
        joint:setLength(expected_r * 2 * math.sin(math.pi / n * j) * scale)
        joint:setFrequency((6 - j) * 0.2 / (0.1 + expected_r)^2.1 * 5)
      end

      local joint = love.physics.newDistanceJoint(b1, body_cen, x1, y1, 0, 0)
      joint:setDampingRatio(0)
      joint:setLength(expected_r * scale)
      joint:setFrequency(0.01 / (0.1 + expected_r)^2.1 * 5)
    end
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

  local T = 0

  local imp_r = 0.1

  local px, py = nil, nil
  local p_start_inside = false

  local hist = {}
  local pop_expired_history = function ()
    while #hist > 1 and hist[1][3] < T - 2.0 do
      table.remove(hist, 1)
    end
  end

  local set_ptr = function (x, y, t)
    pop_expired_history(t)
    if px == nil then
      p_start_inside = check_inside(x, y)
      hist = { { x, y, T } }
    else
      -- If sufficiently far from last record, add a new one
      local lastx, lasty = unpack(hist[#hist])
      local dsq = (x - lastx) * (x - lastx) + (y - lasty) * (y - lasty)
      if dsq >= 100e-4 then
        local m = math.floor(math.sqrt(dsq / 25e-4))
        for i = 1, m do
          local px = lastx + (x - lastx) * i / m
          local py = lasty + (y - lasty) * i / m
          hist[#hist + 1] = { px, py, T }
          if #hist >= 30 then table.remove(hist, 1) end
        end
      elseif dsq >= 25e-4 then
        hist[#hist + 1] = { x, y, T }
        if #hist >= 30 then table.remove(hist, 1) end
      end
    end
    px, py = x * scale, y * scale
  end
  local rel_ptr = function ()
    px, py = nil, nil
  end
  local get_ptr = function ()
    if px then return px / scale, py / scale, imp_r end
    return nil
  end
  local get_ptr_trail = function () return hist, scale end

  local update = function (dt)
    T = T + dt
    if px ~= nil then
      pop_expired_history()
      local min_dist = {}
      local min_dist_dir = {}
      -- Temporarily add current pointer to history
      hist[#hist + 1] = { px / scale, py / scale }
      -- History point is effective if its at the same side of the bubble
      -- (interior/exterior) as the starting point
      local effective = {}
      for i = 1, #hist do
        local px, py = unpack(hist[i])
        px = px * scale
        py = py * scale
        effective[i] = (check_inside(px / scale, py / scale) == p_start_inside)
      end
      -- Find longest effective sequence
      local eff_start, eff_end = 1, 0
      local cur_start
      for i = 1, #hist do
        if effective[i] then
          if not cur_start then cur_start = i end
          if i - cur_start > eff_end - eff_start then
            eff_start, eff_end = cur_start, i
          end
        else
          cur_start = nil
        end
      end
      -- Find each mass point's minimum distance to an effective history point
      for i = eff_start, eff_end do
        local px, py = unpack(hist[i])
        px = px * scale
        py = py * scale
        world:queryBoundingBox(
          px - imp_r * scale, py - imp_r * scale,
          px + imp_r * scale, py + imp_r * scale,
          function (fixt)
            local b = fixt:getBody()
            local x1, y1 = b:getPosition()
            local dx, dy = (x1 - px) / scale, (y1 - py) / scale
            local dsq = dx * dx + dy * dy
            if dsq < imp_r * imp_r then
              local last_min = min_dist[b]
              if last_min == nil or last_min > dsq then
                min_dist[b] = dsq
                min_dist_dir[b] = {dx, dy}
              end
            end
            return true
          end
        )
      end
      -- Remove current pointer
      hist[#hist] = nil
      for b, dsq in pairs(min_dist) do
        local d = math.sqrt(dsq)
        local dx, dy = unpack(min_dist_dir[b])
        local t = 1 - d / imp_r
        local imp_intensity = 1 - t * t
        local imp_scale = 3 * scale * imp_intensity / d
        b:applyForce(dx * imp_scale, dy * imp_scale)
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

  local close = function ()
    world:destroy()
  end

  return {
    set_pos = set_pos,
    get_pos = get_pos,
    get_body = get_body,
    set_size = set_size,
    remove_joints = remove_joints,
    rebuild_joints = rebuild_joints,
    check_inside = check_inside,
    set_ptr = set_ptr,
    rel_ptr = rel_ptr,
    get_ptr = get_ptr,
    get_ptr_trail = get_ptr_trail,
    update = update,
    close = close,
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
            local px = xMin + love.math.random() * (xMax - xMin)
            local py = y + (love.math.random() - 0.5) * yStep
            local vScale = 0.2 + love.math.random() * 0.2
            ps[#ps + 1] = {
              x0 = px, y0 = py,
              x = px, y = py,
              vx = (px - xCen) * vScale,
              vy = (py - yCen) * vScale,
              r = r, g = g, b = b, a = 1,
              t = 0, ttl = 120 + love.math.random() * 120,
            }
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

local blitFilledPolygon, blitOutline

if love.system.getOS() == 'Web' then
blitFilledPolygon = function (p, tex, paintR, paintG, paintB, bubbleOpacity, T)
  local addr = tostring(tex:getPointer()):sub(13) -- 'userdata: 0x'
  local texW, texH = tex:getDimensions()
  local pStr = {}
  for i = 1, #p do
    pStr[i] = string.format('%.7f %.7f', p[i][1], p[i][2])
  end
  print(string.format('+F %s %d %d %.5f %.5f %.5f %.5f %d %s',
    addr, texW, texH, paintR, paintG, paintB, bubbleOpacity, T, table.concat(pStr, ' ')))
end

blitOutline = function (p, tex, paintR, paintG, paintB)
  local addr = tostring(tex:getPointer()):sub(13) -- 'userdata: 0x'
  local texW, texH = tex:getDimensions()
  local pStr = {}
  for i = 1, #p do
    pStr[i] = string.format('%.7f %.7f', p[i][1], p[i][2])
  end
  print(string.format('+O %s %d %d %.5f %.5f %.5f %s',
    addr, texW, texH, paintR, paintG, paintB, table.concat(pStr, ' ')))
end

else
blitFilledPolygon = function (p, tex, paintR, paintG, paintB, bubbleOpacity, T)
  tex:mapPixel(function () return 0, 0, 0, 0 end)

  local texW, texH = tex:getDimensions()
  local n = #p
  -- http://alienryderflex.com/polygon_fill/
  for y = 0, texH - 1 do
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
      if xs[i] >= texW then break end
      if xs[i + 1] >= 0 then
        for x = math.max(0, math.floor(xs[i])), math.min(texW - 1, math.floor(xs[i + 1])) do
          local a = bubbleOpacity * (0.5 + 0.5 * love.math.noise(x / 50, T / 360, y / 50))
          tex:setPixel(x, y, paintR, paintG, paintB, a)
        end
      end
    end
  end
end

blitOutline = function (p, tex, paintR, paintG, paintB)
  local texW, texH = tex:getDimensions()

  local n = #p
  local pts = {}
  for i = 0, n + 2 do
    local x, y = unpack(p[(i - 1 + n) % n + 1])
    pts[i] = { x = x, y = y, knot = (i - 1) / n }
  end
  local x1, y1, index = CatmullRomSpline(0, pts, 0, 0)
  for i = 1, 1000 do
    local t = i / 1000
    local x0, y0, index_new = CatmullRomSpline(t, pts, 0, index)
    -- Distance is less than 1
    if x0 >= 0 and x0 < texW and y0 >= 0 and y0 < texH then
      tex:setPixel(math.floor(x0), math.floor(y0), paintR, paintG, paintB, 1)
    end
    x1, y1, index = x0, y0, index_new
  end
end

end

local targetWords = {
  {zh = '太阳', en = 'Sun'},
  {zh = '月亮/月球', en = 'Moon'},
  {zh = '云/云朵', en = 'Cloud/Clouds'},
  {zh = '苹果', en = 'Apple'},
  {zh = '橙子/橘子/桔子', en = 'Orange/Tangerine/Mandarin'},
  {zh = '香蕉', en = 'Banana'},
  {zh = '水母', en = 'Jellyfish'},
  {zh = '树', en = 'Tree'},
  {zh = '大象', en = 'Elephant'},
  {zh = '蘑菇', en = 'Mushroom'},
  {zh = '花生', en = 'Peanut/Peanuts'},
  {zh = '鱼', en = 'Fish'},
  {zh = '汽车', en = 'Car'},
}

for i = 1, #targetWords do
  for _, lang in ipairs({'zh', 'en'}) do
    local a = {}
    for s in targetWords[i][lang]:gmatch('[^/]+') do
      a[#a + 1] = s
    end
    targetWords[i][lang] = a
  end
end

return function ()
  local s = {}
  local W, H = W, H

  local dispScale = 72

  local btnLang = _G['btnLang']() -- See `main.lua`
  btnLang.enabled = false   -- Enable later, when the word appears

  local n = 100   -- Number of points on the bubble
  local bubbles

  local bubblesRemaining = 3

  local targetWord
  local targetWordText, targetWordTextStr
  -- Words are picked from a randomly shuffled sequence
  local targetWordsPtr = #targetWords
  local randomTargetWord = function ()
    -- Randomly select a target word
    if targetWordsPtr == #targetWords then
      -- Shuffle
      for i = #targetWords, 2, -1 do
        local j = love.math.random(i)
        targetWords[i], targetWords[j] = targetWords[j], targetWords[i]
      end
      targetWordsPtr = 1
    else
      targetWordsPtr = targetWordsPtr + 1
    end
    targetWord = targetWords[targetWordsPtr]
  end

  local previousGuesses

  local Wc, Hc = 144, 180
  local WcEx, HcEx = 10, 10
  local tex = love.image.newImageData(Wc + WcEx * 2, Hc + HcEx * 2, 'rgba8')
  local img = love.graphics.newImage(tex)

  local texCanvas = love.image.newImageData(Wc, Hc, 'rgba8')
  local imgCanvas = love.graphics.newImage(texCanvas)

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
    -- Restart from last ended game
    if state == STATE_FINAL then
      -- Clear textures
      texCanvas:mapPixel(function () return 0, 0, 0, 0 end)
      imgCanvas:replacePixels(texCanvas)
      -- Reset target word (will be drawn after the first bubble is released)
      targetWord = nil
      targetWordText, targetWordTextStr = nil, nil
    end

    bubblesRemaining = bubblesRemaining - 1
    state, sinceState = STATE_INFLATE, 0
    inflateStart = nil
    btnStick.enabled = false

    audio.sfx('bubble_out')
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
    if btnLang.press(x, y) then return true end

    -- Check the buttons first, in case the player changes colour before inflation
    for i = 1, #buttons do if buttons[i].press(x, y) then return true end end

    if state == STATE_INFLATE then
      inflateStart = sinceState
      bubbles = createBubbles(n, 1.1, Hc / Wc * 1.1)
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
    if btnLang.move(x, y) then return true end

    for i = 1, #buttons do if buttons[i].move(x, y) then return true end end
    local x1 = (x - Xc) / dispScale
    local y1 = (y - Yc) / dispScale

    if state == STATE_PAINT then
      bubbles.set_ptr(x1, y1)
    end
  end

  local catThinkFrame = -1
  local catAnswerSeq, catAnswerFrame = -1, -1
  local catAnswerSpeechBubble = 1
  local catBingoFrame = -1
  local catBingoSince = -1  -- Record ticks for differently paced animations, see below

  local slotPullSince = -1

  s.release = function (x, y)
    if btnLang.release(x, y) then return true end

    if state == STATE_INFLATE and inflateStart then
      state, sinceState = STATE_PAINT, 0
      bubbles.rebuild_joints()
      -- Pull the slot at the first bubble release
      if bubblesRemaining == 2 then
        slotPullSince = 0
        randomTargetWord()
        previousGuesses = {}
        btnLang.enabled = true
        audio.sfx('slot', 0.15)
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
          -- Blit onto canvas
          blitOutline(bubblePolygon(Wc / 2, Hc / 2, 0, 0),
            texCanvas, selPaint[1], selPaint[2], selPaint[3])
          imgCanvas:replacePixels(texCanvas)
          -- Create particle effect
          particles.pop(bubblePolygon(Xc, Yc, 0, 0), selPaint[1], selPaint[2], selPaint[3])
          bubbles.close()
          -- Disable & hide language button
          btnLang.enabled = false
          -- Encode image and send to server
          local imageFileData = texCanvas:encode('png')
          local s = imageFileData:getString()
          local reqPayload = { targetWord[_G['lang']][1] }
          for i = 1, #previousGuesses do reqPayload[i + 1] = ',' .. previousGuesses[i] end
          reqPayload[#reqPayload + 1] = '/'
          reqPayload[#reqPayload + 1] = s
          enqueueRequest(table.concat(reqPayload))
          -- Thinking
          catThinkFrame = 1
          -- Move on
          state, sinceState = STATE_INITIAL, 0
          if bubblesRemaining > 0 then
            btnStick.enabled = true
          end

          audio.sfx('bubble_pop')
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
          if love.math.random(3) ~= 0 then
            -- Stop
            catTailStop = 10 + love.math.random(20)
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

        -- Is correct?
        local guessedCorrect = false
        for _, w in ipairs(targetWord[_G['lang']]) do
          if recognitionResult == w then
            guessedCorrect = true
            break
          end
        end
        if catAnswerFrame >= 12 and guessedCorrect then
          catAnswerSeq, catAnswerFrame = -1, -1
          catBingoFrame = 1
          catBingoSince = 0
          rewardCount = rewardCount + 1
          bubblesRemaining = 0
          btnStick.enabled = false
          state, sinceState = STATE_FINAL, 0
          audio.sfx('bingo')
        elseif catAnswerFrame >= 24 and not guessedCorrect then
          catAnswerSeq, catAnswerFrame = -1, -1
          if state == STATE_INITIAL and bubblesRemaining == 0 then
            -- Finalise, regardless
            state, sinceState = STATE_FINAL, 0
          end
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
    if state == STATE_FINAL and sinceState == 720 then
      -- Allow restart
      bubblesRemaining = 3
      btnStick.enabled = true
      audio.sfx('refill')
    end

    particles.update()

    local resp = fetchResponse()
    if resp ~= nil then
      recognitionResult = resp
      recognitionResultText = love.graphics.newText(_G['global_font'](15), resp)
      previousGuesses[#previousGuesses + 1] = recognitionResult

      catThinkFrame = -1
      catAnswerSeq = love.math.random(2)
      catAnswerFrame = 1
      catAnswerSpeechBubble = love.math.random(#speechBubbles)

      audio.sfx('answer')
    end
  end

  s.key = function (key)
    if key == 'space' then rewardCount = rewardCount + 1 end
    if key == '1' then randomTargetWord() end
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
    draw.img('background/' .. tostring(backgroundFrame), 0, backgroundFrame == 0 and 32 or 0)

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
        bubbleOpacity = 0.5 + 0.2 * math.exp(-sinceState / 960)
      end
      -- Blit polygon onto texture
      local p = bubblePolygon(Wc / 2, Hc / 2, WcEx, HcEx)
      blitFilledPolygon(p, tex, paintR, paintG, paintB, bubbleOpacity, T)
      blitOutline(p, tex, paintR, paintG, paintB)

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

    if targetWord then
      local s = targetWord[_G['lang']][1]
      if targetWordTextStr ~= s then
        targetWordText = love.graphics.newText(_G['global_font'](15), s)
        targetWordTextStr = s
      end
      local progress = 1
      if slotPullSince >= 0 then
        progress = math.max(0, math.min(1, (slotPullSince - 400) / 40))
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
      local w = recognitionResultText:getWidth() * t + 16
      love.graphics.setColor(1, 1, 1)
      speechBubbles[catAnswerSpeechBubble].draw(10, 164, math.floor(w + 0.5), 24)
      if catAnswerFrame >= 6 then
        love.graphics.setColor(0, 0, 0)
        love.graphics.draw(recognitionResultText, 18, 169)
      end
    end

    btnLang.draw()

    love.graphics.setColor(1, 1, 1)
  end

  s.destroy = function ()
  end

  return s
end
