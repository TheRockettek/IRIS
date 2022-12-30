local logging = require("libs.logging")

local chestPeripheral = "minecraft:chest"

local function FindAllChests(iris)
    local chests = {}

    local peripherals = peripheral.getNames()

    for _, value in ipairs(peripherals) do
        if value:find(chestPeripheral) then
            table.insert(chests, value)
        end
    end

    iris.logger.Debug().Str("count", #chests).Str("total", #peripherals).Msg("Found chests")

    return chests
end

return {
    FindAllChests = FindAllChests
}