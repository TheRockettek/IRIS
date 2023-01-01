local errors = require "core.errors"
local logging = require "libs.logging"
local irisSerialization = require "core.iris_serialization"
local atlasSerialization = require "core.atlas_serialization"
local scanner = require "core.scanner"
local events = require "core.events"

local VERSION = "0.0.1"

local configurationPath = "iris.config"

-- We need the turtle to be able to interact directly with this inventory
local turtleInventoryRelative = "bottom"

local defaultConfiguration = {
    inputInventory = "top",
    outputInventory = "left",
    turtleInventory = "bottom",

    irisFileLocation = "iris.data",
    atlasFileLocation = "atlas.data",

    scanOnStart = true,
    scanDelay = 60000 -- Time in milliseconds to wait between an inventory scan. This is only used during startup.
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
        irisData = { iris = { lastScannedAt = 0 }, inventories = {} },

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
        iris.tryWrapPeripheral(iris.configuration.inputInventory)

        -- Validate output is wrappable
        iris.tryWrapPeripheral(iris.configuration.outputInventory)

        -- Validate buffer is wrappable
        iris.tryWrapPeripheral(turtleInventoryRelative)
        iris.tryWrapPeripheral(iris.configuration.turtleInventory)

        -- Load iris data
        iris.loadIRISData()

        -- Load iris atlas data
        iris.loadAtlasData()

        if iris.configuration.scanOnStart then iris.fullScan() end

        os.queueEvent(events.EventIrisInit)
    end

    -- Loads configuration. Overrides existing default configuration keys,
    -- preserving keys from the default config if not passed in a custom file.
    iris.loadConfiguration = function(path)
        iris.logger.Trace().Str("_name", "loadConfiguration").Send()

        if not fs.exists(path) then
            return nil, errors.ErrConfigurationDoesNotExist
        end

        local file = fs.open(path, "rb")
        local contents = file.readAll()
        file.close()

        assert(type(contents) == "string")

        local jsonDecode = textutils.unserializeJson(contents)
        if jsonDecode == nil then
            return defaultConfiguration, errors.ErrFailedToJSONDecode
        end

        assert(type(jsonDecode) == "table")

        local configuration = defaultConfiguration

        for key, value in pairs(jsonDecode) do configuration[key] = value end

        return configuration, nil
    end

    iris.save = function()
        iris.logger.Trace().Str("_name", "save").Send()

        local _, ierr = iris.saveIRISData()
        local _, aerr = iris.saveAtlasData()

        return ierr or aerr
    end

    -- Loads data from an IRIS file
    iris.loadIRISData = function()
        iris.logger.Trace().Str("_name", "loadIRISsData").Send()

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
        iris.logger.Trace().Str("_name", "saveIRISData").Send()


        if not iris.isIRISDataDirty then
            iris.logger.Info().Msg("Skipped saving IRIS data")
            return false, nil
        end

        local start = os.epoch("utc")
        iris.logger.Debug().Msg("Saving IRIS data")

        local path = iris.configuration.irisFileLocation

        local irisDataSerialized, err = irisSerialization.Encode(iris)
        if err ~= nil then return false, err end

        local file = fs.open(path, "wb")
        file.write(irisDataSerialized)
        file.close()

        iris.isAtlasDataDirty = false

        iris.logger.Info().Dur("duration", start).Msg("Saved IRIS data")

        return true, nil
    end

    -- Loads data from an IRIS file
    iris.loadAtlasData = function()
        iris.logger.Trace().Str("_name", "loadAtlasData").Send()

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
        iris.logger.Trace().Str("_name", "saveAtlasData").Send()

        if not iris.isAtlasDataDirty then
            iris.logger.Info().Msg("Skipped saving IRIS Atlas")
            return false, nil
        end

        local start = os.epoch("utc")
        iris.logger.Debug().Msg("Saving IRIS Atlas")

        local path = iris.configuration.atlasFileLocation

        local atlasDataSerialized, err = atlasSerialization.Encode(iris)
        if err ~= nil then return false, err end

        local file = fs.open(path, "wb")
        file.write(atlasDataSerialized)
        file.close()

        iris.isAtlasDataDirty = false

        iris.logger.Info().Dur("duration", start).Msg("Saved IRIS Atlas")

        return true, nil
    end

    -- Performs a scan of all inventories, stores and saves changes.
    -- If the last scan is before the scan delay, will not run and return false.
    iris.fullScan = function()
        iris.logger.Trace().Str("_name", "fullScan").Send()

        local timeSince = os.epoch("utc") - iris.irisData.iris.lastScannedAt
        if timeSince < iris.configuration.scanDelay then
            iris.logger.Info().Str("since", timeSince).Str("delay",
                iris.configuration
                .scanDelay).Msg(
                "Full scan called but not hit delay")

            os.queueEvent(events.EventIrisFullScanFailed)

            return false
        end

        local inventories = scanner.ScanAllInventories(iris)

        iris.irisData.inventories = inventories
        iris.irisData.iris.lastScannedAt = os.epoch("utc")
        iris.isIRISDataDirty = true

        local err = iris.save()
        if err ~= nil then
            iris.logger.Warn().Err(err).Msg("Failed to save data")
        end

        local itemSlotsUsed, itemSlotsTotal, itemCount, itemTotal = iris.calculateUsage()
        os.queueEvent(events.EventIrisFullScan, itemSlotsUsed, itemSlotsTotal, itemCount, itemTotal)

        return true
    end

    iris.calculateUsage = function()
        iris.logger.Trace().Str("_name", "calculateUsage").Send()

        local itemSlotsUsed = 0
        local itemSlotsTotal = 0
        local itemCount = 0

        for _, inventoriesData in pairs(iris.irisData.inventories) do
            itemSlotsTotal = itemSlotsTotal + inventoriesData.totalSlots
            itemSlotsUsed = itemSlotsUsed + inventoriesData.usedSlots
            itemCount = itemCount + inventoriesData.totalItems
        end

        return itemSlotsUsed, itemSlotsTotal, itemCount, 0
    end

    iris.tryWrapPeripheral = function(name)
        iris.logger.Trace().Str("_name", "tryWrapPeripheral").Str("name", name).Send()

        if peripheral.wrap(name) == nil then
            iris.logger.Panic().Err(errors.ErrCouldNotWrapPeripheral).Str(
                "name", name).Msg("Failed to wrap to peripheral")

            error("failed to wrap to peripheral " .. name)
        end
    end

    -- Returns all inventories that contain a specific item. Returns slot and count.
    iris.locate = function(name)
        iris.logger.Trace().Str("_name", "locate").Str("name", name).Send()

        local locations = {}

        local maxStack = 1
        local atlasEntry = iris.getFromAtlas(name)
        if atlasEntry then
            maxStack = atlasEntry.max
        end

        for inventoryName, inventoryData in pairs(iris.irisData.inventories) do
            for slotId, item in pairs(inventoryData.items) do
                if item.name == name then
                    table.insert(locations, {
                        peripheral = inventoryName,
                        slot = tonumber(slotId),
                        count = item.count,
                        max = maxStack,
                    })
                end
            end
        end

        return locations
    end

    -- Find partial stacks of empty items.
    -- Returns list of partial stacks and empty slot candidate.
    -- Passing total store will make it only return slots that are needed.
    iris.findSpot = function(name, totalStore, maxStack, ignoreList)
        iris.logger.Trace().Str("_name", "findSpot").Str("name", name).Str("totalStore", totalStore).Str("maxStack",
            maxStack).Json("ignoreList",
            ignoreList).Send()

        local start = os.epoch("utc")

        if type(ignoreList) == "string" then
            ignoreList = { ignoreList }
        elseif ignoreList == nil then
            ignoreList = {}
        end

        local tryFindOptimalSlots = totalStore > 0

        local slots = iris.locate(name)

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
                if not tableContains(ignoreList, value.peripheral) then
                    if value.count ~= value.max then
                        table.insert(output.candidates, value)
                        output.hasSpace = true

                        toFit = toFit - (value.max - value.count)
                    end
                end
            end

            -- We have filled up all slots we have in storage, find more empty space.
            if toFit > 0 then
                local emptySlots = iris.findEmptySpaces(math.ceil(
                    toFit / maxStack), ignoreList)

                output.hasSpace = emptySlots.hasSpace
                output.spacesMissing = emptySlots.spacesMissing
                output.emptySlots = emptySlots.candidates
            end
        else
            local emptySlots = iris.findEmptySpaces(math.ceil(
                totalStore / maxStack), ignoreList)

            output.hasSpace = emptySlots.hasSpace
            output.spacesMissing = emptySlots.spacesMissing
            output.emptySlots = emptySlots.candidates
        end

        iris.logger.Trace().Str("hasSpace", output.hasSpace).Str("spacesMissing", output.spacesMissing).Json("emptySlots"
            , output.emptySlots).Json("candidates", output.candidates).Dur("duration", start).Msg("Completed finding spot")

        return output
    end

    iris.findEmptySpaces = function(maxSpacesNeeded, ignoreList)
        iris.logger.Trace().Str("_name", "findEmptySpaces").Str("maxSpacesNeeded", maxSpacesNeeded).Json("ignoreList",
            ignoreList).Send()

        local start = os.epoch("utc")

        if type(ignoreList) == "string" then
            ignoreList = { ignoreList }
        elseif ignoreList == nil then
            ignoreList = {}
        end

        assert(type(ignoreList) == "table")

        local output = { hasSpace = false, spacesMissing = 0, candidates = {} }

        for inventoryName, inventoryData in pairs(iris.irisData.inventories) do
            iris.logger.Trace().Str("name", inventoryName).Msg("Looking for spaces")
            if not tableContains(ignoreList, inventoryName) then
                iris.logger.Trace().Str("used", inventoryData.usedSlots).Str("total", inventoryData.totalSlots).Msg("Inventory is not ignored")
                if inventoryData.usedSlots < inventoryData.totalSlots then
                    iris.logger.Trace().Msg("Inventory has space")
                    for slotId = 1, inventoryData.totalSlots, 1 do
                        iris.logger.Trace().Str("slotId", slotId).Json("slot", inventoryData.items[tostring(slotId)]).Str("maxspace"
                            , maxSpacesNeeded).Msg("Scanning slot")
                        if inventoryData.items[tostring(slotId)] == nil and
                            maxSpacesNeeded > 0 then
                            table.insert(output.candidates, {
                                peripheral = inventoryName,
                                slot = tonumber(slotId)
                            })

                            maxSpacesNeeded = maxSpacesNeeded - 1
                            output.hasSpace = true

                            iris.logger.Trace().Str("newSpacesNeeded", maxSpacesNeeded).Msg("Added slot")
                        end
                    end

                    if maxSpacesNeeded <= 0 then break end
                end
            end
        end

        -- If we have a number greater than 0, we do not have enough spaces available.
        output.hasSpace = maxSpacesNeeded == 0
        output.spacesMissing = maxSpacesNeeded

        iris.logger.Trace().Json("candidates", output.candidates).Dur("duration", start).Msg("Completed finding empty spaces")

        return output
    end

    -- Returns all items based on locations.
    iris.flatten = function()
        iris.logger.Trace().Str("_name", "flatten").Send()

        local items = {}

        for inventoryName, inventoryData in pairs(iris.irisData.inventories) do
            for slotId, item in pairs(inventoryData.items) do
                if items[item.name] == nil then
                    items[item.name] = {}
                end

                local maxStack = 1
                local atlasEntry = iris.getFromAtlas(item.name)
                if atlasEntry then
                    maxStack = atlasEntry.max
                end

                table.insert(items[item.name], {
                    peripheral = inventoryName,
                    slot = tonumber(slotId),
                    count = item.count,
                    max = maxStack,
                })
            end
        end

        return items
    end

    -- Returns data from atlas.
    iris.getFromAtlas = function(name)
        iris.logger.Trace().Str("_name", "getFromAtlas").Str("name", name).Send()

        local data = iris.atlasData[name]

        return data
    end

    -- Returns data from atlas. If it does not exist,
    -- will try fetch data.
    iris.fetchFromAtlas = function(name)
        iris.logger.Trace().Str("_name", "fetchFromAtlas").Str("name", name).Send()

        local data = iris.getFromAtlas(name)
        if data ~= nil then return data, nil end

        local locations = iris.locate(name)
        for _, location in pairs(locations) do
            local inventory = peripheral.wrap(location.peripheral)
            if inventory ~= nil then
                local itemDetail = inventory.getItemDetail(location.slot)
                if itemDetail ~= nil and itemDetail.name == name then
                    local atlasEntry = iris.updateAtlasEntry(name, itemDetail.displayName, itemDetail.maxCount,
                        itemDetail.tags)

                    return atlasEntry, nil
                else
                    iris.logger.Warn().Str("name", name).Str("peripheral", location.peripheral).Str("slot", location.slot)
                        .Json("itemDetail", itemDetail).Msg("getItemDetail did not match expected item")
                end
            end
        end

        return nil, errors.ErrIRISMissingItems
    end

    -- Updates atlas entry.
    iris.updateAtlasEntry = function(name, displayName, maxCount, tags)
        iris.logger.Trace().Str("_name", "updateAtlasEntry").Str("displayName", displayName).Str("maxCount", maxCount).Json("tags"
            , tags).Send()

        local orig = iris.atlasData[name]

        iris.atlasData[name] = { displayName = displayName, max = maxCount, tags = tags }

        if orig ~= iris.atlasData[name] then
            iris.isAtlasDataDirty = true
        end

        return iris.atlasData[name]
    end

    -- IRIS operations

    iris.pullItemFromIRIS = function(name, count)
        iris.logger.Trace().Str("_name", "pullItemFromIRIS").Str("name", name).Str("count", count).Send()

        return iris._pullItemIntoInventory(iris.configuration.outputInventory, name, count)
    end

    iris.pushInputIntoIRIS = function()
        iris.logger.Trace().Str("_name", "pushInputIntoIRIS").Send()

        return iris._pushInventoryIntoIRIS(iris.configuration.inputInventory)
    end

    iris.pullItemIntoBuffer = function(name, count)
        iris.logger.Trace().Str("_name", "pullItemIntoBuffer").Str("name", name).Str("count", count).Send()

        return iris._pullItemIntoInventory(iris.configuration.turtleInventory, name, count)
    end

    iris.pushBufferIntoIRIS = function()
        iris.logger.Trace().Str("_name", "pushBufferIntoIRIS").Send()

        return iris._pushInventoryIntoIRIS(iris.configuration.turtleInventory)
    end

    iris._pullItemIntoInventory = function(peripheralName, name, count)
        iris.logger.Trace().Str("_name", "_pullItemIntoInventory").Str("peripheralName", peripheralName).Str("name", name)
            .Str("count", count).Send()

        local inventory = peripheral.wrap(peripheralName)
        if inventory == nil then return 0, errors.ErrCouldNotWrapPeripheral end

        local start = os.epoch("utc")
        iris.logger.Debug().Str("name", name).Str("count", count).Str("peripheral", peripheralName).Msg("Pulling from IRIS into inventory")

        local locations, err = iris.locate(name)
        if err ~= nil then
            return 0, err
        end

        local itemsTransferred = 0

        for _, location in pairs(locations) do
            if count > 0 then
                local transferred = iris._push(location.peripheral, location.slot, peripheralName, nil,
                    math.min(count, location.max - location.count))
                count = count - transferred
                itemsTransferred = itemsTransferred + transferred
            end
        end

        iris.logger.Debug().Dur("duration", start).Str("name", name).Str("count", count).Str("peripheral", peripheralName)
            .Str("transferred", itemsTransferred).Msg("Moved item from IRIS into inventory")

        if count > 0 then
            return itemsTransferred, errors.ErrIRISMissingItems
        end

        return itemsTransferred, nil
    end

    iris._pushInventoryIntoIRIS = function(peripheralName)
        iris.logger.Trace().Str("_name", "_pushInventoryIntoIRIS").Str("peripheralName", peripheralName).Send()

        local inventory = peripheral.wrap(peripheralName)
        if inventory == nil then return 0, errors.ErrCouldNotWrapPeripheral end

        local start = os.epoch("utc")
        iris.logger.Debug().Str("peripheral", peripheralName).Msg("Pushing inventory into IRIS")

        local inventory, err = scanner.ScanInventory(iris, peripheralName)
        if err ~= nil then
            return 0, err
        end

        local itemsTransferred = 0
        local missingSpace = false

        assert(type(inventory) == "table")
        assert(type(inventory.items) == "table")

        for slot, item in pairs(inventory.items) do
            local maxStack = 1
            local atlasEntry = iris.fetchFromAtlas(item.name)
            if atlasEntry then
                maxStack = atlasEntry.max
            end

            local result = iris.findSpot(item.name, item.count, maxStack,
                {
                    peripheralName,
                    iris.configuration.inputInventory,
                    iris.configuration.outputInventory,
                    iris.configuration.turtleInventory,
                    turtleInventoryRelative,
                })
            if result.hasSpace then
                for _, candidate in pairs(result.candidates) do
                    if item.count > 0 then
                        local transferred = iris._push(candidate.peripheral, candidate.slot, peripheralName,
                            tonumber(slot),
                            math.min(item.count, candidate.max - candidate.count))
                        item.count = item.count - transferred
                        itemsTransferred = itemsTransferred + transferred
                    end
                end

                for _, emptySlot in pairs(result.emptySlots) do
                    if item.count > 0 then
                        local transferred = iris._push(emptySlot.peripheral, emptySlot.slot, peripheralName,
                            tonumber(slot),
                            math.min(item.count, maxStack))
                        item.count = item.count - transferred
                        itemsTransferred = itemsTransferred + transferred
                    end
                end
            else
                missingSpace = true
            end
        end

        iris.logger.Debug().Dur("duration", start).Str("peripheral", peripheralName).Str("transferred", itemsTransferred)
            .Msg("Moved inventory into IRIS")

        if missingSpace then
            return itemsTransferred, errors.ErrIRISMissingSpace
        end

        return itemsTransferred, nil
    end

    iris._push = function(fromInventory, fromSlot, toInventory, toSlot, count)
        iris.logger.Trace().Str("_name", "_push").Str("fromInventory", fromInventory).Str("fromSlot", fromSlot).Str("toInventory"
            , toInventory).Str("toSlot"
            , toSlot).Str("count", count).Send()

        local inventory = peripheral.wrap(fromInventory)
        if inventory == nil then return 0, errors.ErrCouldNotWrapPeripheral end

        local transferred = inventory.pushItems(toInventory, fromSlot, count, toSlot)

        iris._markAddSlot(toInventory, fromSlot, count)
        iris._markRemoveSlot(fromInventory, toSlot, count)

        return transferred, nil
    end

    iris._markAddItem = function(inventoryName, name, count)
        -- TODO
    end

    iris._markRemoveItem = function(inventoryName, name, count)
        -- TODO
    end

    iris._markAddSlot = function(inventoryName, slot, count)
        iris.logger.Trace().Str("_name", "_markAddSlot").Str("inventory", inventoryName).Str("slot", slot).Str("count",
            count)
            .Send()
        iris.logger.Debug().Str("inventory", inventoryName).Str("slot", slot).Str("count", count).Msg("Updating data to add items to slot")

        -- ScanInventory if not stored
        if iris.irisData.inventories[inventoryName] == nil then
            local inventory = scanner.ScanInventory(iris, inventoryName)

            iris.irisData.inventories[inventoryName] = inventory
            iris.isIRISDataDirty = true
        else
            -- ScanInventory if we don't store an item here or what we store does not make sense.
            if iris.irisData.inventories[inventoryName].items[tostring(slot)] ==
                nil or
                iris.irisData.inventories[inventoryName].items[tostring(slot)]
                .count == nil then
                local inventory = scanner.ScanInventory(iris, inventoryName)

                iris.irisData.inventories[inventoryName] = inventory
                iris.isIRISDataDirty = true
            else
                iris.irisData.inventories[inventoryName].items[tostring(slot)]
                    .count = iris.irisData.inventories[inventoryName].items[tostring(
                    slot)].count + count
                iris.isIRISDataDirty = true
            end
        end
    end

    iris._markRemoveSlot = function(inventoryName, slot, count)
        iris.logger.Trace().Str("_name", "_markRemoveSlot").Str("inventoryName", inventoryName).Str("slot", slot).Str("count"
            , count).Send()
        iris.logger.Debug().Str("inventoryName", inventoryName).Str("slot", slot).Str("count", count).Msg("Updating data to remove items from slot")

        -- ScanInventory if not stored
        if iris.irisData.inventories[inventoryName] == nil then
            local inventory = scanner.ScanInventory(iris, inventoryName)

            iris.irisData.inventories[inventoryName] = inventory
            iris.isIRISDataDirty = true
        else
            -- ScanInventory if we don't store an item here or what we store does not make sense.
            if iris.irisData.inventories[inventoryName].items[tostring(slot)] ==
                nil or
                iris.irisData.inventories[inventoryName].items[tostring(slot)]
                .count == nil then
                local inventory = scanner.ScanInventory(iris, inventoryName)

                iris.irisData.inventories[inventoryName] = inventory
                iris.isIRISDataDirty = true
            else
                iris.irisData.inventories[inventoryName].items[tostring(slot)]
                    .count = iris.irisData.inventories[inventoryName].items[tostring(
                    slot)].count - count

                -- If count is 0, remove slot
                if iris.irisData.inventories[inventoryName].items[tostring(slot)].count == 0 then
                    iris.irisData.inventories[inventoryName].items[tostring(slot)] = nil
                end

                iris.isIRISDataDirty = true
            end
        end
    end

    return iris
end

return { NewIRIS = NewIRIS }
