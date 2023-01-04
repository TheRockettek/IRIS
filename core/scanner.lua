local peripherals = require("core.peripherals")
local waitgroup   = require("libs.waitgroup")

local function ScanInventory(inventories, wg, iris, name)
    assert(type(inventories) == "table")
    assert(type(iris) == "table")
    assert(type(name) == "string")

    local inventoryPeripheral = peripheral.wrap(name)
    if inventoryPeripheral == nil then
        return
    end

    iris.logger.Debug().Str("name", name).Msg("[TINTER] Scanning inventory")

    local start = os.epoch("utc")

    local inventorySize = inventoryPeripheral.size()

    local internalWaitGroup = wg == nil
    if internalWaitGroup then
        wg = waitgroup.NewWaitGroup()
    end

    for i = 1, inventorySize, 1 do
        wg.Add(function()
            local item = inventoryPeripheral.getItemDetail(i)

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
        wg.Wait()
    end

    iris.logger.Debug().Str("name", name).Dur("duration", start).Str("isBlocking", internalWaitGroup).Msg("[TINTER] Scanned inventory")
end

local function ScanAllInventories(iris)
    iris.logger.Info().Msg("Scanning all inventories")

    local start = os.epoch("utc")

    local inventories = {}
    local inventoryNames = peripherals.FindAllInventories(iris)

    local wg = waitgroup.NewWaitGroup()
    for _, name in pairs(inventoryNames) do
        ScanInventory(inventories, wg, iris, name)
    end
    wg.Wait()

    iris.logger.Info().Dur("duration", start).Msg("Finished scanning inventories")

    return inventories
end

return {
    ScanInventory = ScanInventory,
    ScanAllInventories = ScanAllInventories
}
