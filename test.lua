local component = require("component")
local event = require("event")
local term = require("term")
local computer = require("computer")
local gpu = component.gpu
local modem = component.modem

-------------------------------------------------
-- НАСТРОЙКИ
-------------------------------------------------

local NICK = "Player1"
local PLAYER_COLOR = 0x0000FF

local COLORS = {
  white  = 0xFFFFFF,
  red    = 0xFF0000,
  green  = 0x00FF00,
  blue   = 0x0000FF,
  yellow = 0xFFFF00,
  cyan   = 0x00FFFF,
  purple = 0xAA00FF
}

local PORT = 4242

-- размеры поля
local FIELD_WIDTH  = 40
local FIELD_HEIGHT = 16

-- высота чата
local CHAT_HEIGHT = 6
local MAX_CHAT_LINES = CHAT_HEIGHT - 1

-------------------------------------------------

modem.open(PORT)
gpu.setResolution(gpu.maxResolution())
term.clear()

local screenW, screenH = gpu.getResolution()

-- координаты поля
local fieldX = math.floor((screenW - FIELD_WIDTH) / 2)
local fieldY = 1

local chatY = FIELD_HEIGHT + 3

-------------------------------------------------
-- ИГРОВЫЕ ДАННЫЕ
-------------------------------------------------

local player = {
  x = math.floor(FIELD_WIDTH / 2),
  y = math.floor(FIELD_HEIGHT / 2),
  size = 2,
  nick = NICK,
  color = PLAYER_COLOR
}

local others = {}
local chat = {}

local MOVE_DELAY = 0.1
local lastMove = 0
local chatMode = false
local chatBuffer = ""

-------------------------------------------------
-- ВСПОМОГАТЕЛЬНОЕ
-------------------------------------------------

local function rectsIntersect(a, b)
  return not (
    a.x + a.size - 1 < b.x or
    a.x > b.x + b.size - 1 or
    a.y + a.size - 1 < b.y or
    a.y > b.y + b.size - 1
  )
end

local function canMoveTo(nx, ny)
  local test = {x = nx, y = ny, size = player.size}
  for _, p in pairs(others) do
    if rectsIntersect(test, p) then
      return false
    end
  end
  return true
end

-------------------------------------------------
-- ОТРИСОВКА
-------------------------------------------------

local function drawBorder()
  gpu.setForeground(0xFFFFFF)
  for x = 0, FIELD_WIDTH + 1 do
    gpu.set(fieldX + x, fieldY, "#")
    gpu.set(fieldX + x, fieldY + FIELD_HEIGHT + 1, "#")
  end
  for y = 0, FIELD_HEIGHT + 1 do
    gpu.set(fieldX, fieldY + y, "#")
    gpu.set(fieldX + FIELD_WIDTH + 1, fieldY + y, "#")
  end
end

local function drawSquare(px, py, size, color)
  gpu.setForeground(color)
  for dx = 0, size - 1 do
    for dy = 0, size - 1 do
      gpu.set(fieldX + px + dx, fieldY + py + dy, "█")
    end
  end
end

local function drawNick(px, py, nick)
  gpu.setForeground(0xFFFFFF)
  gpu.set(fieldX + px, fieldY + py - 1, nick)
end

local function drawChat()
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, chatY, screenW, CHAT_HEIGHT, " ")

  local start = math.max(1, #chat - MAX_CHAT_LINES + 1)
  local line = 0

  for i = start, #chat do
    local msg = chat[i]
    gpu.setForeground(msg.color)
    gpu.set(2, chatY + line, msg.nick .. ":")
    gpu.setForeground(0xFFFFFF)
    gpu.set(2 + #msg.nick + 2, chatY + line, msg.text)
    line = line + 1
  end

  if chatMode then
    gpu.setForeground(0xFFFFFF)
    gpu.set(2, chatY + CHAT_HEIGHT - 1, "> " .. chatBuffer)
  end
end

local function redraw()
  term.clear()
  drawBorder()

  for _, p in pairs(others) do
    drawNick(p.x, p.y, p.nick)
    drawSquare(p.x, p.y, p.size, p.color)
  end

  drawNick(player.x, player.y, player.nick)
  drawSquare(player.x, player.y, player.size, player.color)

  drawChat()
end

-------------------------------------------------
-- СЕТЬ
-------------------------------------------------

local function broadcastState()
  modem.broadcast(PORT, "state",
    player.nick, player.x, player.y, player.size, player.color)
end

local function broadcastChat(text)
  modem.broadcast(PORT, "chat",
    player.nick, player.color, text)
end

-------------------------------------------------

redraw()
broadcastState()

while true do
  local e = {event.pull(0.05)}

  if e[1] == "key_down" then
    local key = e[4]
    local char = e[3]

    if chatMode then
      if key == 28 then -- Enter
        if #chatBuffer > 0 then
          table.insert(chat, {nick = player.nick, color = player.color, text = chatBuffer})
          broadcastChat(chatBuffer)
        end
        chatBuffer = ""
        chatMode = false
        redraw()
      elseif key == 14 then -- Backspace
        chatBuffer = chatBuffer:sub(1, -2)
        redraw()
      elseif char and char >= 32 and char <= 126 then
        chatBuffer = chatBuffer .. string.char(char)
        redraw()
      end

    else
      if key == 16 then -- Q
        break
      elseif key == 20 then -- T
        chatMode = true
        redraw()
      else
        local now = computer.uptime()
        if now - lastMove >= MOVE_DELAY then
          local nx, ny = player.x, player.y

          if key == 17 then ny = ny - 1 end
          if key == 31 then ny = ny + 1 end
          if key == 30 then nx = nx - 1 end
          if key == 32 then nx = nx + 1 end

          if nx >= 1 and ny >= 1 and
             nx + player.size - 1 <= FIELD_WIDTH and
             ny + player.size - 1 <= FIELD_HEIGHT and
             canMoveTo(nx, ny) then

            player.x = nx
            player.y = ny
            lastMove = now
            broadcastState()
            redraw()
          end
        end
      end
    end

  elseif e[1] == "modem_message" then
    local _, _, _, _, mtype, a, b, c, d, e2 = table.unpack(e)

    if mtype == "state" then
      local nick, x, y, size, color = a, b, c, d, e2
      if nick ~= player.nick then
        others[nick] = {nick = nick, x = x, y = y, size = size, color = color}
        redraw()
      end

    elseif mtype == "chat" then
      local nick, color, text = a, b, c
      table.insert(chat, {nick = nick, color = color, text = text})
      redraw()
    end
  end
end

-------------------------------------------------
-- КОРРЕКТНЫЙ ВЫХОД
-------------------------------------------------

term.clear()
gpu.setForeground(0xFFFFFF)
gpu.setBackground(0x000000)
