-- server.lua
local component = require("component")
local event = require("event")
local computer = require("computer")
local modem = component.modem
local math = require("math")

local PORT = 4242
modem.open(PORT)
math.randomseed(computer.uptime()*1000)

local players = {}  -- id -> {nick, x, y, size, color}
local chat = {}     -- {nick, color, text}

-- настройки поля
local FIELD_WIDTH = 60
local FIELD_HEIGHT = 22

print("Сервер запущен на порту "..PORT)

while true do
  local e = {event.pull(0.05)}
  if e[1] == "modem_message" then
    local _, _, _, _, mtype, a,b,c,d,e2,f = table.unpack(e)
    
    if mtype == "join" then
      local nick, color = a,b
      local id = tostring(math.random(1,99999999))
      -- стартовая позиция случайная
      local x = math.random(1, FIELD_WIDTH-1)
      local y = math.random(1, FIELD_HEIGHT-1)
      players[id] = {nick=nick,x=x,y=y,size=2,color=color}
      -- отправляем игроку его id
      modem.send(e[3], PORT, "join_ack", id)
      print(nick.." присоединился как "..id)
    
    elseif mtype == "move" then
      local id, nx, ny = a,b,c
      if players[id] then
        -- коллизия между игроками
        local canMove = true
        local psize = players[id].size
        for oid, p in pairs(players) do
          if oid ~= id then
            if not (nx+psize-1 < p.x or nx > p.x+p.size-1 or ny+psize-1 < p.y or ny > p.y+p.size-1) then
              canMove=false
              break
            end
          end
        end
        -- границы
        if nx<1 or ny<1 or nx+p.size-1>FIELD_WIDTH or ny+p.size-1>FIELD_HEIGHT then canMove=false end
        if canMove then
          players[id].x = nx
          players[id].y = ny
        end
      end

    elseif mtype == "chat" then
      local nick, color, text = a,b,c
      table.insert(chat, {nick=nick,color=color,text=text})
      if #chat>7 then table.remove(chat,1) end
    end

    -- Рассылаем состояние всем игрокам
    for addr,_ in pairs(component.modem.getAddresses()) do
      for id,p in pairs(players) do
        modem.send(addr, PORT, "state", id, p.nick, p.x, p.y, p.size, p.color)
      end
      -- чат
      for _,msg in ipairs(chat) do
        modem.send(addr, PORT, "chat", msg.nick, msg.color, msg.text)
      end
    end
  end
end
