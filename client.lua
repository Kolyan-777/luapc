-- client.lua
local component = require("component")
local event = require("event")
local term = require("term")
local computer = require("computer")
local gpu = component.gpu
local unicode = require("unicode")

local PORT = 4242
modem = component.modem
modem.open(PORT)

-- настройки игрока и поля
local NICK = "Player1"
local PLAYER_COLOR = 0x0000FF
local FIELD_WIDTH = 60
local FIELD_HEIGHT = 22
local CHAT_HEIGHT = 6
local MAX_CHAT_MESSAGES = 7

-- состояние
local playerID = nil
local players = {}
local chat = {}
local chatMode = false
local chatBuffer = ""
local MOVE_DELAY = 0.1
local lastMove = 0

gpu.setResolution(gpu.maxResolution())

-- отправка join
modem.broadcast(PORT,"join",NICK,PLAYER_COLOR)

-- функции отрисовки
local function drawBorder()
  gpu.setForeground(0xFFFFFF)
  for x=0,FIELD_WIDTH+1 do
    gpu.set(x+1,1,"#")
    gpu.set(x+1,FIELD_HEIGHT+2,"#")
  end
  for y=0,FIELD_HEIGHT+1 do
    gpu.set(1,y+1,"#")
    gpu.set(FIELD_WIDTH+2,y+1,"#")
  end
end

local function drawSquare(px,py,size,color)
  gpu.setForeground(color)
  for dx=0,size-1 do
    for dy=0,size-1 do
      gpu.set(px+dx+1,py+dy+1,"█")
    end
  end
end

local function drawNick(px,py,nick,color)
  gpu.setForeground(color)
  gpu.set(px+1,py,nick)
end

local function drawChat()
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, FIELD_HEIGHT+3, FIELD_WIDTH+2, CHAT_HEIGHT, " ")
  local line=0
  for i=1,#chat do
    local msg=chat[i]
    gpu.setForeground(msg.color)
    gpu.set(2, FIELD_HEIGHT+3+line, msg.nick..":")
    gpu.setForeground(0xFFFFFF)
    gpu.set(2+unicode.len(msg.nick)+2, FIELD_HEIGHT+3+line, msg.text)
    line=line+1
  end
  if chatMode then
    gpu.setForeground(0xFFFFFF)
    gpu.set(2, FIELD_HEIGHT+3+CHAT_HEIGHT-1, "> "..chatBuffer)
  end
end

local function redraw()
  term.clear()
  drawBorder()
  for _,p in pairs(players) do
    drawNick(p.x,p.y-1,p.nick,p.color)
    drawSquare(p.x,p.y,p.size,p.color)
  end
  drawChat()
end

local function sendMove(nx,ny)
  modem.broadcast(PORT,"move",playerID,nx,ny)
end

local function sendChat(text)
  modem.broadcast(PORT,"chat",NICK,PLAYER_COLOR,text)
end

-- главный цикл
redraw()
while true do
  local e={event.pull(0.05)}

  if e[1]=="modem_message" then
    local _,_,_,_,mtype,a,b,c,d,e2,f=table.unpack(e)
    if mtype=="join_ack" then
      playerID=a
    elseif mtype=="state" then
      local id,nick,x,y,size,color=a,b,c,d,e2,f
      players[id]={id=id,nick=nick,x=x,y=y,size=size,color=color}
      redraw()
    elseif mtype=="chat" then
      local nick,color,text=a,b,c
      table.insert(chat,{nick=nick,color=color,text=text})
      if #chat>MAX_CHAT_MESSAGES then table.remove(chat,1) end
      redraw()
    end

  elseif e[1]=="key_down" then
    local key = e[4]
    local char = e[3]

    if chatMode then
      if key==28 then
        if unicode.len(chatBuffer)>0 then
          sendChat(chatBuffer)
        end
        chatBuffer=""
        chatMode=false
        redraw()
      elseif key==14 then
        chatBuffer=unicode.sub(chatBuffer,1,-2)
        redraw()
      elseif char and char>0 then
        chatBuffer = chatBuffer..unicode.char(char)
        redraw()
      end
    else
      if key==16 then break end
      if key==20 then
        chatMode=true
        redraw()
      else
        if playerID and players[playerID] then
          local p = players[playerID]
          local nx,ny = p.x,p.y
          local now = computer.uptime()
          if now-lastMove>=MOVE_DELAY then
            if key==17 then ny=ny-1 end
            if key==31 then ny=ny+1 end
            if key==30 then nx=nx-1 end
            if key==32 then nx=nx+1 end
            if nx>=1 and ny>=1 and nx+p.size-1<=FIELD_WIDTH and ny+p.size-1<=FIELD_HEIGHT then
              p.x=nx p.y=ny
              lastMove=now
              sendMove(nx,ny)
              redraw()
            end
          end
        end
      end
    end
  end
end

-- выход
term.clear()
gpu.setForeground(0xFFFFFF)
gpu.setBackground(0x000000)
