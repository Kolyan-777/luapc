-- === БИБЛИОТЕКИ ===
local component = require("component")
local computer = require("computer")
local event = require("event")
local term = require("term")
local keyboard = require("keyboard")

local gpu = component.gpu
local modem = component.modem

-- === ПРОВЕРКИ ===
if not gpu then error("Видеокарта не найдена") end
if not modem then error("Модем не найден") end

-- === КОНФИГУРАЦИЯ ===
local SERVER_PORT = 1234
local SERVER_ADDRESS = nil 
local w, h

-- === СОСТОЯНИЕ ===
local me = {
  name = "Player",
  color = 0xFFFFFF,
  x = 0,
  y = 0
}
local otherPlayers = {} 
local chatHistory = {}
local inputText = ""
local isTyping = false 
local running = true

-- === ФУНКЦИИ ===

local function initScreen()
  w, h = gpu.getResolution()
  if w < 80 then
    gpu.setResolution(80, 25)
    w, h = 80, 25
  end
end

local function send(...)
  if not modem.isOpen(SERVER_PORT) then modem.open(SERVER_PORT) end
  modem.broadcast(SERVER_PORT, ...)
end

-- Безопасное добавление сообщения
local function addChatMessage(nick, msg)
  -- Защита от nil значений
  local safeNick = nick or "Unknown"
  local safeMsg = msg or ""
  
  local prefix = safeNick == "Server" and "[SERVER] " or safeNick .. ": "
  table.insert(chatHistory, prefix .. safeMsg)
  
  -- Храним только последние 12 сообщений
  if #chatHistory > 12 then
    table.remove(chatHistory, 1)
  end
end

local function draw()
  -- Очистка
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, w, h, " ")

  local gameHeight = h - 3
  local centerX = math.floor(w / 2)
  local centerY = math.floor(gameHeight / 2)

  -- Границы
  gpu.setForeground(0x333333)
  gpu.fill(1, 1, w, 1, "░")
  gpu.fill(1, gameHeight, w, 1, "░")

  local function toScreen(wx, wy)
    return centerX + (wx - me.x), centerY + (wy - me.y)
  end

  -- Рисуем других игроков
  for addr, p in pairs(otherPlayers) do
    if p.x and p.y then
      local sx, sy = toScreen(p.x, p.y)
      if sx > 1 and sx < w and sy > 1 and sy < gameHeight then
        gpu.setForeground(p.color)
        gpu.set(sx, sy, "█")
        
        local nick = p.name or "Unknown"
        local nickX = sx - math.floor(#nick / 2)
        gpu.setForeground(0xFFFFFF)
        gpu.set(nickX, sy - 1, nick)
      end
    end
  end

  -- Рисуем себя
  gpu.setForeground(me.color)
  gpu.set(centerX, centerY, "@")
  gpu.setForeground(0x00FF00)
  gpu.set(centerX, centerY + 1, "v")

  -- Чат
  local chatY = gameHeight + 2
  gpu.setForeground(0xAAAAAA)
  gpu.set(1, chatY - 1, " --- CHAT ---")
  
  for i, msg in ipairs(chatHistory) do
    gpu.set(1, chatY - 1 + i, string.sub(msg, 1, w))
  end

  -- Строка ввода
  local statusColor = isTyping and 0x00FF00 or 0xFF0000
  gpu.setForeground(statusColor)
  local statusText = isTyping and "[ЧAT]" or "[ИГРА]"
  gpu.set(1, h, statusText .. " > " .. inputText .. (isTyping and "_" or ""))
end

-- === ЗАПУСК ===
initScreen()
send("connect", me.name, me.color)

local lastMoveTime = 0
local MOVE_DELAY = 0.1

while running do
  draw()
  
  -- Получаем событие с небольшим таймаутом, чтобы цикл крутился и рисовал
  local e = { event.pull(0.05) }
  local eventName = e[1]

  if eventName == "key_down" then
    -- Распаковка: e[1]=name, e[2]=addr, e[3]=char, e[4]=code
    local char = e[3]
    local code = e[4]
    
    -- Выход (Ctrl + C)
    if char == 3 and keyboard.isControlDown() then 
      running = false 
    end

    -- РЕЖИМ ЧАТА
    if isTyping then
      if code == 28 or code == 156 then -- Enter
        if inputText ~= "" then
          send("chat", inputText)
          inputText = ""
        end
        isTyping = false -- Выход из чата
      elseif code == 1 then -- Esc
        inputText = ""
        isTyping = false
      elseif code == 14 then -- Backspace
        inputText = inputText:sub(1, -2)
      elseif char and char >= 32 and char <= 126 then
        inputText = inputText .. string.char(char)
      end

    -- РЕЖИМ ИГРЫ
    else
      -- Нажатие T включает чат
      if char == string.byte("t") or char == string.byte("T") then
        isTyping = true
      
      -- Обработка WASD
      else
        -- Проверка таймера движения
        if computer.uptime() - lastMoveTime > MOVE_DELAY then
          local moved = false
          
          -- W (код 17) или S (код 31) или A (код 30) или D (код 32)
          -- Проверяем char (символ) или code (скан-код)
          if char == string.byte("w") then me.y = me.y - 1; moved = true
          elseif char == string.byte("s") then me.y = me.y + 1; moved = true
          elseif char == string.byte("a") then me.x = me.x - 1; moved = true
          elseif char == string.byte("d") then me.x = me.x + 1; moved = true
          end
          
          if moved then
            send("move", (char == string.byte("d") and 1 or (char == string.byte("a") and -1 or 0)), 
                             (char == string.byte("s") and 1 or (char == string.byte("w") and -1 or 0)))
            lastMoveTime = computer.uptime()
          end
        end
      end
    end

  elseif eventName == "modem_message" then
    -- e[1]=msg_name, e[2]=localAddr, e[3]=remoteAddr, e[4]=port, e[5]=distance
    -- e[6]=data1, e[7]=data2, e[8]=data3, e[9]=data4, e[10]=data5
    
    local msgType = e[6]
    
    if msgType == "spawn_player" then
      local addr = e[7]
      local name = e[8]
      local color = e[9]
      local x = e[10]
      local y = e[11]
      
      if addr and x and y then
        otherPlayers[addr] = { name = name, color = color, x = x, y = y }
        if addr ~= modem.address then
          addChatMessage("Server", (name or "Unknown") .. " вошел в игру.")
        end
      end
      
    elseif msgType == "update_pos" then
      local addr = e[7]
      local x = e[8]
      local y = e[9]
      
      if otherPlayers[addr] then
        otherPlayers[addr].x = x
        otherPlayers[addr].y = y
      end
      
    elseif msgType == "chat" then
      local nick = e[7]
      local msg = e[8]
      addChatMessage(nick, msg)
    end
  end
end

-- Выход
term.clear()
gpu.setBackground(0x000000)
gpu.setForeground(0xFFFFFF)
print("Клиент отключен.")
