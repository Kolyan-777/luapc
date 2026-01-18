local component = require("component")
local event = require("event")
local term = require("term")
local computer = require("computer")
local gpu = component.gpu
local unicode = require("unicode")

local PORT = 4242
local modem = component.modem
modem.open(PORT)

-- Настройки
local NICK = "Player1"
local PLAYER_COLOR = 0x0000FF
local FIELD_WIDTH = 60
local FIELD_HEIGHT = 22
local CHAT_HEIGHT = 6
local MAX_CHAT_MESSAGES = 7

-- Безопасное разрешение (80x25 подходит для большинства экранов Т1-Т3)
-- Если хочешь, можешь раскомментировать строку ниже для полного экрана, но может не работать на слабых железках
-- gpu.setResolution(gpu.maxResolution())
local w, h = gpu.getResolution()
if w < 80 then gpu.setResolution(80, 25) end

-- Состояние
local playerID = nil
local players = {}
local chat = {}
local chatMode = false
local chatBuffer = ""
local MOVE_DELAY = 0.1
local lastMove = 0

-- Отправка join
modem.broadcast(PORT, "join", NICK, PLAYER_COLOR)

-- Функции отрисовки
local function drawBorder()
    gpu.setForeground(0xFFFFFF)
    -- Верхняя и нижняя границы
    gpu.fill(1, 1, FIELD_WIDTH + 2, 1, "#")
    gpu.fill(1, FIELD_HEIGHT + 2, FIELD_WIDTH + 2, 1, "#")
    -- Боковые границы
    for y = 2, FIELD_HEIGHT + 1 do
        gpu.set(1, y, "#")
        gpu.set(FIELD_WIDTH + 2, y, "#")
    end
end

local function drawSquare(px, py, size, color)
    gpu.setBackground(color) -- Заливаем квадрат цветом
    for dx = 0, size - 1 do
        for dy = 0, size - 1 do
            gpu.set(px + dx + 1, py + dy + 1, " ")
        end
    end
    gpu.setBackground(0x000000) -- Сброс фона
end

local function drawNick(px, py, nick, color)
    gpu.setForeground(color)
    -- Смещаем ник чуть выше игрока, центрируем примерно
    local nickLen = unicode.len(nick)
    local startX = math.max(1, math.min(FIELD_WIDTH + 2 - nickLen, px + 1))
    gpu.set(startX, py, nick)
end

local function drawChat()
    local chatStartY = FIELD_HEIGHT + 3
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    -- Очищаем область чата
    gpu.fill(1, chatStartY, FIELD_WIDTH + 2, CHAT_HEIGHT, " ")
    
    local line = 0
    for i = 1, #chat do
        local msg = chat[i]
        if line < CHAT_HEIGHT - 1 then -- Оставляем место для ввода
            gpu.setForeground(msg.color)
            gpu.set(2, chatStartY + line, msg.nick .. ":")
            gpu.setForeground(0xFFFFFF)
            gpu.set(2 + unicode.len(msg.nick) + 2, chatStartY + line, msg.text)
            line = line + 1
        end
    end
    
    if chatMode then
        gpu.setForeground(0x00FF00)
        gpu.set(2, chatStartY + CHAT_HEIGHT - 1, "> " .. chatBuffer .. "_")
    end
end

local function redraw()
    -- Вместо полной очистки экрана, перерисовываем только игровое поле
    gpu.setBackground(0x000000)
    gpu.fill(1, 1, FIELD_WIDTH + 2, FIELD_HEIGHT + 2, " ") -- Очистка поля
    
    drawBorder()
    for _, p in pairs(players) do
        drawSquare(p.x, p.y, p.size, p.color)
        drawNick(p.x, p.y - 1, p.nick, p.color)
    end
    drawChat()
end

local function sendMove(nx, ny)
    modem.broadcast(PORT, "move", playerID, nx, ny)
end

local function sendChat(text)
    modem.broadcast(PORT, "chat", NICK, PLAYER_COLOR, text)
end

-- Главный цикл
redraw()
while true do
    local e = {event.pull(0.05)}

    if e[1] == "modem_message" then
        local _, _, _, _, _, mtype, a, b, c, d, e2, f = table.unpack(e)
        
        if mtype == "join_ack" then
            playerID = a
            print("Присоединился. ID: " .. playerID)
        elseif mtype == "state" then
            local id, nick, x, y, size, color = a, b, c, d, e2, f
            players[id] = {id = id, nick = nick, x = x, y = y, size = size, color = color}
            redraw()
        elseif mtype == "chat" then
            local nick, color, text = a, b, c
            table.insert(chat, {nick = nick, color = color, text = text})
            if #chat > MAX_CHAT_MESSAGES then table.remove(chat, 1) end
            redraw()
        end

    elseif e[1] == "key_down" then
        local key = e[4]
        local char = e[3] -- Код символа (для ввода текста)
        -- В версии OpenLibraries/OpenOS e[3] это пользовательский символ, e[4] - код клавиши (OC keyboard codes)

        if chatMode then
            if key == 28 then -- Enter
                if unicode.len(chatBuffer) > 0 then
                    sendChat(chatBuffer)
                end
                chatBuffer = ""
                chatMode = false
                redraw()
            elseif key == 14 then -- Backspace
                chatBuffer = unicode.sub(chatBuffer, 1, -2)
                redraw()
            elseif char and char > 0 and not (key == 28 or key == 14 or key == 15 or key == 203 or key == 208 or key == 200 or key == 205) then
                 -- Проверка, чтобы не печатать служебные символы (стрелки и т.д.), если они вдруг придут как char
                 chatBuffer = chatBuffer .. unicode.char(char)
                 redraw()
            end
        else
            if key == 16 then break end -- Q - Выход (только если не в чате)
            if key == 20 then -- T - Чат
                chatMode = true
                redraw()
            end
            
            if playerID and players[playerID] then
                local p = players[playerID]
                local nx, ny = p.x, p.y
                local moved = false
                local now = computer.uptime()

                if now - lastMove >= MOVE_DELAY then
                    if key == 200 then ny = ny - 1; moved = true end -- W / Стрелка Вверх
                    if key == 208 then ny = ny + 1; moved = true end -- S / Стрелка Вниз
                    if key == 203 then nx = nx - 1; moved = true end -- A / Стрелка Влево
                    if key == 205 then nx = nx + 1; moved = true end -- D / Стрелка Вправо
                    
                    -- Проверка границ (клиентская, для отклика)
                    if nx >= 1 and ny >= 1 and nx + p.size - 1 <= FIELD_WIDTH and ny + p.size - 1 <= FIELD_HEIGHT then
                        p.x = nx
                        p.y = ny
                        lastMove = now
                        sendMove(nx, ny)
                        redraw()
                    end
                end
            end
        end
    end
end

-- Выход
term.clear()
gpu.setForeground(0xFFFFFF)
gpu.setBackground(0x000000)
