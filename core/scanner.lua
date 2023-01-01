local peripherals = require("core.peripherals")
local errors      = require("core.errors")
local events      = require("core.events")
local waitgroup   = require("libs.waitgroup")

local function ScanInventory(iris, name)
    assert(type(name) == "string")

    iris.logger.Debug().Str("name", name).Msg("Scanning inventory")

    local inventory = peripheral.wrap(name)
    if inventory == nil then
        return nil, errors.ErrCouldNotWrapPeripheral
    end

    local chestSize = inventory.size()
    local chestList = inventory.list()

    local chestData = {
        totalSlots = chestSize,
        usedSlots = 0,
        totalItems = 0,
        items = {},
    }

    for i, item in pairs(chestList) do
        chestData.items[tostring(i)] = {
            name = item.name,
            count = item.count,
        }
        chestData.usedSlots = chestData.usedSlots + 1
        chestData.totalItems = chestData.totalItems + item.count
    end

    return chestData, nil
end

local function ScanAllInventories(iris)
    iris.logger.Debug().Msg("Scanning all inventories")

    os.queueEvent(events.EventIrisScanStart)

    local start = os.epoch("utc")

    local chests = {}
    local chestNames = peripherals.FindAllInventories(iris)

    local wg = waitgroup.NewWaitGroup()

    for _, name in pairs(chestNames) do
        wg.Add(function()
            local chest, err = ScanInventory(iris, name)
            if err ~= nil then
                iris.logger.Warn().Str("name", name).Err(err).Msg("Failed to scan inventory")
            else
                chests[name] = chest
            end
        end)
    end

    wg.Wait()

    iris.logger.Debug().Dur("duration", start).Msg("Finished scanning chests")

    os.queueEvent(events.EventIrisScanComplete)

    return chests
end

return {
    ScanChest = ScanInventory,
    ScanAllChests = ScanAllInventories
}
