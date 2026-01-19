-- КОНФИГУРАЦИЯ
local SERVER_PORT = 1234
local SERVER_ADDRESS = nil -- Оставьте nil для поиска ближайшего сервера, или укажите адрес (строкой), если знаете его

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
local component = require("component")
local computer = require("computer")
local event = require("event")
local term = require("term")
local keyboard = require("keyboard")
local gpu = component.gpu
local modem = component.modem

-- Проверка GPU
if not gpu then
  print("Ошибка: Видеокарта не найдена.")
  return
end

-- Проверка Модема
if not modem then
  print("Ошибка: Модем не найден.")
  return
end

-- Настройка разрешения экрана (Попытка установить более высокое разрешение)
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
  -- Красим ник
  local colorPrefix = nick == "Server" and "&e" or "&f" 
  table.insert(chatHistory, colorPrefix .. nick .. "&r: " .. msg)
  -- Ограничиваем историю, чтобы не забила память (например, последние 50 сообщений)
  if #chatHistory > 50 then
    table.remove(chatHistory, 1)
  end
end

-- Функция отрисовки интерфейса
local function draw()
  -- 1. Очистка экрана (Заливка черным)
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, w, h, " ")

  -- 2. Отрисовка области игры (верхняя часть экрана)
  local gameHeight = h - 3 -- Оставляем 3 строки снизу под чат и ввод
  local centerX = math.floor(w / 2)
  local centerY = math.floor(gameHeight / 2)

  -- Рисуем рамку игровой зоны
  gpu.setForeground(0xAAAAAA)
  gpu.fill(1, 1, w, 1, "-") -- Верхняя граница
  gpu.fill(1, gameHeight, w, 1, "-") -- Нижняя граница игрового поля

  -- Функция преобразования мировых координат в экранные
  -- Игрок всегда в центре экрана
  local function toScreen(wx, wy)
    return centerX + (wx - me.x), centerY + (wy - me.y)
  end

  -- Рисуем других игроков
  for addr, p in pairs(otherPlayers) do
    local sx, sy = toScreen(p.x, p.y)
    -- Рисуем только если попал в экран
    if sx > 0 and sx <= w and sy > 0 and sy < gameHeight then
      gpu.setForeground(p.color)
      -- Рисуем "квадратик" игрока
      gpu.set(sx, sy, "█")
      -- Рисуем ник над игроком
      gpu.set(sx - math.floor(#p.name/2), sy - 1, p.name)
    end
  end

  -- Рисуем себя (всегда в центре)
  gpu.setForeground(me.color)
  gpu.set(centerX, centerY, "@") -- Себя пометим значком @
  gpu.setForeground(0x00FF00) -- Зеленый индикатор "Я"
  gpu.set(centerX, centerY + 1, "v") 

  -- 3. Отрисовка Чата (нижняя часть экрана)
  local chatStartY = h - 2
  -- Показываем последние 2 сообщения в логе поверх поля ввода, если история длинная
  local visibleLog = {}
  for i = math.max(1, #chatHistory - 2), #chatHistory do
    table.insert(visibleLog, chatHistory[i])
  end
  
  for i, line in ipairs(visibleLog) do
    -- Простая реализация цветов: заменяем коды цветов на стандартные цвета GPU
    -- &f = белый, &e = желтый, &r = сброс
    local textToDraw = line:gsub("&e", ""):gsub("&f", ""):gsub("&r", "")
    if line:find("&e") then gpu.setForeground(0xFFFF00) else gpu.setForeground(0xFFFFFF) end
    
    gpu.set(1, chatStartY - (#visibleLog - i), textToDraw)
  end

  -- 4. Отрисовка строки ввода
  gpu.setForeground(0xAAAAAA)
  gpu.set(1, h, "Chat: " .. inputText .. "_") -- Курсор
end

-- Основной цикл
log("Клиент запущен. Подключение к серверу...")

-- Отправляем запрос на подключение
send("connect", me.name, me.color)

-- Таймер для отправки движения (anti-spam движение)
local lastMoveTime = 0
local MOVE_DELAY = 0.1 -- Секунды

while running do
  draw() -- Обновляем графику каждый цикл
  
  -- Получаем событие с таймаутом 0.05 сек, чтобы интерфейс не зависал наглухо
  local eventData = { event.pull(0.05) }
  local eventName = eventData[1]

  if eventName then
    -------------------------------------------------
    -- СОБЫТИЕ: Нажатие клавиши (Клавиатура)
    -------------------------------------------------
    if eventName == "key_down" then
      local char, code = eventData[3], eventData[4]
      
      -- Обработка текстового ввода (только ASCII символы для простоты)
      if char and char > 31 and char < 127 and code ~= 13 then -- 13 is Enter
        inputText = inputText .. string.char(char)
      
      -- Обработка специальных клавиш (Enter, Backspace, WASD)
      elseif code == 28 or code == 156 then -- Enter
        if inputText ~= "" then
          send("chat", inputText)
          addChatMessage(me.name, inputText)
          inputText = ""
        end
      elseif code == 14 then -- Backspace
        inputText = inputText:sub(1, -2)
      
      -- WASD Движение
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
      
      -- Выход по Ctrl+C
      if char == 3 and keyboard.isControlDown() then 
        running = false 
      end

    -------------------------------------------------
    -- СОБЫТИЕ: Сообщение по сети (Модем)
    -------------------------------------------------
    elseif eventName == "modem_message" then
      local _, _, _, _, _, msgType, p1, p2, p3, p4 = table.unpack(eventData)
      
      if msgType == "spawn_player" then
        -- p1=addr, p2=name, p3=color, p4=x, p5=y
        otherPlayers[p1] = { name = p2, color = p3, x = p4, y = p5 }
        addChatMessage("Server", p2 .. " вошел в игру.")
      
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
end

-- Завершение работы
term.clear()
gpu.setBackground(0x000000)
gpu.setForeground(0xFFFFFF)
print("Клиент отключен.")
