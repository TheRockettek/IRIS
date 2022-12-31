local peripherals = require("core.peripherals")
local errors      = require("core.errors")
local events      = require("core.events")
local waitgroup   = require("libs.waitgroup")
local items       = require("core.items")

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

    for i, item in pairs(chestList) do
        chestData.items[tostring(i)] = {
            name = item.name,
            display = item.name,
            count = item.count,
            max = items.GetItemMaxStack(item.name),
        }
    end

    -- for i, _ in pairs(chestList) do
    --     local itemDetail = chest.getItemDetail(i)
    --     if itemDetail then
    --         chestData.items[tostring(i)] = {
    --             name = itemDetail.name,
    --             display = itemDetail.display,
    --             count = itemDetail.count,
    --             max = itemDetail.maxCount,
    --         }
    --     end
    -- end

    return chestData, nil
end

local function ScanAllChests(iris)
    iris.logger.Debug().Msg("Scanning all chests")

    os.queueEvent(events.EventIrisScanStart)

    local start = os.epoch("utc")
    local chests = {}
    local chestNames = peripherals.FindAllChests(iris)

    local wg = waitgroup.NewWaitGroup()

    for _, name in pairs(chestNames) do
        wg.Add(function()
            local chest, err = ScanChest(iris, name)
            if err ~= nil then
                iris.logger.Warn().Str("name", name).Err(err).Msg("Failed to scan chest")
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
    ScanChest = ScanChest,
    ScanAllChests = ScanAllChests
}