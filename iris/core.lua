local turtle      = require "turtle"
local utils       = require "utils"
local inventory   = require "inventory"
local irisPlugins = require "irisplugins"

local VERSION = "1.0.0"

-- Atlas specific config
local atlasFileLocation = "iris.atlas" -- Location of atlas on disk
local atlasTTL = 86400000 -- Time (in milliseconds) that an item will persist on the atlas. This defaults to a day.

local function NewIRIS(logger)
    utils.expectTable("NewIRIS", "logger", logger, "logger:logger")

    local this = {
        _type = "iris:controller",

        turtle = turtle.NewTurtle(),
        logger = logger,

        inventories = {},
        pluginManager = nil,

        atlas = {},
        isAtlasDirty = false,

        items = {},
        emptySlots = {},
        itemSummary = {},

        usedSlotCount = 0,
        emptySlotCount = 0,
        totalItemCount = 0,
        itemMaxCount = 0,
    }

    this.pluginManager = irisPlugins.IRISPluginManager(this)

    -- Plugin manager code is located at bottom, to ensure IRIS functions are defined.

    this.start = function()
        this.logger.Info().Str("VERSION", VERSION).Msg("IRIS is starting...")

        this.loadAtlas(atlasFileLocation)
        this.scanInventories()
        this.saveAtlas(atlasFileLocation)

        -- TODO background task to auto save. Maybe plugin?

        this.logger.Info().Msg("IRIS has started")
        this.pluginManager.OnIRISStart()
    end

    this.close = function()
        this.logger.Info().Msg("IRIS is unloading")
        this.pluginManager.OnIRISUnload()
    end

    this._formatIgnoreList = function(ignoreList)
        if type(ignoreList) == "table" then
            return ignoreList
        elseif type(ignoreList) == "string" then
            return { ignoreList }
        elseif type(ignoreList) == "nil" then
            return {}
        else
            error(("Unexpected type for ignoreList. (expected string, table or nil, got %s)"):format(type(ignoreList)))
        end
    end

    this._cleanAtlas = function()
        local now = os.epoch("utc")
        local func = this.logger.FunctionStart("_clenaAtlas")

        local cleaned = 0

        for i, k in pairs(this.atlas) do
            if k.lastSeen and (now - k.lastSeen) > atlasTTL then
                this.atlas[i] = nil
                cleaned = cleaned + 1
            end
        end

        func.FunctionEnd("cleaned", cleaned)
    end

    this.loadAtlas = function(fileLocation)
        local func = this.logger.FunctionStart("loadAtlas", "fileLocation", fileLocation)

        local err

        if fs.exists(fileLocation) then
            local file = fs.open(fileLocation, "rb")
            local content = file.readAll()
            local dSuccess, dResult = pcall(textutils.unserialize, content)
            if dSuccess then
                for atlasKey, atlasEntry in pairs(dResult) do
                    local eSuccess, eResult = pcall(utils.expectTable, "loadAtlas", "atlas_entry", atlasEntry,
                        "iris:atlas_entry")
                    if eSuccess then
                        this.atlas[atlasKey] = atlasEntry
                    else
                        this.logger.Warn().Err(eResult).Str("atlasKey", atlasKey).Str("entryType", atlasEntry._type).Msg("Atlas value was unexpected type. Ignoring")
                    end
                end
            else
                this.logger.Error().Err(dResult).Msg("Failed to deserialize atlas file")
                err = dResult
            end
        else
            this.logger.Warn().Msg("Atlas could not be found. This may just be a fresh install.")
            err = "File does not exist"
        end

        func.FunctionEnd("err", err)

        return err
    end

    this.saveAtlas = function(fileLocation)
        local func = this.logger.FunctionStart("saveAtlas", "fileLocation", fileLocation)

        local err
        if this.isAtlasDirty then
            this._cleanAtlas()

            local success, result = pcall(textutils.serialize, this.atlas, { compact = true, allow_repetitions = true })
            if success then
                local file = fs.open(fileLocation, "wb")
                success, result = pcall(file.write, result)
                if success then
                    file.close()
                    this.isAtlasDirty = false
                else
                    this.logger.Error().Err(result).Msg("Failed to write to file")
                    err = result
                end
            else
                this.logger.Error().Err(result).Msg("Failed to serialize atlas file")
                err = result
            end
        else
            this.logger.Info().Msg("Skipping save atlas as the data has not changed since the last save")
        end

        func.FunctionEnd("error", err)

        return err
    end

    this.scanInventories = function()
        local func = this.logger.FunctionStart("scanInventories")

        local inventoryCount = this._scanAllInventories()

        func.FunctionEnd("inventoryCount", inventoryCount)

        return inventoryCount
    end

    this.findItem = function(inventoryItemHash, count, ignoreList)
        ignoreList = this._formatIgnoreList(ignoreList)

        local func = this.logger.FunctionStart("findItem", "inventoryItemHash", inventoryItemHash, "count", count,
            "ignoreList", ignoreList)

        local flatPack = utils.flattenValuesForSearch(ignoreList)
        local itemsRemaining = count

        local candidates = {}

        local items = this.items[inventoryItemHash]
        if items then
            for _, inventoryItem in pairs(items) do
                if not flatPack.find(inventoryItem._inventoryName) then
                    table.insert(candidates, inventoryItem)
                    itemsRemaining = itemsRemaining - inventoryItem.count
                    if itemsRemaining <= 0 then
                        break
                    end
                end
            end
        end

        func.FunctionEnd("candidates", candidates, "missingItems", itemsRemaining)

        return candidates, math.max(0, itemsRemaining)
    end

    this.findSpot = function(inventoryItemHash, count, maxCount, ignoreList)
        ignoreList = this._formatIgnoreList(ignoreList)

        local func = this.logger.FunctionStart("findSpot", "inventoryItemHash", inventoryItemHash, "count", count,
            "maxCount", maxCount, "ignoreList", ignoreList)

        local flatPack = utils.flattenValuesForSearch(ignoreList)
        local itemsRemaining = count

        local candidates = {}
        local willOverflow = false
        local emptySpaces = {}
        local missingSpaces = 0

        local items = this.items[inventoryItemHash]
        if items then
            for _, inventoryItem in pairs(items) do
                if not flatPack.find(inventoryItem._inventoryName) then
                    table.insert(candidates, inventoryItem)

                    local atlasEntry = this.getFromAtlas(inventoryItem)
                    itemsRemaining = itemsRemaining - (atlasEntry.maxCount - inventoryItem.count)
                    if itemsRemaining <= 0 then
                        break
                    end
                end
            end
        end

        -- I need to figure out best way of doing max count.
        -- To be honest, it should be stored in the this.items,
        -- I could also just look at any candidates, but if both
        -- of those are empty, i can't really do much.
        -- To make my life easier, i'll always just query max count
        -- on the turtle or whatever is inputting so i do not need
        -- to worry if its passed or not and make it over complicated.

        -- If we have filled all existing stacks, find empty space to use.
        if itemsRemaining > 0 then
            emptySpaces, missingSpaces = this.findEmptySpace(math.ceil(itemsRemaining / maxCount), ignoreList)
            willOverflow = true
        end

        func.FunctionEnd("candidates", candidates, "willOverflow", willOverflow, "emptySpaces", emptySpaces,
            "missingSpaces", missingSpaces)

        return candidates, willOverflow, emptySpaces, missingSpaces
    end

    this.findEmptySpace = function(maxSpacesNeeded, ignoreList)
        ignoreList = this._formatIgnoreList(ignoreList)

        local func = this.logger.FunctionStart("findEmptySpace", "maxSpacesNeeded", maxSpacesNeeded, "ignoreList",
            ignoreList)

        local flatPack = utils.flattenValuesForSearch(ignoreList)
        local spacesRemaining = maxSpacesNeeded
        local candidates = {}

        for inventorySlotKey, _ in pairs(this.emptySlots) do
            local inventoryName, slot = inventory.KeyToInventorySlot(inventorySlotKey)
            if not flatPack.find(inventoryName) then
                table.insert(candidates, { inventoryName = inventoryName, slot = slot })
                spacesRemaining = spacesRemaining - 1
                if spacesRemaining <= 0 then
                    return candidates, spacesRemaining
                end
            end
        end

        func.FunctionEnd("candidates", candidates, "spacesRemaining", spacesRemaining)

        return candidates, spacesRemaining
    end

    this.push = function(fromInventory, fromSlot, toInventory, toSlot, count)
        local func = this.logger.FunctionStart("push", "fromInventory", fromInventory, "fromSlot", fromSlot,
            "toInventory", toInventory, "toSlot", toSlot, "count", count)

        local inventoryItem
        local localTurtleName = this.turtle.getNameLocal()

        if fromInventory == this.turtle._type then fromInventory = localTurtleName end
        if toInventory == this.turtle._type then toInventory = localTurtleName end

        if fromInventory == localTurtleName then
            inventoryItem = inventory.InventoryItem(localTurtleName, fromSlot, this.turtle.getItemDetail(fromSlot))
        else
            local inventoryData = this.inventories[fromInventory]
            assert(inventoryData)
            inventoryItem = utils.deepcopy(inventoryData.slots[tostring(fromSlot)])
        end

        assert(inventoryItem)

        local itemsTransferred

        if fromInventory == localTurtleName then
            itemsTransferred = this.turtle.pushItems(toInventory, fromSlot, count, toSlot)
        elseif toInventory == localTurtleName then
            itemsTransferred = this.turtle.pullItems(fromInventory, fromSlot, count, toSlot)
        else
            itemsTransferred = peripheral.call(fromInventory, "pushItems", toInventory, fromSlot, count, toSlot)
        end

        assert(type(itemsTransferred) == "number")

        inventoryItem.count = inventoryItem.count - itemsTransferred

        local resultInventoryItem

        -- TODO: Figure out optimal way of doing this.
        if toInventory == localTurtleName then
            resultInventoryItem = inventory.InventoryItem(toInventory, toSlot, this.turtle.getItemDetail(toSlot))
        else
            resultInventoryItem = inventory.InventoryItem(toInventory, toSlot,
                peripheral.call(toInventory, "getItemDetail", toSlot))
        end

        local atlasEntry = this.getFromAtlas(resultInventoryItem)

        this._setInventoryItem(toInventory, toSlot, resultInventoryItem, atlasEntry)
        this._setInventoryItem(fromInventory, fromSlot, inventoryItem, atlasEntry)

        func.FunctionEnd("itemsTransferred", itemsTransferred)

        return itemsTransferred
    end

    this._registerInventory = function(inventoryName, inventorySize)
        local func = this.logger.FunctionStart("_registerInventory", "inventoryName", inventoryName, "inventorySize",
            inventorySize)

        utils.expect("_registerInventory", "inventoryName", inventoryName, "string")
        utils.expect("_registerInventory", "inventorySize", inventorySize, "number")

        local irisInventory = this.inventories[inventoryName]
        if not irisInventory then
            this.inventories[inventoryName] = inventory.Inventory(inventoryName, inventorySize)
            for slotNumber = 1, inventorySize, 1 do
                this.emptySlots[inventory.InventorySlotToKey(inventoryName, slotNumber)] = true
                this.emptySlotCount = this.emptySlotCount + 1
                this.itemMaxCount = this.itemMaxCount + inventory.DefaultInventoryStackSize
            end

            this.logger.Debug().Str("inventoryName", inventoryName).Msg("Registering inventory")
        end

        func.FunctionEnd()
    end

    this.getFromAtlas = function(inventoryItem)
        local func = this.logger.FunctionStart("getFromAtlas", "inventoryItem", inventoryItem)

        local atlasEntry = this.atlas[inventoryItem.hash()]
        if not atlasEntry then
            local result = this.ensureAtlas(inventoryItem)
            if result then
                atlasEntry = result
            else
                this.logger.Warn().Str("inventoryName", inventoryItem._inventoryName).Str("slotNumber",
                    inventoryItem._slot).Str("hash", inventoryItem.hash()).Msg("Could not get item from atlas or ensure")
            end
        end

        atlasEntry.lastSeen = os.epoch("utc")
        this.isAtlasDirty = true

        func.FunctionEnd("atlasEntry", atlasEntry)

        return atlasEntry
    end

    this.ensureAtlas = function(inventoryItem)
        local func = this.logger.FunctionStart("ensureAtlas", "inventoryItem", inventoryItem)

        utils.expectTable("ensureAtlas", "inventoryItem", inventoryItem, "iris:inventory_item")

        local inventoryItemHash = inventoryItem.hash()

        local atlasEntry = this.atlas[inventoryItemHash]
        if not atlasEntry then
            local inventoryName = inventoryItem._inventoryName
            local slotNumber = inventoryItem._slot

            assert(inventoryName)
            assert(slotNumber)

            local item
            if inventoryName == this.turtle._getNameLocal() then
                item = this.turtle.getItemDetail(slotNumber)
            else
                item = peripheral.call(inventoryName, "getItemDetail", slotNumber)
            end

            if item then
                atlasEntry = AtlasEntry(item)
                this.atlas[inventoryItemHash] = atlasEntry
            else
                this.logger.Warn().Str("inventoryName", inventoryName).Str("slotNumber", slotNumber).Str("hash",
                    inventoryItemHash).Msg("Could not locate item detail in slot to add to atlas")
            end
        end

        func.FunctionEnd("atlasEntry", atlasEntry)

        return atlasEntry
    end

    this._setInventoryItem = function(inventoryName, slot, inventoryItem, atlasEntry)
        local func = this.logger.FunctionStart("_setInventoryItem", "inventoryName", inventoryName, "slot", slot,
            "inventoryItem", inventoryItem)

        utils.expect("_setInventoryItem", "inventoryName", inventoryName, "string")
        utils.expect("_setInventoryItem", "slot", slot, "number")
        if inventoryItem then
            utils.expectTable("_setInventoryItem", "inventoryItem", inventoryItem, "iris:inventory_item")
            this.ensureAtlas(inventoryItem)
        end

        local irisInventory = this.inventories[inventoryName]
        assert(irisInventory)

        irisInventory.SetInventoryItem(slot, inventoryItem, atlasEntry)
        if inventoryItem then
            this._setInventoryItemMaster(inventoryName, slot, inventoryItem, atlasEntry)
        end

        func.FunctionEnd()
    end

    this._setInventoryItemMaster = function(inventoryName, slot, inventoryItem, atlasEntry)
        local func = this.logger.FunctionStart("_setInventoryItemMaster", "inventoryName", inventoryName, "slot", slot,
            "inventoryItem", inventoryItem)

        utils.expect("_setInventoryItemMaster", "inventoryName", inventoryName, "string")
        utils.expect("_setInventoryItemMaster", "slot", slot, "number")
        utils.expectTable("_setInventoryItemMaster", "inventoryItem", inventoryItem, "iris:inventory_item")

        local inventoryItemHash = inventoryItem.inventoryHash()
        local itemHash = inventoryItem.hash()
        local isTurtleInventory = inventoryName == this.turtle._getNameLocal()

        local irisItems = this.items[itemHash]
        if irisItems == nil then
            this.items[itemHash] = {}
            irisItems = this.items[itemHash]
        end

        assert(irisItems)

        local currentSlot = irisItems[inventoryItemHash]
        if inventoryItem.count == 0 then
            if currentSlot ~= nil then
                irisItems[inventoryItemHash] = nil

                if not isTurtleInventory then
                    local itemSummary = this.itemSummary[itemHash]
                    if itemSummary == nil then
                        itemSummary = utils.deepcopy(inventoryItem)
                    else
                        itemSummary.count = itemSummary.count - currentSlot.count
                    end
                    this.itemSummary[itemHash] = itemSummary
                end

                this.emptySlots[inventory.InventorySlotToKey(inventoryName, slot)] = true

                this.usedSlotCount = this.usedSlotCount - 1
                this.emptySlotCount = this.emptySlotCount + 1
                this.totalItemCount = this.totalItemCount - currentSlot.count
                this.itemMaxCount = this.itemMaxCount + inventory.DefaultInventoryStackSize
            else
                this.logger.Warn().Str("inventoryName", inventoryName).Str("slot", slot).Object("inventoryItem",
                    inventoryItem.Table()).Msg("Attempt to set an empty item which is not already in IRIS")
            end
        else
            if currentSlot ~= nil then
                assert(currentSlot.equals(inventoryItem),
                    ("Unexpected slot item. Current item in slot %d is %s, expected %s"):format(slot, currentSlot.hash()
                        , inventoryItem.hash()))

                local countChange = inventoryItem.count - currentSlot.count
                if countChange ~= 0 then
                    irisItems[inventoryItemHash] = inventoryItem

                    if not isTurtleInventory then
                        local itemSummary = this.itemSummary[itemHash]
                        if itemSummary == nil then
                            itemSummary = utils.deepcopy(inventoryItem)
                        else
                            itemSummary.count = itemSummary.count + countChange
                        end

                        this.itemSummary[itemHash] = itemSummary
                    end

                    this.totalItemCount = this.totalItemCount + countChange
                else
                    this.logger.Warn().Str("inventoryName", inventoryName).Str("slot", slot).Object("inventoryItem",
                        inventoryItem.Table()).Object("currentSlot", currentSlot.Table()).Msg("Attempt to set an item which is already stored")
                end
            else
                irisItems[inventoryItemHash] = inventoryItem

                if not isTurtleInventory then
                    local itemSummary = this.itemSummary[itemHash]
                    if itemSummary == nil then
                        itemSummary = utils.deepcopy(inventoryItem)
                    else
                        itemSummary.count = itemSummary.count + inventoryItem.count
                    end

                    this.itemSummary[itemHash] = itemSummary
                end

                this.emptySlots[inventory.InventorySlotToKey(inventoryName, slot)] = nil

                this.usedSlotCount = this.usedSlotCount + 1
                this.emptySlotCount = this.emptySlotCount - 1
                this.totalItemCount = this.totalItemCount + inventoryItem.count

                this.itemMaxCount = this.itemMaxCount - inventory.DefaultInventoryStackSize + atlasEntry.maxCount
            end
        end

        func.FunctionEnd()
    end

    this._findAllInventories = function()
        local func = this.logger.FunctionStart("_findAllInventories")

        local inventoryNames = {}
        local peripherals = peripheral.getNames()

        local sides = redstone.getSides()
        local flatpak = utils.flattenValuesForSearch(sides)

        for _, peripheralName in pairs(peripherals) do
            if not flatpak.find(peripheralName) then
                local _, peripheralType = peripheral.getType(peripheralName)
                if peripheralType == "inventory" then
                    table.insert(inventoryNames, peripheralName)
                end
            end
        end

        func.FunctionEnd("inventories", #inventoryNames)

        return inventoryNames
    end

    this._scanAllInventories = function()
        local func = this.logger.FunctionStart("_scanAllInventories")

        local inventoryNames = this._findAllInventories()

        func.FunctionStep("_findAllInventories")

        for _, inventoryName in pairs(inventoryNames) do
            this._scanInventory(inventoryName)
        end
        if this.turtle then
            this._scanInventory(this.turtle.getNameLocal())
        end

        func.FunctionEnd("inventoryCount", #inventoryNames)

        return #inventoryNames
    end

    this._scanInventory = function(inventoryName)
        local func = this.logger.FunctionStart("_scanInventory", "inventoryName", inventoryName)

        local inventorySize
        local inventoryList

        local turtleNameLocal = this.turtle.getNameLocal()

        if inventoryName == turtleNameLocal then
            inventorySize = this.turtle.size()
            inventoryList = this.turtle.list()
        else
            inventorySize = peripheral.call(inventoryName, "size")
            inventoryList = peripheral.call(inventoryName, "list")
        end

        if inventorySize then
            this._registerInventory(inventoryName, inventorySize)

            for slotNumber = 1, inventorySize, 1 do
                this._setInventoryItem(inventoryName, slotNumber, nil, nil)
            end

            for slotNumber, itemStub in pairs(inventoryList) do
                local inventoryItem = inventory.InventoryItem(inventoryName, slotNumber, itemStub)
                local atlasEntry = this.getFromAtlas(inventoryItem)
                this._setInventoryItem(inventoryName, slotNumber, inventoryItem, atlasEntry)
            end
        end

        func.FunctionEnd("size", inventorySize)

        return inventorySize
    end

    this.pluginManager.LoadAllPlugins()
    this.pluginManager.OnIRISLoad()

    return this
end

return { NewIRIS = NewIRIS }
