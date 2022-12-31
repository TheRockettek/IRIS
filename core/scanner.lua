local peripherals = require("core.peripherals")
local logging     = require("libs.logging")
local errors      = require("core.errors")

local function ScanChest(iris, name)
    assert(type(name) == "string")

    iris.logger.Debug().Str("name", name).Msg("Scanning chest")

    local chest = peripheral.wrap(name)
    if chest == nil then
        return nil, errors.ErrCouldNotWrapPeripheral
    end

    local chestData = {
        total = chest.size(),
        items = {},
    }

    local chestList = chest.list()

    for i, _ in pairs(chestList) do
        local itemDetail = chest.getItemDetail(i)
        if itemDetail then
            chestData.items[tostring(i)] = {
                name = itemDetail.name,
                display = itemDetail.display,
                count = itemDetail.count,
                max = itemDetail.maxCount,
            }
        end
    end

    return chestData, nil
end

local function ScanAllChests(iris)
    iris.logger.Debug().Msg("Scanning all chests")

    iris.isScanning = true
    iris.scanningCurrent = 0
    iris.scanningTotal = 0

    local start = os.epoch("utc")
    local chests = {}
    local chestNames = peripherals.FindAllChests(iris)

    iris.scanningTotal = #chestNames

    for index, name in pairs(chestNames) do
        iris.scanningCurrent = index

        local chest, err = ScanChest(iris, name)
        if err ~= nil then
            iris.logger.Warn().Str("name", name).Err(err).Msg("Failed to scan chest")
        else
            chests[name] = chest
        end
    end

    iris.logger.Debug().Dur("duration", start).Msg("Finished scanning chests")
    iris.isScanning = false

    return chests
end

return {
    ScanChest = ScanChest,
    ScanAllChests = ScanAllChests
}