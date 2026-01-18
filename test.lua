local component = require("component")
local event = require("event")
local term = require("term")
local computer = require("computer")
local gpu = component.gpu

-- экран
local maxW, maxH = gpu.maxResolution()
gpu.setResolution(maxW, maxH)
term.clear()

local width, height = gpu.getResolution()

-- цвет игрока (синий)
local PLAYER_COLOR = 0x0000FF
local BG_COLOR = 0x000000

-- игрок 2x2
local player = {
  x = math.floor(width / 2),
  y = math.floor(height / 2),
  size = 2
}

-- ограничение скорости
local MOVE_DELAY = 0.1 -- секунды
local lastMove = 0

local function drawPlayer()
  gpu.setForeground(PLAYER_COLOR)
  for dx = 0, player.size - 1 do
    for dy = 0, player.size - 1 do
      gpu.set(player.x + dx, player.y + dy, "█")
    end
  end
  gpu.setForeground(0xFFFFFF)
end

local function draw()
  term.clear()
  drawPlayer()
end

draw()

while true do
  local e = {event.pull(0.05)}
  if e[1] == "key_down" then
    local key = e[4]
    local now = computer.uptime()

    if key == 16 then -- Q
      term.clear()
      gpu.setForeground(0xFFFFFF)
      break
    end

    if now - lastMove >= MOVE_DELAY then
      if key == 17 then -- W
        if player.y > 1 then player.y = player.y - 1 end
      elseif key == 31 then -- S
        if player.y + player.size - 1 < height then
          player.y = player.y + 1
        end
      elseif key == 30 then -- A
        if player.x > 1 then player.x = player.x - 1 end
      elseif key == 32 then -- D
        if player.x + player.size - 1 < width then
          player.x = player.x + 1
        end
      end

      lastMove = now
      draw()
    end
  end
end
