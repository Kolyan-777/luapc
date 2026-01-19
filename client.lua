-- === ИСПРАВЛЕНИЕ: Подключение библиотек и объявление функции log ===
local component = require("component")
local computer = require("computer")
local event = require("event")
local term = require("term")
local keyboard = require("keyboard")

-- Простейшая функция лога, выводящая в консоль
local function log(msg)
  print(msg)
end
-- =====================================================================

-- КОНФИГУРАЦИЯ
local SERVER_PORT = 1234
local SERVER_ADDRESS = nil -- Оставьте nil для поиска ближайшего сервера

-- Состояние клиента
local me = {
  name = "Player",
  color = 0xFFFFFF,
  x = 0,
  y = 0
}
local otherPlayers = {} -- Список других игроков [address] = {name, color, x, y}
local chatHistory = {} -- История сообщений чата
local inputText = ""   -- Текст, который сейчас вводит игрок
local running = true

-- Инициализация компонентов
local gpu = component.gpu
local modem = component.modem

-- Проверка GPU
if not gpu then
  log("Ошибка: Видеокарта не найдена.")
  return
end

-- Проверка Модема
if not modem then
  log("Ошибка: Модем не найден.")
  return
end

-- Настройка разрешения экрана
local w, h = gpu.getResolution()
if w < 80 then
  gpu.setResolution(80, 25)
  w, h = 80, 25
end

-- Функция отправки данных серверу
local function send(...)
  if not modem.isOpen(SERVER_PORT) then
    modem.open(SERVER_PORT)
  end
  modem.broadcast(SERVER_PORT, ...)
end

-- Функция добавления сообщения в чат
local function addChatMessage(nick, msg)
  local colorPrefix = nick == "Server" and "&e" or "&f" 
  table.insert(chatHistory, colorPrefix .. nick .. "&r: " .. msg)
  if #chatHistory > 50 then
    table.remove(chatHistory, 1)
  end
end

-- Функция отрисовки интерфейса
local function draw()
  -- 1. Очистка экрана
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, w, h, " ")

  -- 2. Отрисовка области игры
  local gameHeight = h - 3 
  local centerX = math.floor(w / 2)
  local centerY = math.floor(gameHeight / 2)

  -- Рисуем рамку игровой зоны
  gpu.setForeground(0xAAAAAA)
  gpu.fill(1, 1, w, 1, "-") 
  gpu.fill(1, gameHeight, w, 1, "-") 

  -- Преобразование координат
  local function toScreen(wx, wy)
    return centerX + (wx - me.x), centerY + (wy - me.y)
  end

  -- Рисуем других игроков
  for addr, p in pairs(otherPlayers) do
    local sx, sy = toScreen(p.x, p.y)
    if sx > 0 and sx <= w and sy > 0 and sy < gameHeight then
      gpu.setForeground(p.color)
      gpu.set(sx, sy, "█")
      gpu.set(sx - math.floor(#p.name/2), sy - 1, p.name)
    end
  end

  -- Рисуем себя
  gpu.setForeground(me.color)
  gpu.set(centerX, centerY, "@")
  gpu.setForeground(0x00FF00)
  gpu.set(centerX, centerY + 1, "v") 

  -- 3. Отрисовка Чата
  local chatStartY = h - 2
  local visibleLog = {}
  for i = math.max(1, #chatHistory - 2), #chatHistory do
    table.insert(visibleLog, chatHistory[i])
  end
  
  for i, line in ipairs(visibleLog) do
    -- Убираем цветовые коды для простого вывода или обрабатываем их
    -- Для простоты здесь просто текст
    local textToDraw = line:gsub("&e", ""):gsub("&f", ""):gsub("&r", "")
    -- Если сообщение от сервера, покрасим в желтый
    if line:find("&e") then gpu.setForeground(0xFFFF00) else gpu.setForeground(0xFFFFFF) end
    
    gpu.set(1, chatStartY - (#visibleLog - i), textToDraw)
  end

  -- 4. Строка ввода
  gpu.setForeground(0xAAAAAA)
  gpu.set(1, h, "Chat: " .. inputText .. "_")
end

-- Основной цикл
log("Клиент запущен. Подключение к серверу...")

-- Отправляем запрос на подключение
send("connect", me.name, me.color)

-- Таймеры
local lastMoveTime = 0
local MOVE_DELAY = 0.1

while running do
  draw()
  
  -- event.pull с таймаутом, чтобы не зависало
  local eventData = { event.pull(0.05) }
  local eventName = eventData[1]

  if eventName then
    if eventName == "key_down" then
      local char, code = eventData[3], eventData[4]
      
      -- Ввод текста (проверка, что это не специальная клавиша)
      if char and char > 31 and char < 127 and code ~= 13 then 
        inputText = inputText .. string.char(char)
      
      elseif code == 28 or code == 156 then -- Enter
        if inputText ~= "" then
          send("chat", inputText)
          addChatMessage(me.name, inputText)
          inputText = ""
        end
      elseif code == 14 then -- Backspace
        inputText = inputText:sub(1, -2)
      
      -- WASD (проверка задержки)
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
      
      -- Выход
      if char == 3 and keyboard.isControlDown() then 
        running = false 
      end

    elseif eventName == "modem_message" then
      local _, _, _, _, _, msgType, p1, p2, p3, p4 = table.unpack(eventData)
      
      if msgType == "spawn_player" then
        otherPlayers[p1] = { name = p2, color = p3, x = p4, y = p5 }
        addChatMessage("Server", p2 .. " вошел в игру.")
      
      elseif msgType == "update_pos" then
        if otherPlayers[p1] then
          otherPlayers[p1].x = p2
          otherPlayers[p1].y = p3
        end
      
      elseif msgType == "chat" then
        addChatMessage(p1, p2)
      end
    end
  end
end

-- Завершение
term.clear()
gpu.setBackground(0x000000)
gpu.setForeground(0xFFFFFF)
print("Клиент отключен.")
