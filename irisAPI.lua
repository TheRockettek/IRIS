local errors = require "core.errors"
local json = require "libs.json"
local logging = require "libs.logging"
local irisSerialization = require "core.iris_serialization"
local atlasSerialization = require "core.atlas_serialization"
local scanner = require "core.scanner"
local events = require "core.events"

local VERSION = "0.0.1"

local configurationPath = "iris.config"

local defaultConfiguration = {
    turtleInput = "top",
    turtleOutput = "left",

    irisFileLocation = "iris.data",
    atlasFileLocation = "atlas.data",

    scanOnStart = true,
    scanDelay = 60000 -- Time in milliseconds to wait between a chest scan. This is only used during startup.
}

local function tableContains(table, key)
    for i, _ in pairs(table) do if i == key then return true end end

    return false
end

local function NewIRIS(logger)
    local iris = {
        version = VERSION,
        logger = logger or logging.NewLogger(nil, nil),

        isIRISDataLoaded = false,
        isIRISDataDirty = false,
        irisData = { iris = { lastScannedAt = 0 }, chests = {} },

        isAtlasDataLoaded = false,
        isAtlasDataDirty = false,
        atlasData = {},

        configuration = defaultConfiguration
    }

    -- Initializes IRIS
    iris.init = function(logger)
        if logger ~= nil then iris.logger = logger end

        iris.logger.Info().Msg("IRIS Version " .. VERSION)

        -- Load configuration
        local configuration, err = iris.loadConfiguration(configurationPath)
        if err ~= nil then
            iris.logger.Warn().Err(err).Msg("Failed to load configuration")
        else
            iris.configuration = configuration
        end

        -- Validate input is wrappable
        iris.tryWrapPeripheral(iris.configuration.turtleInput)

        -- Validate output is wrappable
        iris.tryWrapPeripheral(iris.configuration.turtleOutput)

        -- Load iris data
        iris.loadIRISData()

        -- Load iris atlas data
        iris.loadIRISData()

        if iris.configuration.scanOnStart then iris.fullScan() end

        os.queueEvent(events.EventIrisInit)
    end

    -- Loads configuration. Overrides existing default configuration keys,
    -- preserving keys from the default config if not passed in a custom file.
    iris.loadConfiguration = function(path)
        if not fs.exists(path) then
            return nil, errors.ErrConfigurationDoesNotExist
        end

        local file = fs.open(path, "rb")
        local contents = file.readAll()
        file.close()

        assert(type(contents) == "string")

        local jsonDecode = json.Decode(contents)
        if jsonDecode == nil then
            return defaultConfiguration, errors.ErrFailedToJSONDecode
        end

        assert(type(jsonDecode) == "table")

        local configuration = defaultConfiguration

        for key, value in pairs(jsonDecode) do configuration[key] = value end

        return configuration, nil
    end

    -- Loads data from an IRIS file
    iris.loadIRISData = function()
        local path = iris.configuration.irisFileLocation

        if not fs.exists(path) then
            iris.logger.Warn().Msg("IRIS is loading from fresh file")

            return false
        end

        local file = fs.open(path, "rb")
        local contents = file.readAll()
        file.close()

        assert(type(contents) == "string")

        local irisData, err = irisSerialization.Decode(contents)
        if err ~= nil then
            iris.logger.Warn().Err(err).Msg("Failed to load IRIS data")
        else
            assert(type(irisData) == "table")

            iris.irisData = irisData.data
            iris.isIRISDataLoaded = true
        end

        return true
    end

    -- Saves data from memory to file. If not changes
    -- have been made indicated by isIRISDataDirty, returns false.
    iris.saveIRISData = function()
        if not iris.isAtlasDataDirty then return false, nil end

        local path = iris.configuration.irisFileLocation

        local irisDataSerialized, err = irisSerialization.Encode(iris)
        if err ~= nil then return false, err end

        local file = fs.open(path, "wb")
        file.write(irisDataSerialized)
        file.close()

        iris.isAtlasDataDirty = false

        return true, nil
    end

    -- Loads data from an IRIS file
    iris.loadAtlasData = function()
        local path = iris.configuration.atlasFileLocation

        if not fs.exists(path) then
            iris.logger.Warn().Msg("IRIS Atlas is loading from fresh file")

            return false
        end

        local file = fs.open(path, "rb")
        local contents = file.readAll()
        file.close()

        assert(type(contents) == "string")

        local atlasData, err = atlasSerialization.Decode(contents)
        if err ~= nil then
            iris.logger.Warn().Err(err).Msg("Failed to load IRIS Atlas data")
        else
            assert(type(atlasData) == "table")

            iris.atlasData = atlasData.data
            iris.isAtlasDataLoaded = true
        end

        return true
    end

    -- Saves data from memory to file. If not changes
    -- have been made indicated by isIRISDataDirty, returns false.
    iris.saveAtlasData = function()
        if not iris.isAtlasDataDirty then return false, nil end

        local path = iris.configuration.atlasFileLocation

        local atlasDataSerialized, err = atlasSerialization.Encode(iris)
        if err ~= nil then return false, err end

        local file = fs.open(path, "wb")
        file.write(atlasDataSerialized)
        file.close()

        iris.isAtlasDataDirty = false

        return true, nil
    end

    -- Performs a scan of all chests, stores and saves changes.
    -- If the last scan is before the scan delay, will not run and return false.
    iris.fullScan = function()
        local timeSince = os.epoch("utc") - iris.irisData.iris.lastScannedAt
        if timeSince < iris.configuration.scanDelay then
            iris.logger.Info().Str("since", timeSince).Str("delay",
                iris.configuration
                .scanDelay).Msg(
                "Full scan called but not hit delay")

            os.queueEvent(events.EventIrisFullScanFailed)

            return false
        end

        local chests = scanner.ScanAllChests(iris)

        iris.irisData.chests = chests
        iris.irisData.iris.lastScannedAt = os.epoch("utc")
        iris.isAtlasDataDirty = true

        local saved, err = iris.saveIRISData()
        if err ~= nil then
            iris.logger.Warn().Err(err).Msg("failed to save IRIS data")
        end

        if saved then
            iris.logger.Info().Msg("IRIS data saved successfuly")
        end

        local itemSlotsUsed, itemSlotsTotal, itemCount, itemTotal = iris.calculateUsage()
        os.queueEvent(events.EventIrisFullScan, itemSlotsUsed, itemSlotsTotal, itemCount, itemTotal)

        return true
    end

    iris.calculateUsage = function()
        local itemSlotsUsed = 0
        local itemSlotsTotal = 0
        local itemCount = 0

        for _, chestData in pairs(iris.irisData.chests) do
            itemSlotsTotal = itemSlotsTotal + chestData.totalSlots
            itemSlotsUsed = itemSlotsUsed + chestData.usedSlots
            itemCount = itemCount + chestData.totalItems
        end

        return itemSlotsUsed, itemSlotsTotal, itemCount, 0
    end

    iris.tryWrapPeripheral = function(name)
        if peripheral.wrap(name) == nil then
            iris.logger.Panic().Err(errors.ErrCouldNotWrapPeripheral).Str(
                "name", name).Msg("Failed to wrap to peripheral")

            error("failed to wrap to peripheral " .. name)
        end
    end

    -- Returns all chests that contain a specific item. Returns slot and count.
    iris.locate = function(tryScan, name)
        if tryScan then iris.fullScan() end

        local locations = {}

        for chestName, chestData in pairs(iris.irisData.chests) do
            for slotId, item in pairs(chestData.items) do
                if item.name == name then
                    table.insert(locations, {
                        peripheral = chestName,
                        slot = slotId,
                        count = item.count,
                        max = item.max
                    })
                end
            end
        end

        return locations
    end

    -- Find partial stacks of empty items.
    -- Returns list of partial stacks and empty slot candidate.
    -- Passing total store will make it only return slots that are needed.
    iris.findSpot = function(tryScan, name, totalStore, maxStack)
        local tryFindOptimalSlots = totalStore > 0

        local slots = iris.locate(tryScan, name)

        local output = {
            hasSpace = false,
            spacesMissing = 0,
            candidates = {},
            emptySlots = {}
        }

        if tryFindOptimalSlots then
            table.sort(slots, function(a, b)
                return (a.max - a.count) > (b.max - b.count)
            end)

            local toFit = totalStore

            for _, value in pairs(slots) do
                if value.count ~= value.max then
                    table.insert(output.candidates, value)
                    output.hasSpace = true

                    toFit = toFit - (value.max - value.count)
                end
            end

            -- We have filled up all slots we have in storage, find more empty space.
            if toFit > 0 then
                local emptySlots = iris.findEmptySpaces(tryScan, math.ceil(
                    toFit / maxStack))

                output.hasSpace = emptySlots.hasSpace
                output.spacesMissing = emptySlots.spacesMissing
                output.emptySlots = emptySlots.candidates
            end
        else
            local emptySlots = iris.findEmptySpaces(tryScan, math.ceil(
                totalStore / maxStack))

            output.hasSpace = emptySlots.hasSpace
            output.spacesMissing = emptySlots.spacesMissing
            output.emptySlots = emptySlots.candidates
        end

        return output
    end

    iris.findEmptySpaces = function(tryScan, maxSpacesNeeded, ignoreList)
        if type(ignoreList) == "string" then
            ignoreList = { ignoreList }
        elseif ignoreList == nil then
            ignoreList = {}
        end

        assert(type(ignoreList) == "table")

        if tryScan then iris.fullScan() end

        local output = { hasSpace = false, spacesMissing = 0, candidates = {} }

        for chestName, chestData in pairs(iris.irisData.chests) do
            if not tableContains(ignoreList, chestName) then
                if chestData.total > chestData.totalItems then
                    for slotId = 1, chestData.total, 1 do
                        if chestData.items[tostring(slotId)] == nil and
                            maxSpacesNeeded > 0 then
                            table.insert(output.candidates, {
                                peripheral = chestName,
                                slot = slotId
                            })

                            maxSpacesNeeded = maxSpacesNeeded - 1
                            output.hasSpace = true
                        end
                    end

                    if maxSpacesNeeded <= 0 then break end
                end
            end
        end

        -- If we have a number greater than 0, we do not have enough spaces available.
        output.hasSpace = maxSpacesNeeded > 0
        output.spacesMissing = maxSpacesNeeded

        return output
    end

    -- Returns all items based on locations.
    iris.flatten = function(tryScan)
        if tryScan then iris.fullScan() end

        local items = {}

        for chestName, chestData in pairs(iris.irisData.chests) do
            for slotId, item in pairs(chestData.items) do
                if items[item.name] == nil then
                    items[item.name] = {}
                end

                table.insert(items[item.name], {
                    peripheral = chestName,
                    slot = slotId,
                    count = item.count,
                })
            end
        end

        return items
    end

    -- Returns data from atlas.
    iris.getFromAtlas = function(name)
        local data = iris.atlasData[name]

        return data
    end

    -- Returns data from atlas. If it does not exist,
    -- will try fetch data.
    iris.fetchFromAtlas = function(name)
        local data = iris.getFromAtlas(name)
        if data ~= nil then return data, nil end

        -- Try fetch from local storage

        -- Identify item

        -- Store in atlas

        return data, nil
    end

    -- Updates atlas entry.
    iris.updateAtlasEntry = function(name, maxCount, tags)
        local orig = iris.atlasData[name]

        iris.atlasData[name] = { max = maxCount, tags = tags }

        if orig ~= iris.atlasData[name] then
            iris.isAtlasDataDirty = true

            return true
        end

        return false
    end

    -- IRIS operations

    -- Pushes all items in local inventory back into IRIS.
    iris.flushLocal = function()
        local err = nil
        local items = 0

        for slotId = 1, 16, 1 do
            if turtle.getItemCount() > 0 then
                local pitems, perr = iris.pushLocal(slotId)
                if perr ~= nil then err = perr end
                items = items + pitems
            end
        end

        return items, err
    end

    -- Pulls an item from IRIS into local inventory.
    iris.pullLocal = function(name, slotId, fillTo, saveData)
        -- Check current item in slot is empty or can fit

        local originalItemCount = fillTo

        turtle.select(slotId)
        local item = turtle.getItemDetail()
        if item ~= nil then
            if item.name == name then
                local itemCount = turtle.getItemCount()
                fillTo = fillTo - itemCount
            end
        end

        if fillTo <= 0 then
            -- We have enough items.
            return fillTo, nil
        end

        -- Identify max items in a stack
        local maxItems = 64
        local atlasEntry = iris.getFromAtlas(name)
        if atlasEntry then maxItems = atlasEntry.max end

        local locations = iris.locate(false, name)
        for _, location in pairs(locations) do
            local transferCount = math.min(maxItems, fillTo)

            local transferred, err = iris._pull(location.peripheral, slotId,
                location.slot, transferCount)
            if err == nil then fillTo = fillTo - transferred end
        end

        if saveData then
            iris.saveIRISData()
            iris.saveAtlasData()
        end

        return originalItemCount - fillTo, nil
    end

    -- Pushes an item from local inventory into IRIS.
    iris.pushLocal = function(slotId, saveData)
        turtle.select(slotId)
        local item = turtle.getItemDetail()
        if item == nil then return 0, nil end

        local itemCount = turtle.getItemCount()
        local originalItemCount = itemCount

        local itemMax = turtle.getItemSpace() + itemCount

        iris.updateAtlasEntry(item.name, itemMax, nil)

        local result = iris.findSpot(false, item.name, itemCount, itemMax)
        if not result.hasSpace then return 0, errors.ErrIRISMissingSpace end

        -- Use existing slots.
        for _, candidate in pairs(result.candidates) do
            local transferCount = math.max(itemCount, itemMax - candidate.count)

            local transferred, err = iris._push(candidate.peripheral, slotId,
                candidate.slot, transferCount)
            if err == nil then itemCount = itemCount - transferred end

            if itemCount <= 0 then break end
        end

        -- Use empty space if necessary.
        if itemCount > 0 then
            for _, emptySlot in pairs(result.emptySlots) do
                local chest = peripheral.wrap(emptySlot.peripheral)
                if chest then
                    local transferCount = math.max(itemCount, itemMax)

                    local transferred, err =
                    iris._push(emptySlot.peripheral, slotId, emptySlot.slot,
                        transferCount)
                    if err == nil then
                        itemCount = itemCount - transferred
                    end

                    if itemCount <= 0 then break end
                end
            end
        end

        if saveData then
            iris.saveIRISData()
            iris.saveAtlasData()
        end

        return originalItemCount - itemCount, nil
    end

    -- Pulls an item from IRIS. Inserts into turtleOutput.
    iris.pull = function(name, count, saveData)
        iris.flushLocal()

        -- Identify max items in a stack
        local maxItems = 64
        local atlasEntry = iris.getFromAtlas(name)
        if atlasEntry then maxItems = atlasEntry.max end

        for i = 1, 16, 1 do
            local transferred, err = iris.pullLocal(name, i,
                math.min(count, maxItems),
                false)
            if err == nil then count = count - transferred end

            if count <= 0 then break end
        end

        local err = iris._pushOutput()
        if err ~= nil then return err end

        if count > 0 then iris.pull(name, count, false) end

        if saveData then
            iris.saveIRISData()
            iris.saveAtlasData()
        end

        return nil
    end

    -- Pushes items from turtleInput into IRIS.
    iris.push = function(saveData)
        iris.flushLocal()

        -- Try up to 10 times.
        for _ = 1, 10, 1 do
            local items, err = iris._pullInput()
            if err then return err end

            if items > 0 then
                iris.flushLocal()
            else
                break
            end
        end

        if saveData then
            iris.saveIRISData()
            iris.saveAtlasData()
        end

        return nil
    end

    iris._pullInput = function()
        local totalItems = 0

        local inventory = peripheral.wrap(iris.configuration.turtleInput)
        if inventory == nil then return 0, errors.ErrCouldNotWrapPeripheral end

        local items = inventory.items()

        for periphalSlot, item in pairs(items) do
            local hasSpace = false

            for i = 1, 16, 1 do
                turtle.select(i)
                if turtle.getItemCount() == 0 then
                    local count = inventory.pullItem(iris.configuration
                        .turtleInput, i,
                        item.count, periphalSlot)
                    if count > 0 then
                        totalItems = totalItems + count
                        hasSpace = true
                    end
                end
            end

            if not hasSpace then break end
        end

        return items, nil
    end

    iris._pushOutput = function()
        local totalItems = 0

        local inventory = peripheral.wrap(iris.configuration.turtleOutput)
        if inventory == nil then return 0, errors.ErrCouldNotWrapPeripheral end

        for i = 1, 16, 1 do
            turtle.select(i)
            local count = turtle.getItemCount()
            if count > 0 then
                count = inventory.pushItem(iris.configuration.turtleOutput, i,
                    count)
                if count > 0 then totalItems = totalItems + count end
            end
        end

        return totalItems, nil
    end

    iris._pull = function(peripheral, localSlot, peripheralSlot, count)
        local inventory = peripheral.wrap(peripheral)
        if inventory == nil then return 0, errors.ErrCouldNotWrapPeripheral end

        local transferred = inventory.pullItem(peripheral, localSlot, count,
            peripheralSlot)

        -- ScanChest if not stored
        if iris.irisData.chests[peripheral] == nil then
            local chest = scanner.ScanChest(iris, peripheral)

            iris.irisData.chests[peripheral] = chest
            iris.isIRISDataDirty = true
        else
            -- ScanChest if we don't store an item here or what we store does not make sense.
            if iris.irisData.chests[peripheral].slots[tostring(peripheralSlot)] ==
                nil or
                iris.irisData.chests[peripheral].slots[tostring(peripheralSlot)]
                .count == nil then
                local chest = scanner.ScanChest(iris, peripheral)

                iris.irisData.chests[peripheral] = chest
                iris.isIRISDataDirty = true
            else
                iris.irisData.chests[peripheral].slots[tostring(peripheralSlot)]
                    .count = iris.irisData.chests[peripheral].slots[tostring(
                    peripheralSlot)].count - transferred
                iris.isIRISDataDirty = true
            end
        end
    end

    iris._push = function(peripheral, localSlot, peripheralSlot, count)
        local inventory = peripheral.wrap(peripheral)
        if inventory == nil then return 0, errors.ErrCouldNotWrapPeripheral end

        local transferred = inventory.pushItem(peripheral, localSlot, count,
            peripheralSlot)

        -- ScanChest if not stored
        if iris.irisData.chests[peripheral] == nil then
            local chest = scanner.ScanChest(iris, peripheral)

            iris.irisData.chests[peripheral] = chest
            iris.isIRISDataDirty = true
        else
            -- ScanChest if we don't store an item here or what we store does not make sense.
            if iris.irisData.chests[peripheral].slots[tostring(peripheralSlot)] ==
                nil or
                iris.irisData.chests[peripheral].slots[tostring(peripheralSlot)]
                .count == nil then
                local chest = scanner.ScanChest(iris, peripheral)

                iris.irisData.chests[peripheral] = chest
                iris.isIRISDataDirty = true
            else
                iris.irisData.chests[peripheral].slots[tostring(peripheralSlot)]
                    .count = iris.irisData.chests[peripheral].slots[tostring(
                    peripheralSlot)].count + transferred
                iris.isIRISDataDirty = true
            end
        end

        return transferred, nil
    end

    return iris
end

return { NewIRIS = NewIRIS }
