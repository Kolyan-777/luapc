-- === БИБЛИОТЕКИ ===
local component = require("component")
local computer = require("computer")
local event = require("event")
local term = require("term")
local keyboard = require("keyboard")
local serialization = require("serialization")

local gpu = component.gpu
local modem = component.modem

-- Проверка компонентов
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
local isTyping = false -- Режим чата (включается по T)
local running = true

-- === ФУНКЦИИ ===

-- Настройка экрана
local function initScreen()
  w, h = gpu.getResolution()
  if w < 80 then
    gpu.setResolution(80, 25)
    w, h = 80, 25
  end
end

-- Отправка на сервер
local function send(...)
  if not modem.isOpen(SERVER_PORT) then modem.open(SERVER_PORT) end
  modem.broadcast(SERVER_PORT, ...)
end

-- Добавление в чат (только от сервера или системные)
local function addChatMessage(nick, msg)
  local prefix = nick == "Server" and "[SERVER] " or nick .. ": "
  table.insert(chatHistory, prefix .. msg)
  if #chatHistory > 10 then table.remove(chatHistory, 1) end
end

-- Сохранение и восстановление области экрана (для буферизации)
-- Это устраняет мерцание, рисуя все в памяти, а потом выводя разом
local buffer = {}
local function saveBuffer()
  buffer = {}
  -- Копируем содержимое экрана (по строкам)
  for y = 1, h do
    buffer[y] = gpu.get(1, y, w, y)
  end
end

local function restoreBuffer()
  if not buffer or not next(buffer) then return end
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  for y = 1, h do
    if buffer[y] then
      gpu.set(1, y, buffer[y])
    end
  end
end

local function draw()
  -- 1. Очистка всего экрана черным цветом
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, w, h, " ")

  local gameHeight = h - 3
  local centerX = math.floor(w / 2)
  local centerY = math.floor(gameHeight / 2)

  -- Рисуем границы игровой зоны
  gpu.setForeground(0x333333) -- Темно-серая рамка
  gpu.fill(1, 1, w, 1, "░") -- Верх
  gpu.fill(1, gameHeight, w, 1, "░") -- Низ

  -- Преобразование координат
  local function toScreen(wx, wy)
    return centerX + (wx - me.x), centerY + (wy - me.y)
  end

  -- 2. Рисуем других игроков
  for addr, p in pairs(otherPlayers) do
    -- Проверка: есть ли у игрока координаты?
    if p.x and p.y then
      local sx, sy = toScreen(p.x, p.y)
      
      -- Рисуем только если в пределах экрана (с небольшим отступом)
      if sx > 1 and sx < w and sy > 1 and sy < gameHeight then
        -- Тело игрока
        gpu.setForeground(p.color)
        gpu.set(sx, sy, "█")
        
        -- Ник над игроком (центрирование)
        local nick = p.name or "Unknown"
        local nickX = sx - math.floor(#nick / 2)
        gpu.setForeground(0xFFFFFF)
        gpu.set(nickX, sy - 1, nick)
      end
    end
  end

  -- 3. Рисуем себя
  gpu.setForeground(me.color)
  gpu.set(centerX, centerY, "@")
  
  -- Стрелка "я здесь" снизу
  gpu.setForeground(0x00FF00)
  gpu.set(centerX, centerY + 1, "v")

  -- 4. Зона чата (последние несколько строк)
  local chatY = gameHeight + 2
  gpu.setForeground(0xAAAAAA)
  gpu.set(1, chatY - 1, " --- CHAT ---")
  
  for i, msg in ipairs(chatHistory) do
    -- Обрезаем слишком длинные сообщения, чтобы не вылезали за экран
    local displayMsg = string.sub(msg, 1, w)
    gpu.set(1, chatY - 1 + i, displayMsg)
  end

  -- 5. Строка ввода
  local statusColor = isTyping and 0x00FF00 or 0xFF0000 -- Зеленый если пишем, красный если играем
  gpu.setForeground(statusColor)
  local statusText = isTyping and "[ЧAT]" or "[ИГРА]"
  gpu.set(1, h, statusText .. " > " .. inputText .. (isTyping and "_" or ""))
end

-- === ЗАПУСК ===
initScreen()
send("connect", me.name, me.color)

local lastMoveTime = 0
local MOVE_DELAY = 0.1

print("Клиент запущен.")
print("Управление:")
print("  WASD - Ходить")
print("  T   - Написать в чат")
print("  ENTER - Отправить")
print("  ESC  - Отменить ввод текста")

while running do
  draw()
  
  -- Получаем событие
  local e = { event.pull(0.05) }
  local eventName = e[1]

  if eventName == "key_down" then
    local char, code = e[3], e[4]
    
    -- ОБРАБОТКА ВЫХОДА
    if char == 3 and keyboard.isControlDown() then 
      running = false 
    end

    -- ЕСЛИ МЫ В РЕЖИМЕ ЧАТА
    if isTyping then
      if code == 28 or code == 156 then -- ENTER -> Отправить
        if inputText ~= "" then
          send("chat", inputText)
          inputText = ""
        end
        isTyping = false -- Выходим из режима чата после отправки
      
      elseif code == 1 then -- ESC -> Отменить
        inputText = ""
        isTyping = false
      
      elseif code == 14 then -- Backspace
        inputText = inputText:sub(1, -2)
      
      -- Ввод текста (только печатные символы)
      elseif char and char >= 32 and char <= 126 then
        inputText = inputText .. string.char(char)
      end

    -- ЕСЛИ МЫ В РЕЖИМЕ ИГРЫ
    else
      if char == string.byte("t") or char == string.byte("T") then
        isTyping = true -- Включаем режим чата
      
      -- Обработка движения (WASD)
      elseif computer.uptime() - lastMoveTime > MOVE_DELAY then
        local dx, dy = 0, 0
        if char == string.byte("w") then dy = -1
        elseif char == string.byte("s") then dy = 1
        elseif char == string.byte("a") then dx = -1
        elseif char == string.byte("d") then dx = 1
        end
        
        if dx ~= 0 or dy ~= 0 then
          me.x = me.x + dx
          me.y = me.y + dy
          send("move", dx, dy)
          lastMoveTime = computer.uptime()
        end
      end
    end

  elseif eventName == "modem_message" then
    local _, _, _, _, _, msgType, p1, p2, p3, p4, p5 = table.unpack(e)
    
    if msgType == "spawn_player" then
      -- p1=addr, p2=name, p3=color, p4=x, p5=y
      otherPlayers[p1] = { name = p2, color = p3, x = p4, y = p5 }
      if p1 ~= modem.address then -- Не пишем "вошел" про самого себя
        addChatMessage("Server", p2 .. " вошел в игру.")
      end
    
    elseif msgType == "update_pos" then
      -- p1=addr, p2=x, p3=y
      if otherPlayers[p1] then
        otherPlayers[p1].x = p2
        otherPlayers[p1].y = p3
      end
    
    elseif msgType == "chat" then
      -- p1=nick, p2=message
      addChatMessage(p1, p2)
    end
  end
end

-- Выход
term.clear()
gpu.setBackground(0x000000)
gpu.setForeground(0xFFFFFF)
print("Клиент отключен.")
