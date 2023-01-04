local peripherals = require("core.peripherals")
local waitgroup   = require("libs.waitgroup")

local function ScanInventory(inventories, wg, iris, name)
    assert(type(inventories) == "table")
    assert(type(iris) == "table")
    assert(type(name) == "string")

    iris.logger.Debug().Str("name", name).Msg("[TINTER] Scanning inventory")

    local inventorySize = peripheral.call(name, "size")

    local internalWaitGroup = wg == nil
    if internalWaitGroup then
        wg = waitgroup.NewWaitGroup()
    end

    if inventorySize then
        for i = 1, inventorySize, 1 do
            wg.Add(function()
                local item = peripheral.call(name, "getItemDetail", i)

                if inventories[name] == nil then
                    inventories[name] = {
                        totalSlots = inventorySize,
                        usedSlots = 0,
                        totalItems = 0,
                        itemMaxCount = 0,
                        items = {},
                    }
                end


                if item then
                    inventories[name].items[tostring(i)] = {
                        name = item.name,
                        count = item.count,

                        display = item.displayName,
                        max = item.maxCount,
                        nbt = item.nbt,
                        tags = item.tags,
                    }
                    inventories[name].usedSlots = inventories[name].usedSlots + 1
                    inventories[name].totalItems = inventories[name].totalItems + item.count
                    inventories[name].itemMaxCount = inventories[name].itemMaxCount + item.maxCount
                else
                    inventories[name].itemMaxCount = inventories[name].itemMaxCount + 64
                end
            end)
        end

        if internalWaitGroup then
            wg.Wait(20)
        end
    else
        iris.logger.Warn().Str("name", name).Msg("Failed to get size of inventory")
    end

    return inventorySize ~= nil and inventorySize > 0
end

local function ScanAllInventories(iris)
    iris.logger.Info().Msg("Scanning all inventories")

    local start = os.epoch("utc")

    local inventories = {}
    local inventoryNames = peripherals.FindAllInventories(iris)

    local wg = waitgroup.NewWaitGroup()
    for _, name in pairs(inventoryNames) do
        wg.Add(function()
            ScanInventory(inventories, wg, iris, name)
        end)
    end
    wg.Wait(20)

    iris.logger.Info().Dur("duration", start).Msg("Finished scanning inventories")

    return inventories
end

return {
    ScanInventory = ScanInventory,
    ScanAllInventories = ScanAllInventories
}
