local component = require("component")
local event = require("event")
local term = require("term")
local computer = require("computer")
local gpu = component.gpu
local modem = component.modem

-------------------------------------------------
-- НАСТРОЙКИ ИГРОКА (МЕНЯТЬ ЗДЕСЬ)
-------------------------------------------------

local NICK = "Player1"

-- основной цвет игрока
local PLAYER_COLOR = 0x0000FF

-- таблица популярных цветов
local COLORS = {
  white = 0xFFFFFF,
  black = 0x000000,
  red   = 0xFF0000,
  green = 0x00FF00,
  blue  = 0x0000FF,
  yellow = 0xFFFF00,
  cyan   = 0x00FFFF,
  purple = 0xAA00FF
}

-- сетевые настройки
local PORT = 4242

-------------------------------------------------

modem.open(PORT)

gpu.setResolution(gpu.maxResolution())
term.clear()

local width, height = gpu.getResolution()

local player = {
  x = math.floor(width / 2),
  y = math.floor(height / 2),
  size = 2,
  nick = NICK,
  color = PLAYER_COLOR
}

local others = {}

local MOVE_DELAY = 0.1
local lastMove = 0

local function drawSquare(x, y, size, color)
  gpu.setForeground(color)
  for dx = 0, size - 1 do
    for dy = 0, size - 1 do
      gpu.set(x + dx, y + dy, "█")
    end
  end
end

local function drawNick(x, y, nick)
  gpu.setForeground(0xFFFFFF)
  gpu.set(x, y - 1, nick)
end

local function redraw()
  term.clear()

  -- другие игроки
  for _, p in pairs(others) do
    drawNick(p.x, p.y, p.nick)
    drawSquare(p.x, p.y, p.size, p.color)
  end

  -- ты
  drawNick(player.x, player.y, player.nick)
  drawSquare(player.x, player.y, player.size, player.color)
end

local function broadcastState()
  modem.broadcast(
    PORT,
    player.nick,
    player.x,
    player.y,
    player.size,
    player.color
  )
end

redraw()
broadcastState()

while true do
  local e = {event.pull(0.05)}

  if e[1] == "key_down" then
    local key = e[4]
    local now = computer.uptime()

    if key == 16 then -- Q
      term.clear()
      break
    end

    if now - lastMove >= MOVE_DELAY then
      if key == 17 and player.y > 2 then
        player.y = player.y - 1
      elseif key == 31 and player.y + player.size - 1 < height then
        player.y = player.y + 1
      elseif key == 30 and player.x > 1 then
        player.x = player.x - 1
      elseif key == 32 and player.x + player.size - 1 < width then
        player.x = player.x + 1
      end

      lastMove = now
      broadcastState()
      redraw()
    end

  elseif e[1] == "modem_message" then
    local _, _, _, _, nick, x, y, size, color = table.unpack(e)

    if nick ~= player.nick then
      others[nick] = {
        nick = nick,
        x = x,
        y = y,
        size = size,
        color = color
      }
      redraw()
    end
  end
end

