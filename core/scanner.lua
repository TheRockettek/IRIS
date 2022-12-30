local peripherals = require("core.peripherals")
local logging     = require("libs.logging")
local errors      = require("core.errors")

local function ScanChest(name)
    assert(type(name) == "string")

    logging.Logger.Debug().Str("name", name).Msg("Scanning chest")

    chest = peripheral.wrap(name)
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

local function ScanAllChests()
    logging.Logger.Debug().Msg("Scanning all chests")

    start = os.epoch("utc")

    local chests = {}
    local chestNames = peripherals.FindAllChests()

    for _, name in pairs(chestNames) do
        local chest, err = ScanChest(name)
        if err ~= nil then
            logging.Logger.Warn().Str("name", name).Err(err).Msg("Failed to scan chest")
        else
            chests[name] = chest
        end
    end

    logging.Logger.Debug().Dur("duration", start).Msg("Finished scanning chests")

    return chests
end

return {
    ScanChest = ScanChest,
    ScanAllChests = ScanAllChests
}