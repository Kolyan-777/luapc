local component = require("component")
local event = require("event")
local term = require("term")
local computer = require("computer")
local gpu = component.gpu
local modem = component.modem
local unicode = require("unicode")
local math = require("math")

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
local FIELD_WIDTH  = 60
local FIELD_HEIGHT = 22
local CHAT_HEIGHT  = 6
local MAX_CHAT_MESSAGES = 7

-------------------------------------------------
-- ИНИЦИАЛИЗАЦИЯ
-------------------------------------------------
modem.open(PORT)
gpu.setResolution(gpu.maxResolution())
term.clear()
math.randomseed(computer.uptime() * 1000)

local screenW, screenH = gpu.getResolution()
local fieldX = math.floor((screenW - FIELD_WIDTH) / 2)
local fieldY = 1
local chatY = FIELD_HEIGHT + 3

-- уникальный ID игрока
local playerID = tostring(math.random(1, 99999999))

local player = {
  id = playerID,
  x = math.floor(FIELD_WIDTH/2),
  y = math.floor(FIELD_HEIGHT/2),
  size = 2,
  nick = NICK,
  color = PLAYER_COLOR
}

local others = {}  -- ключ = ID чужого игрока
local chat = {}
local chatMode = false
local chatBuffer = ""
local MOVE_DELAY = 0.1
local lastMove = 0

-------------------------------------------------
-- ФУНКЦИИ
-------------------------------------------------
local function rectsIntersect(a,b)
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
    if rectsIntersect(test, p) then return false end
  end
  return true
end

local function drawBorder()
  gpu.setForeground(0xFFFFFF)
  for x=0, FIELD_WIDTH+1 do
    gpu.set(fieldX+x, fieldY, "#")
    gpu.set(fieldX+x, fieldY+FIELD_HEIGHT+1, "#")
  end
  for y=0, FIELD_HEIGHT+1 do
    gpu.set(fieldX, fieldY+y, "#")
    gpu.set(fieldX+FIELD_WIDTH+1, fieldY+y, "#")
  end
end

local function drawSquare(px, py, size, color)
  gpu.setForeground(color)
  for dx=0,size-1 do
    for dy=0,size-1 do
      gpu.set(fieldX+px+dx, fieldY+py+dy, "█")
    end
  end
end

local function drawNick(px, py, nick, color)
  gpu.setForeground(color)
  gpu.set(fieldX+px, fieldY+py-1, nick)
end

local function drawChat()
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, chatY, screenW, CHAT_HEIGHT, " ")
  local line = 0
  for i=1,#chat do
    local msg = chat[i]
    gpu.setForeground(msg.color)
    gpu.set(2, chatY+line, msg.nick .. ":")
    gpu.setForeground(0xFFFFFF)
    gpu.set(2 + unicode.len(msg.nick) + 2, chatY+line, msg.text)
    line = line + 1
  end
  if chatMode then
    gpu.setForeground(0xFFFFFF)
    gpu.set(2, chatY+CHAT_HEIGHT-1, "> "..chatBuffer)
  end
end

local function redraw()
  term.clear()
  drawBorder()
  for _, p in pairs(others) do
    drawNick(p.x, p.y, p.nick, p.color)
    drawSquare(p.x, p.y, p.size, p.color)
  end
  drawNick(player.x, player.y, player.nick, player.color)
  drawSquare(player.x, player.y, player.size, player.color)
  drawChat()
end

local function broadcastState()
  modem.broadcast(PORT,"state", player.id, player.nick, player.x, player.y, player.size, player.color)
end

local function addChatMessage(nick, color, text)
  if #chat >= MAX_CHAT_MESSAGES then
    table.remove(chat,1)
  end
  table.insert(chat,{nick=nick,color=color,text=text})
end

local function broadcastChat(text)
  modem.broadcast(PORT,"chat", player.nick, player.color, text)
end

-------------------------------------------------
-- ИГРОВОЙ ЦИКЛ
-------------------------------------------------
redraw()
broadcastState()

while true do
  local e = {event.pull(0.05)}
  if e[1] == "key_down" then
    local key = e[4]
    local char = e[3]

    if chatMode then
      if key == 28 then
        if unicode.len(chatBuffer) > 0 then
          addChatMessage(player.nick, player.color, chatBuffer)
          broadcastChat(chatBuffer)
        end
        chatBuffer=""
        chatMode=false
        redraw()
      elseif key == 14 then
        chatBuffer = unicode.sub(chatBuffer,1,-2)
        redraw()
      elseif char and char>0 then
        chatBuffer = chatBuffer..unicode.char(char)
        redraw()
      end
    else
      if key == 16 then -- Q
        break
      elseif key == 20 then -- T
        chatMode=true
        redraw()
      else
        local now = computer.uptime()
        if now-lastMove >= MOVE_DELAY then
          local nx, ny = player.x, player.y
          if key==17 then ny=ny-1 end
          if key==31 then ny=ny+1 end
          if key==30 then nx=nx-1 end
          if key==32 then nx=nx+1 end
          if nx>=1 and ny>=1 and nx+player.size-1<=FIELD_WIDTH and ny+player.size-1<=FIELD_HEIGHT and canMoveTo(nx,ny) then
            player.x=nx
            player.y=ny
            lastMove=now
            broadcastState()
            redraw()
          end
        end
      end
    end

  elseif e[1]=="modem_message" then
    local _,_,_,_, mtype, a,b,c,d,e2,f = table.unpack(e)
    if mtype=="state" then
      local id,nick,x,y,size,color=a,b,c,d,e2,f
      if id~=player.id then
        others[id]={id=id,nick=nick,x=x,y=y,size=size,color=color}
        redraw()
      end
    elseif mtype=="chat" then
      local nick,color,text=a,b,c
      addChatMessage(nick,color,text)
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
