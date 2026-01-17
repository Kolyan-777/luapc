local component = require("component")
local computer = require("computer")
local event = require("event")
local term = require("term")

term.clear()

print("=== OpenComputers test script ===")
print("Uptime: " .. math.floor(computer.uptime()) .. " sec")
print("Energy: " .. math.floor(computer.energy()) .. " / " .. computer.maxEnergy())

print("\nAvailable components:")
for address, ctype in component.list() do
  print(ctype .. " : " .. address)
end

print("\nPress any key to continue...")

-- ждём нажатие клавиши
event.pull("key_down")

term.clear()
print("Test finished successfully.")
