local component = require("component")
local event = require("event")
local computer = require("computer")
local modem = component.modem
local math = require("math")

local PORT = 4242
modem.open(PORT)
math.randomseed(computer.uptime() * 1000 + computer.address():byte(1))

local players = {}  -- id -> {nick,x,y,size,color}
local chat = {}     -- {nick,color,text}
local FIELD_WIDTH = 60
local FIELD_HEIGHT = 22
local MAX_CHAT_MESSAGES = 7

print("Сервер запущен на порту "..PORT)

while true do
    local e = {event.pull(0.05)}
    if e[1] == "modem_message" then
        -- Распаковка: eventName, receiverAddress, senderAddress, port, distance, mtype, ...
        local _, receiver, sender, port, distance, mtype, a, b, c, d, e2, f = table.unpack(e)

        if mtype == "join" then
            local nick, color = a, b
            local id = tostring(math.random(1, 99999999))
            local x = math.random(1, FIELD_WIDTH - 1)
            local y = math.random(1, FIELD_HEIGHT - 1)
            players[id] = {nick = nick, x = x, y = y, size = 2, color = color}

            -- 1. Отправляем новичку его ID
            modem.send(sender, PORT, "join_ack", id)

            -- 2. Отправляем новичку список всех текущих игроков
            for pid, p in pairs(players) do
                modem.send(sender, PORT, "state", pid, p.nick, p.x, p.y, p.size, p.color)
            end

            -- 3. Отправляем новичку историю чата
            for _, msg in ipairs(chat) do
                modem.send(sender, PORT, "chat", msg.nick, msg.color, msg.text)
            end

            -- 4. Оповещаем ВСЕХ остальных о появлении нового игрока
            modem.broadcast(PORT, "state", id, nick, x, y, 2, color)
            
            print(nick .. " присоединился как " .. id)

        elseif mtype == "move" then
            local id, nx, ny = a, b, c
            if players[id] then
                local canMove = true
                local psize = players[id].size
                
                -- Проверка коллизий с другими игроками
                for oid, p in pairs(players) do
                    if oid ~= id then
                        -- AABB коллизия (Прямоугольник на Прямоугольник)
                        if not (nx + psize - 1 < p.x or nx > p.x + p.size - 1 or 
                                ny + psize - 1 < p.y or ny > p.y + p.size - 1) then
                            canMove = false
                            break
                        end
                    end
                end

                -- Проверка границ
                if nx < 1 or ny < 1 or nx + psize - 1 > FIELD_WIDTH or ny + psize - 1 > FIELD_HEIGHT then 
                    canMove = false 
                end

                if canMove then
                    players[id].x = nx
                    players[id].y = ny
                    -- Отправляем обновление позиции ВСЕМ
                    modem.broadcast(PORT, "state", id, players[id].nick, nx, ny, psize, players[id].color)
                end
            end

        elseif mtype == "chat" then
            local nick, color, text = a, b, c
            table.insert(chat, {nick = nick, color = color, text = text})
            if #chat > MAX_CHAT_MESSAGES then table.remove(chat, 1) end
            
            -- Рассылаем новое сообщение чата ВСЕМ
            modem.broadcast(PORT, "chat", nick, color, text)
        end
    end
end
