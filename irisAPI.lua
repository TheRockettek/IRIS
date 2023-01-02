local errors = require "core.errors"
local logging = require "libs.logging"
local irisSerialization = require "core.iris_serialization"
local scanner = require "core.scanner"
local events = require "core.events"

local VERSION = "0.0.1"

local configurationPath = "iris.config"

local defaultConfiguration = {
    irisFileLocation = "iris.data",

    scanOnStart = true,
    scanDelay = 60000 -- Time in milliseconds to wait between an inventory scan. This is only used during startup.
}

local function check(func, index, expectedType, value)
    if type(value) ~= expectedType then
        return error(('%s: bad argument #%d (expected %s, got %s)'):format(func, index, expectedType, expectedType(value))
            , 3)
    end
end

local function tableContainsValue(table, value)
    for _, k in pairs(table) do if k == value then return true end end

    return false
end

local function NewIRIS(logger)
    local iris = {
        internalInventory = "iris_internal:turtle",

        version = VERSION,
        logger = logger or logging.NewLogger(nil, nil),

        isIRISDataLoaded = false,
        isIRISDataDirty = false,
        irisData = { iris = { lastSca_transferItemsnnedAt = 0 }, inventories = {} },

        configuration = defaultConfiguration
    }

    -- provide dummy storage peripheral
    iris.turtle = {
        _getTurtlePeripheral = function()
            for _, k in pairs(redstone.getSides()) do
                if peripheral.getType(k) == "modem" then
                    return peripheral.wrap(k).getNameLocal()
                end
            end

            return nil
        end,

        size = function()
            return 16
        end,

        getItemDetail = function(slot)
            return turtle.getItemDetail(slot, true)
        end,

        getItemLimit = function(slot)
            return turtle.getItemCount(slot) + turtle.getItemSpace(slot)
        end,
    }

    iris.turtle.list = function()
        local items = {}
        for i = 1, iris.turtle.size(), 1 do
            local item = turtle.getItemDetail(i)
            if item then
                table.insert(items, item)
            end
        end
        return items
    end

    iris.turtle.pushItems = function(toName, fromSlot, limit, toSlot)
        local toPeripheral = peripheral.wrap(toName)
        check("pushItems", 1, "table", toPeripheral)

        return toPeripheral.pullItems(iris.turtle._getTurtlePeripheral(), fromSlot, limit, toSlot)
    end

    iris.turtle.pullItems = function(fromName, fromSlot, limit, toSlot)
        local fromPeripheral = peripheral.wrap(fromName)
        check("pullItems", 1, "table", fromPeripheral)

        return fromPeripheral.pushItems(iris.turtle._getTurtlePeripheral(), fromSlot, limit, toSlot)
    end

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

        -- Load iris data
        iris.loadIRISData()

        if iris.configuration.scanOnStart then iris.fullScan() end

        iris.logger.silent = true

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

        local jsonDecode = textutils.unserializeJSON(contents)
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

        return ierr
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

        iris.isIRISDataDirty = false

        iris.logger.Info().Dur("duration", start).Msg("Saved IRIS data")

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

        os.queueEvent(events.EventIrisFullScan)

        return true
    end

    iris.calculateUsage = function()
        iris.logger.Trace().Str("_name", "calculateUsage").Send()

        local itemSlotsUsed = 0
        local itemSlotsTotal = 0
        local itemCount = 0
        local itemMaxCount = 0

        for _, inventoriesData in pairs(iris.irisData.inventories) do
            itemSlotsTotal = itemSlotsTotal + inventoriesData.totalSlots
            itemSlotsUsed = itemSlotsUsed + inventoriesData.usedSlots
            itemCount = itemCount + inventoriesData.totalItems
            itemMaxCount = itemCount + inventoriesData.itemMaxCount
        end

        return itemSlotsUsed, itemSlotsTotal, itemCount, itemMaxCount
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
    iris.locate = function(name, nbt)
        iris.logger.Trace().Str("_name", "locate").Str("name", name).Send()

        local locations = {}

        for inventoryName, inventoryData in pairs(iris.irisData.inventories) do
            for slotId, item in pairs(inventoryData.items) do
                if item.name == name and ((nbt == "" or nbt == nil) or item.nbt == nbt) then
                    table.insert(locations, {
                        peripheral = inventoryName,
                        slot = tonumber(slotId),
                        count = item.count,

                        display = item.display or item.name,
                        max = item.max,
                        nbt = item.nbt,
                        tags = item.tags,
                    })
                end
            end
        end

        return locations
    end

    -- Find partial stacks of empty items.
    -- Returns list of partial stacks and empty slot candidate.
    -- Passing total store will make it only return slots that are needed.
    iris.findSpot = function(name, nbt, totalStore, maxStack, ignoreList)
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

        local slots = iris.locate(name, nbt)

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
                if not tableContainsValue(ignoreList, value.peripheral) then
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
            if maxSpacesNeeded > 0 then
                if not tableContainsValue(ignoreList, inventoryName) then
                    if inventoryData.usedSlots < inventoryData.totalSlots then
                        for slotId = 1, inventoryData.totalSlots, 1 do
                            if inventoryData.items[tostring(slotId)] == nil then
                                table.insert(output.candidates, {
                                    peripheral = inventoryName,
                                    slot = tonumber(slotId)
                                })

                                maxSpacesNeeded = maxSpacesNeeded - 1
                                output.hasSpace = true

                                if maxSpacesNeeded <= 0 then break end
                            end
                        end

                        if maxSpacesNeeded <= 0 then break end
                    end
                end
            end
        end

        -- If we have a number greater than 0, we do not have enough spaces available.
        output.hasSpace = maxSpacesNeeded == 0
        output.spacesMissing = maxSpacesNeeded

        return output
    end

    -- Returns all items based on locations.
    iris.flatten = function()
        iris.logger.Trace().Str("_name", "flatten").Send()

        local items = {}

        for inventoryName, inventoryData in pairs(iris.irisData.inventories) do
            for slotId, item in pairs(inventoryData.items) do
                local itemName = iris._getItemName(item)

                if items[itemName] == nil then
                    items[itemName] = {}
                end

                table.insert(items[itemName], {
                    peripheral = inventoryName,
                    slot = tonumber(slotId),
                    count = item.count,

                    display = item.display or item.name,
                    max = item.max,
                    nbt = item.nbt,
                    tags = item.tags,
                })
            end
        end

        return items
    end

    -- Returns id for item.
    iris._getItemName = function(item)
        if item.nbt then
            return item.name .. "@" .. item.nbt
        end

        return item.name
    end

    -- IRIS operations

    iris.pullItemFromIRIS = function(name, nbt, count)
        iris.logger.Trace().Str("_name", "pullItemFromIRIS").Str("name", name).Str("count", count).Send()

        return iris._pullItemIntoInventory(iris.internalInventory, name, nbt, count)
    end

    iris.pushInputIntoIRIS = function()
        iris.logger.Trace().Str("_name", "pushInputIntoIRIS").Send()

        return iris._pushInventoryIntoIRIS(iris.internalInventory)
    end

    iris.pullItemIntoBuffer = function(name, nbt, count)
        iris.logger.Trace().Str("_name", "pullItemIntoBuffer").Str("name", name).Str("count", count).Send()

        return iris._pullItemIntoInventory(iris.internalInventory, name, nbt, count)
    end

    iris.pushBufferIntoIRIS = function()
        iris.logger.Trace().Str("_name", "pushBufferIntoIRIS").Send()

        return iris._pushInventoryIntoIRIS(iris.internalInventory)
    end

    iris._pullItemIntoInventory = function(peripheralName, name, nbt, count)
        iris.logger.Trace().Str("_name", "_pullItemIntoInventory").Str("peripheralName", peripheralName).Str("name", name)
            .Str("count", count).Send()

        if peripheralName ~= iris.internalInventory then
            local inventory = peripheral.wrap(peripheralName)
            if inventory == nil then return 0, errors.ErrCouldNotWrapPeripheral end
        end

        local start = os.epoch("utc")
        iris.logger.Debug().Str("name", name).Str("count", count).Str("peripheral", peripheralName).Msg("Pulling from IRIS into inventory")

        local locations, err = iris.locate(name, nbt)
        if err ~= nil then
            return 0, err
        end

        local itemsTransferred = 0

        if count > 0 then
            for _, location in pairs(locations) do
                local transferred = iris._push(location.peripheral, location.slot, peripheralName, nil,
                    math.min(count, location.count))
                count = count - transferred
                itemsTransferred = itemsTransferred + transferred

                if count <= 0 then break end
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

        local start = os.epoch("utc")

        local inventoryPeripheral
        if peripheralName == iris.internalInventory then
            inventoryPeripheral = iris.turtle
        else
            inventoryPeripheral = peripheral.wrap(peripheralName)
            if inventoryPeripheral == nil then return 0, errors.ErrCouldNotWrapPeripheral end
        end

        iris.logger.Debug().Str("peripheral", peripheralName).Msg("Pushing inventory into IRIS")

        local inventory, err = scanner.ScanInventory(iris, peripheralName, inventoryPeripheral)
        if err ~= nil then
            return 0, err
        end

        assert(type(inventory) == "table")
        assert(type(inventory.items) == "table")

        local itemsTransferred, missingSpace = iris._transferItems(peripheralName, inventory.items)

        iris.logger.Debug().Dur("duration", start).Str("peripheral", peripheralName).Str("transferred", itemsTransferred)
            .Msg("Moved inventory into IRIS")

        if missingSpace then
            return itemsTransferred, errors.ErrIRISMissingSpace
        end

        return itemsTransferred, nil
    end

    iris._transferItems = function(peripheralName, detailedItems)
        iris.logger.Trace().Str("_name", "_transferItems").Str("peripheralName", peripheralName).Json("items",
            detailedItems).Send()

        local itemsTransferred = 0
        local missingSpace = false

        local start = os.epoch("utc")

        assert(type(peripheralName) == "string")
        assert(type(detailedItems) == "table")

        for slot, item in pairs(detailedItems) do
            local result = iris.findSpot(item.name, item.nbt, item.count, item.max,
                {
                    peripheralName,
                    table.unpack(redstone.getSides())
                })
            if result.hasSpace then
                if item.count > 0 then
                    for _, candidate in pairs(result.candidates) do
                        local transferred = iris._push(peripheralName, tonumber(slot), candidate.peripheral,
                            candidate.slot,
                            math.min(item.count, candidate.max - candidate.count))
                        item.count = item.count - transferred
                        itemsTransferred = itemsTransferred + transferred

                        if item.count <= 0 then break end
                    end
                end

                if item.count > 0 then
                    for _, candidate in pairs(result.emptySlots) do
                        local transferred = iris._push(peripheralName, tonumber(slot), candidate.peripheral,
                            candidate.slot,
                            math.min(item.count, item.max))
                        item.count = item.count - transferred
                        itemsTransferred = itemsTransferred + transferred

                        if item.count <= 0 then break end
                    end
                end
            else
                missingSpace = true
            end
        end

        iris.logger.Debug().Dur("duration", start).Str("peripheral", peripheralName).Str("transferred", itemsTransferred)
            .Msg("Transferred items")

        return itemsTransferred, missingSpace
    end

    iris._push = function(fromInventory, fromSlot, toInventory, toSlot, count)
        iris.logger.Trace().Str("_name", "_push").Str("fromInventory", fromInventory).Str("fromSlot", fromSlot).Str("toInventory"
            , toInventory).Str("toSlot"
            , toSlot).Str("count", count).Msg("[TINTER]")

        local inventoryPeripheral
        local transferred

        if fromInventory == iris.internalInventory then
            inventoryPeripheral = iris.turtle

            transferred = inventoryPeripheral.pushItems(toInventory, fromSlot, count, toSlot)
            if transferred == 0 then
                iris.logger.Warn().Str("fromInventory", fromInventory).Str("fromSlot", fromSlot).Str("toInventory",
                    toInventory).Str("toSlot", toSlot).Str("count", count).Msg("Failed to push items")
            end
        elseif toInventory == iris.internalInventory then
            inventoryPeripheral = iris.turtle

            transferred = inventoryPeripheral.pullItems(fromInventory, fromSlot, count, toSlot)
            if transferred == 0 then
                iris.logger.Warn().Str("fromInventory", fromInventory).Str("fromSlot", fromSlot).Str("toInventory",
                    toInventory).Str("toSlot", toSlot).Str("count", count).Msg("Failed to pull items (as turtle)")
            end
        else
            inventoryPeripheral = peripheral.wrap(fromInventory)
            if inventoryPeripheral == nil then return 0, errors.ErrCouldNotWrapPeripheral end

            transferred = inventoryPeripheral.pushItems(toInventory, fromSlot, count, toSlot)
            if transferred == 0 then
                iris.logger.Warn().Str("fromInventory", fromInventory).Str("fromSlot", fromSlot).Str("toInventory",
                    toInventory).Str("toSlot", toSlot).Str("count", count).Msg("Failed to push items")
            end
        end

        iris._markAddSlot(toInventory, toSlot, count)
        iris._markRemoveSlot(fromInventory, fromSlot, count)

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
            iris.logger.Debug().Str("inventoryName", inventoryName).Str("Inventory is not stored, scanning")

            local inventoryPeripheral = peripheral.wrap(inventoryName)
            if inventoryPeripheral ~= nil then
                local inventory = scanner.ScanInventory(iris, inventoryName, inventoryPeripheral)

                iris.irisData.inventories[inventoryName] = inventory
                iris.isIRISDataDirty = true
            end
        else
            -- ScanInventory if we don't store an item here or what we store does not make sense.
            if iris.irisData.inventories[inventoryName].items[tostring(slot)] ==
                nil or
                iris.irisData.inventories[inventoryName].items[tostring(slot)]
                .count == nil then
                iris.logger.Debug().Str("inventoryName", inventoryName).Str("slot", slot).Str("Item was not stored in our data, scanning chest")

                local inventoryPeripheral = peripheral.wrap(inventoryName)
                if inventoryPeripheral ~= nil then
                    local inventory = scanner.ScanInventory(iris, inventoryName, inventoryPeripheral)

                    iris.irisData.inventories[inventoryName] = inventory
                    iris.isIRISDataDirty = true
                end
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
            iris.logger.Debug().Str("inventoryName", inventoryName).Str("Inventory is not stored, scanning")

            local inventoryPeripheral = peripheral.wrap(inventoryName)
            if inventoryPeripheral ~= nil then
                local inventory = scanner.ScanInventory(iris, inventoryName, inventoryPeripheral)

                iris.irisData.inventories[inventoryName] = inventory
                iris.isIRISDataDirty = true
            end
        else
            -- ScanInventory if we don't store an item here or what we store does not make sense.
            if iris.irisData.inventories[inventoryName].items[tostring(slot)] ==
                nil or
                iris.irisData.inventories[inventoryName].items[tostring(slot)]
                .count == nil then
                iris.logger.Debug().Str("inventoryName", inventoryName).Str("slot", slot).Str("Item was not stored in our data, scanning chest")

                local inventoryPeripheral = peripheral.wrap(inventoryName)
                if inventoryPeripheral ~= nil then
                    local inventory = scanner.ScanInventory(iris, inventoryName, inventoryPeripheral)

                    iris.irisData.inventories[inventoryName] = inventory
                    iris.isIRISDataDirty = true
                end
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
