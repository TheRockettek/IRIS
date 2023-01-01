local peripherals = require("core.peripherals")
local errors      = require("core.errors")
local events      = require("core.events")
local waitgroup   = require("libs.waitgroup")

local function ScanInventory(iris, name)
    assert(type(name) == "string")

    iris.logger.Debug().Str("name", name).Msg("[TINTER] Scanning inventory")

    local inventory = peripheral.wrap(name)
    if inventory == nil then
        return nil, errors.ErrCouldNotWrapPeripheral
    end

    local inventorySize = inventory.size()
    local inventoryList = inventory.list()

    local inventoryData = {
        totalSlots = inventorySize,
        usedSlots = 0,
        totalItems = 0,
        items = {},
    }

    local wg = waitgroup.NewWaitGroup()

    for i = 1, inventorySize, 1 do
        wg.Add(function()
            local item = inventoryData.getItemDetail(i)
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

    -- for i, item in pairs(inventoryList) do
    --     inventoryData.items[tostring(i)] = {
    --         name = item.name,
    --         count = item.count,

    --         display = "",
    --         max = 0,
    --         nbt = "",
    --     }
    --     inventoryData.usedSlots = inventoryData.usedSlots + 1
    --     inventoryData.totalItems = inventoryData.totalItems + item.count
    -- end

    return inventoryData, nil
end

local function ScanAllInventories(iris)
    iris.logger.Debug().Msg("Scanning all inventories")

    os.queueEvent(events.EventIrisScanStart)

    local start = os.epoch("utc")

    local inventories = {}
    local inventoryNames = peripherals.FindAllInventories(iris)

    local wg = waitgroup.NewWaitGroup()

    for _, name in pairs(inventoryNames) do
        wg.Add(function()
            local inventory, err = ScanInventory(iris, name)
            if err ~= nil then
                iris.logger.Warn().Str("name", name).Err(err).Msg("Failed to scan inventory")
            else
                inventories[name] = inventory
            end
        end)
    end

    wg.Wait()

    iris.logger.Debug().Dur("duration", start).Msg("Finished scanning inventories")

    os.queueEvent(events.EventIrisScanComplete)

    return inventories
end

return {
    ScanInventory = ScanInventory,
    ScanAllInventories = ScanAllInventories
}
