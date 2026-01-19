-- Конфигурация
local PORT = 1234               -- Порт, на котором будет работать сервер
local LOG_FILE = "server.log"   -- Имя файла для логов

-- Переменные состояния
local players = {}              -- Таблица активных игроков [address] = {name, color, x, y}
local running = true            -- Флаг работы сервера

-- Функция логирования
local function log(msg)
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local logLine = string.format("[%s] %s", timestamp, msg)
  print(logLine) -- Вывод в консоль сервера
  
  -- Запись в файл
  local f, err = io.open(LOG_FILE, "a")
  if f then
    f:write(logLine .. "\n")
    f:close()
  else
    print("Ошибка записи лога: " .. tostring(err))
  end
end

-- Функция отправки данных конкретному игроку
local function sendTo(address, ...)
  local modem = component.proxy(component.list("modem")())
  if modem then
    modem.send(address, PORT, ...)
  end
end

-- Функция рассылки данных ВСЕМ игрокам, кроме (опционально) excludeAddress
local function broadcast(excludeAddress, ...)
  local modem = component.proxy(component.list("modem")())
  if modem then
    for addr, _ in pairs(players) do
      if addr ~= excludeAddress then
        modem.send(addr, PORT, ...)
      end
    end
  end
end

-- Основной цикл сервера
local function main()
  -- Проверка наличия модема
  local modem = component.list("modem")()
  if not modem then
    log("КРИТИЧЕСКАЯ ОШИБКА: Модем не найден!")
    return
  end
  modem = component.proxy(modem)
  
  -- Открытие порта
  if not modem.open(PORT) then
    log("КРИТИЧЕСКАЯ ОШИБКА: Не удалось открыть порт " .. PORT)
    return
  end
  
  log("Сервер запущен на порту " .. PORT)
  log("Ожидание игроков...")

  while running do
    -- Получаем события: "modem_message"
    local eventData = {computer.pullSignal()}
    local eventName = eventData[1]
    
    if eventName == "modem_message" then
      -- Распаковка данных события
      -- eventData[2] = localAddress, eventData[3] = remoteAddress, 
      -- eventData[4] = port, eventData[5] = distance, 
      -- eventData[6]... = данные (message)
      local remoteAddress = eventData[3]
      local port = eventData[4]
      local msgType = eventData[6]
      
      -- Проверка порта (чтобы фильтровать лишний мусор, если нужно)
      if port == PORT then
        -------------------------------------------------
        -- ОБРАБОТКА: Подключение нового игрока
        -------------------------------------------------
        if msgType == "connect" then
          local nick = eventData[7] or "Unknown"
          local color = eventData[8] or 0xFFFFFF -- Белый по умолчанию
          local x = 0
          local y = 0
          
          -- Если игрок уже подключен, обновляем данные (или можно игнорировать)
          if not players[remoteAddress] then
            log(string.format("Игрок %s (%s) подключился.", nick, remoteAddress))
            
            players[remoteAddress] = {
              name = nick,
              color = color,
              x = x,
              y = y
            }
            
            -- 1. Отправляем новому игроку список всех СУЩЕСТВУЮЩИХ игроков
            for addr, p in pairs(players) do
              if addr ~= remoteAddress then
                sendTo(remoteAddress, "spawn_player", addr, p.name, p.color, p.x, p.y)
              end
            end
            
            -- 2. Рассылаем всем ОСТАЛЬНЫМ, что подключился новый игрок
            broadcast(remoteAddress, "spawn_player", remoteAddress, nick, color, x, y)
            
            -- 3. Отправляем приветствие новому игроку
            sendTo(remoteAddress, "chat", "Server", "Добро пожаловать, " .. nick .. "!")
          end
          
        -------------------------------------------------
        -- ОБРАБОТКА: Движение (WASD)
        -------------------------------------------------
        elseif msgType == "move" then
          local dx = eventData[7]
          local dy = eventData[8]
          local player = players[remoteAddress]
          
          if player then
            -- Обновляем координаты
            player.x = player.x + dx
            player.y = player.y + dy
            
            -- Рассылаем ВСЕМ (включая отправителя для синхронизации) новую позицию
            -- Отправляем: type, address, x, y
            broadcast(nil, "update_pos", remoteAddress, player.x, player.y)
          end
          
        -------------------------------------------------
        -- ОБРАБОТКА: Чат
        -------------------------------------------------
        elseif msgType == "chat" then
          local message = eventData[7] or ""
          local player = players[remoteAddress]
          
          if player and message ~= "" then
            log(string.format("Чат <%s>: %s", player.name, message))
            -- Рассылаем всем: type, nick, message
            broadcast(nil, "chat", player.name, message)
          end
        end
      end
    elseif eventName == "key_down" then
      -- Если нажата комбинация Ctrl+C (код 46), останавливаем сервер
      if eventData[4] == 29 and eventData[3] == 46 then
        log("Остановка сервера пользователем...")
        running = false
      end
    end
  end
end

-- Запуск
local ok, err = pcall(main)
if not ok then
  log("КРИТИЧЕСКИЙ СБОЙ: " .. tostring(err))
end
log("Сервер остановлен.")
