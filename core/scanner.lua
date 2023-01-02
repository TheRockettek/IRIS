local peripherals = require("core.peripherals")
local errors      = require("core.errors")
local events      = require("core.events")
local waitgroup   = require("libs.waitgroup")

local function ScanInventory(iris, name, inventory)
    assert(type(inventory) == "table")

    iris.logger.Debug().Str("name", name).Msg("[TINTER] Scanning inventory")

    local start = os.epoch("utc")

    local inventorySize = inventory.size()

    local inventoryData = {
        totalSlots = inventorySize,
        usedSlots = 0,
        totalItems = 0,
        items = {},
    }

    local wg = waitgroup.NewWaitGroup()

    for i = 1, inventorySize, 1 do
        wg.Add(function()
            local item = inventory.getItemDetail(i)

            if item then
                inventoryData.items[tostring(i)] = {
                    name = item.name,
                    count = item.count,

                    display = item.displayName,
                    max = item.maxCount,
                    nbt = item.nbt,
                    tags = item.tags,
                }
                inventoryData.usedSlots = inventoryData.usedSlots + 1
                inventoryData.totalItems = inventoryData.totalItems + item.count
            end
        end)
    end

    wg.Wait()

    iris.logger.Debug().Str("name", name).Dur("duration", start).Msg("[TINTER] Scanned inventory")

    return inventoryData, nil
end

local function ScanAllInventories(iris)
    iris.logger.Info().Msg("Scanning all inventories")

    local start = os.epoch("utc")

    local inventories = {}
    local inventoryNames = peripherals.FindAllInventories(iris)

    for _, name in pairs(inventoryNames) do

        local inventoryPeripheral = peripheral.wrap(name)
        if inventoryPeripheral ~= nil then
            local inventory, err = ScanInventory(iris, name, inventoryPeripheral)
            if err ~= nil then
                iris.logger.Warn().Str("name", name).Err(err).Msg("Failed to scan inventory")
            else
                inventories[name] = inventory
            end
        end
    end

    iris.logger.Info().Dur("duration", start).Msg("Finished scanning inventories")

    return inventories
end

return {
    ScanInventory = ScanInventory,
    ScanAllInventories = ScanAllInventories
}
