local component = require("component")
local event = require("event")
local term = require("term")
local computer = require("computer")
local gpu = component.gpu

-- инициализация экрана
local maxW, maxH = gpu.maxResolution()
gpu.setResolution(maxW, maxH)
term.clear()

-- размеры поля
local width, height = gpu.getResolution()

-- позиция игрока
local player = {
  x = math.floor(width / 2),
  y = math.floor(height / 2),
  char = "█"
}

-- отрисовка
local function draw()
  term.clear()
  gpu.set(player.x, player.y, player.char)
end

draw()

-- основной цикл
while true do
  local _, _, _, key = event.pull("key_down")

  if key == 16 then -- Q
    term.clear()
    break
  elseif key == 17 then -- W
    if player.y > 1 then player.y = player.y - 1 end
  elseif key == 31 then -- S
    if player.y < height then player.y = player.y + 1 end
  elseif key == 30 then -- A
    if player.x > 1 then player.x = player.x - 1 end
  elseif key == 32 then -- D
    if player.x < width then player.x = player.x + 1 end
  end

  draw()
end
