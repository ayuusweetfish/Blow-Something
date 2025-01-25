local chReq = love.thread.getChannel('network-req')
local chResp = love.thread.getChannel('network-resp')

local http = require 'socket.http'
local ltn12 = require 'ltn12'

while true do
  local msg = chReq:demand()  -- Blocking

  local resp = {}
  http.request {
    url = 'http://127.0.0.1:25126/look',
    method = 'POST',
    headers = { ['Content-Length'] = #msg },
    source = ltn12.source.string(msg),
    sink = ltn12.sink.table(resp),
  }
  chResp:push(table.concat(resp))
end
