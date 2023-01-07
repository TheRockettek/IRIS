local utils     = require "utils"
local inventory = require "inventory"
local turtle    = require "turtle"
local core      = require "core"
local logging   = require "libs.logging"

local function createBinaryTestCase(name, func, ...)
    assert(type(name) == "string")
    assert(type(func) == "function")

    local result = func(...)

    -- assert(success, ("FAIL: %s: %s"):format(name, result))
    assert(result, ("FAIL: %s"):format(name))
    print(("PASS: %s: %s"):format(name, result))

    return result
end

local function createTestCase(name, expected, func, ...)
    assert(type(name) == "string")
    assert(type(expected) == "table")
    assert(type(func) == "function")

    local pcallResults = { func(...) }
    -- local success = pcallResults[1]

    local results = pcallResults

    -- assert(success, ("FAIL: %s: %s"):format(name, pcallResults))

    -- local results = {}
    -- for i = 2, #pcallResults, 1 do
    --     table.insert(results, pcallResults[i])
    -- end


    for i, k in pairs(expected) do
        assert(k == results[i],
            ("FAIL: %s:\nExpected:\n%s\n\nGot:\n%s"):format(name,
                textutils.serialize(expected, { compact = false, allow_repetitions = true }),
                textutils.serialize(results, { compact = false, allow_repetitions = true })))
    end

    for i, k in pairs(results) do
        assert(k == expected[i],
            ("FAIL: %s:\nExpected:\n%s\n\nGot:\n%s"):format(name,
                textutils.serialize(expected, { compact = false, allow_repetitions = true }),
                textutils.serialize(results, { compact = false })))
    end

    print(("PASS: %s\n%s"):format(name, textutils.serialize(results, { compact = false, allow_repetitions = true })))

    return table.unpack(results)
end

local getfirstItem = function(table)
    for i, k in pairs(table) do
        return i, k
    end

    error("table is empty")
end

local inventoryName = "iris:test_inventory"
local slotNumber = 16

-- Utilities

local inventorySlotKey = createTestCase("InventorySlotToKey", { inventoryName .. "|" .. slotNumber }, function()
    return inventory.InventorySlotToKey(inventoryName, slotNumber)
end)

createBinaryTestCase("Copy", function()
    local targetTable = {
        A = 1
    }

    local secondaryTable = utils.deepcopy(targetTable)
    targetTable.A = 2

    return secondaryTable.A ~= targetTable.A
end)

createTestCase("KeyToInventorySlot", { inventoryName, slotNumber }, function()
    return inventory.KeyToInventorySlot(inventorySlotKey)
end)

local searchableTable = {}
for i = 1, 1000, 1 do
    searchableTable[tostring(i)] = i
end

createTestCase("TableHasKey", { true, false }, function()
    return utils.tableHasKey(searchableTable, "3"), utils.tableHasKey(searchableTable, "1001")
end)

createTestCase("TableHasValue", { true, false }, function()
    local a, _ = utils.tableHasValue(searchableTable, 3)
    local b, _ = utils.tableHasValue(searchableTable, 1001)

    return a, b
end)

createTestCase("FlattenKeysForSearch", { true, false }, function()
    local flatpak = utils.flattenKeysForSearch(searchableTable)

    return flatpak.find("3"), flatpak.find("1001")
end)

createTestCase("FlattenValuesForSearch", { true, false }, function()
    local flatpak = utils.flattenValuesForSearch(searchableTable)

    return flatpak.find("3"), flatpak.find("1001")
end)

createTestCase("Expects", { true, false, false }, function()
    local a = pcall(utils.expect, "Expects.<testCase>", "inputName", 1, "number")
    local b = pcall(utils.expect, "Expects.<testCase>", "inputName", 1, "string")
    local c = pcall(utils.expect, "Expects.<testCase>", "inputName", nil, "table")

    return a, b, c
end)

createTestCase("ExpectTable", { false, false, true }, function()
    local a = pcall(utils.expectTable, "ExpectTable.<testCase>", "inputName", nil, "iris:test")
    local b = pcall(utils.expectTable, "ExpectTable.<testCase>", "inputName", {}, "iris:test")
    local c = pcall(utils.expectTable, "ExpectTable.<testCase>", "inputName", { _type = "iris:test" }, "iris:test")

    return a, b, c
end)

createTestCase("ExpectValue", { true, false, false }, function()
    local a = pcall(utils.expectValue, "ExpectValue.<testCase>", "inputName", 1, 1)
    local b = pcall(utils.expectValue, "ExpectValue.<testCase>", "inputName", nil, "string")
    local c = pcall(utils.expectValue, "ExpectValue.<testCase>", "inputName", nil, "")

    return a, b, c
end)

createTestCase("ExpectNotValue", { false, true, true }, function()
    local a = pcall(utils.expectNotValue, "ExpectNotValue.<testCase>", "inputName", 1, 1)
    local b = pcall(utils.expectNotValue, "ExpectNotValue.<testCase>", "inputName", nil, "string")
    local c = pcall(utils.expectNotValue, "ExpectNotValue.<testCase>", "inputName", nil, "")

    return a, b, c
end)

-- Turtle dummy

local dummyTurtle = turtle.NewTurtle()

createBinaryTestCase("TurtleGetTurtleName", function()
    return dummyTurtle.getNameLocal()
end)

createBinaryTestCase("TurtleGetCachedTurtleName", function()
    return dummyTurtle._nameLocal
end)

createBinaryTestCase("TurtleList", function()
    return dummyTurtle.list()
end)

-- Inventory and state management

local logger = logging.NewLogger("-", "iris.test.log")
local iris = core.NewIRIS(logger)

createBinaryTestCase("NewIRIS", function()
    return iris
end)

createBinaryTestCase("ScanAllInventories", function()
    return iris.scanInventories()
end)

createBinaryTestCase("ValidateInventories", function()
    for _, inventoryData in pairs(iris.inventories) do
        utils.expectTable("ValidateInventories", "inventoryData", inventoryData, "iris:inventory")

        iris.logger.Debug().Object("inventoryData", inventoryData.Table()).Send()

        utils.expect("ValidateInventories", "_defaultInventorySlotSize", inventoryData._defaultInventorySlotSize,
            "number")
        utils.expect("ValidateInventories", "_peripheralName", inventoryData._peripheralName, "string")

        local usedSlots = 0
        local itemCount = 0
        local maxItemCount = 0

        for _, inventoryItem in pairs(inventoryData.slots) do
            utils.expectTable("ValidateInventories", "inventoryItem", inventoryItem, "iris:inventory_item")

            utils.expect("ValidateInventories", "_inventoryName", inventoryItem._inventoryName, "string")
            utils.expect("ValidateInventories", "_slot", inventoryItem._slot, "number")
            utils.expect("ValidateInventories", "name", inventoryItem.name, "string")
            utils.expect("ValidateInventories", "count", inventoryItem.count, "number")
            utils.expect("ValidateInventories", "displayName", inventoryItem.displayName, "string")
            utils.expect("ValidateInventories", "maxCount", inventoryItem.maxCount, "number")

            utils.expectNotValue("ValidateInventories", "_inventoryName", inventoryItem._inventoryName, "")
            utils.expectNotValue("ValidateInventories", "_slot", inventoryItem._slot, 0)
            utils.expectNotValue("ValidateInventories", "name", inventoryItem.name, "")
            utils.expectNotValue("ValidateInventories", "count", inventoryItem.count, 0)
            utils.expectNotValue("ValidateInventories", "displayName", inventoryItem.displayName, "")
            utils.expectNotValue("ValidateInventories", "maxCount", inventoryItem.maxCount, 0)

            usedSlots = usedSlots + 1
            itemCount = itemCount + inventoryItem.count
            maxItemCount = maxItemCount + inventoryItem.maxCount
        end

        local emptySlots = inventoryData._slotCount - usedSlots
        maxItemCount = maxItemCount + (emptySlots * inventoryData._defaultInventorySlotSize)

        utils.expect("ValidateInventories", "usedSlotCount", inventoryData.usedSlotCount, "number")
        utils.expectValue("ValidateInventories", "usedSlotCount", inventoryData.usedSlotCount, usedSlots)

        utils.expect("ValidateInventories", "emptySlotCount", inventoryData.emptySlotCount, "number")
        utils.expectValue("ValidateInventories", "emptySlotCount", inventoryData.emptySlotCount, emptySlots)

        utils.expectValue("ValidateInventories", "totalSlots", inventoryData.usedSlotCount + inventoryData.emptySlotCount
            , inventoryData._slotCount)

        utils.expect("ValidateInventories", "totalItemCount", inventoryData.totalItemCount, "number")
        utils.expectValue("ValidateInventories", "totalItemCount", inventoryData.totalItemCount, itemCount)

        utils.expect("ValidateInventories", "itemMaxCount", inventoryData.itemMaxCount, "number")
        utils.expectValue("ValidateInventories", "itemMaxCount", inventoryData.itemMaxCount, maxItemCount)
    end

    return true
end)

local testItemHash, testItem = getfirstItem(iris.items)
local isTestItemFull = testItem.count == testItem.maxCount

local testItem = createBinaryTestCase("FindItem", function()
    local candidates, itemsRemaining = iris.findItem(testItemHash, 1, { iris.turtle.getNameLocal() })

    utils.expect("FindItem", "candidates", candidates, "table")
    utils.expectNotValue("FindItem", "candidates", candidates, {})

    utils.expect("FindItem", "itemsRemaining", itemsRemaining, "number")
    utils.expectValue("FindItem", "itemsRemaining", itemsRemaining, 0)

    return candidates[1]
end)

createBinaryTestCase("FindTooManyItems", function()
    local candidates, itemsRemaining = iris.findItem(testItemHash, 1000000, { iris.turtle.getNameLocal() })

    utils.expect("FindItem", "candidates", candidates, "table")
    utils.expectNotValue("FindItem", "candidates", candidates, {})

    utils.expect("FindItem", "itemsRemaining", itemsRemaining, "number")
    utils.expectNotValue("FindItem", "itemsRemaining", itemsRemaining, 0)

    return itemsRemaining
end)

createBinaryTestCase("FindEmptySpace", function()
    local candidates, spaceMissing = iris.findEmptySpace(1, { iris.turtle.getNameLocal() })

    utils.expect("FindItem", "candidates", candidates, "table")
    utils.expectNotValue("FindItem", "candidates", candidates, {})

    utils.expect("FindEmptySpace", "spaceMissing", spaceMissing, "number")
    utils.expectValue("FindEmptySpace", "spaceMissing", spaceMissing, 0)

    return spaceMissing == 0
end)

createBinaryTestCase("FindTooMuchEmptySpace", function()
    local candidates, spaceMissing = iris.findEmptySpace(1000000, { iris.turtle.getNameLocal() })

    utils.expect("FindItem", "candidates", candidates, "table")
    utils.expectNotValue("FindItem", "candidates", candidates, {})

    utils.expect("FindEmptySpace", "spaceMissing", spaceMissing, "number")
    utils.expectNotValue("FindEmptySpace", "spaceMissing", spaceMissing, 0)

    return spaceMissing
end)

createBinaryTestCase("FindSpot", function()
    local candidates, willOverflow, emptySpaces, missingSpaces = iris.findSpot(testItemHash, 1, testItem.maxCount,
        { iris.turtle.getNameLocal() })

    utils.expect("FindItem", "candidates", candidates, "table")
    utils.expectNotValue("FindItem", "candidates", candidates, {})

    utils.expect("FindEmptySpace", "spaceMissing", willOverflow, "boolean")
    if not isTestItemFull then -- If the test item is full, we do not know if space is missing.
        utils.expectValue("FindEmptySpace", "spaceMissing", willOverflow, false)
    end

    utils.expect("FindEmptySpace", "emptySpaces", emptySpaces, "table")
    if isTestItemFull then
        utils.expectNotValue("FindItem", "emptySpaces", emptySpaces, {})
    else
        utils.expectValue("FindItem", "emptySpaces", emptySpaces, {})
    end

    utils.expect("FindEmptySpace", "missingSpaces", missingSpaces, "number")
    utils.expectValue("FindItem", "missingSpaces", missingSpaces, 0)

    return missingSpaces == 0
end)

createBinaryTestCase("FindTooManySpot", function()
    local candidates, willOverflow, emptySpaces, missingSpaces = iris.findSpot(testItemHash, 1000000, testItem.maxCount,
        { iris.turtle.getNameLocal() })

    utils.expect("FindItem", "candidates", candidates, "table")
    utils.expectNotValue("FindItem", "candidates", candidates, {})

    utils.expect("FindEmptySpace", "spaceMissing", willOverflow, "boolean")
    utils.expectValue("FindEmptySpace", "spaceMissing", willOverflow, true)

    utils.expect("FindEmptySpace", "emptySpaces", emptySpaces, "table")
    utils.expectNotValue("FindItem", "emptySpaces", emptySpaces, {})

    utils.expect("FindEmptySpace", "missingSpaces", missingSpaces, "number")
    utils.expectNotValue("FindItem", "missingSpaces", missingSpaces, 0)

    return missingSpaces
end)

createBinaryTestCase("MoveItemToTurtle", function()
    local itemCount = testItem.count - 1
    local itemsTransferred = iris.push(testItem._inventoryName, testItem._slot, iris.turtle._type, 1, itemCount)

    local currentSummary = utils.deepcopy(iris.itemSummary[testItemHash])

    utils.expect("MoveItemToTurtle", "itemsTransferred", itemsTransferred, "number")
    utils.expectValue("MoveItemToTurtle", "itemsTransferred", itemsTransferred, itemCount)

    local newItem = iris.inventories[testItem._inventoryName].slots[tostring(testItem._slot)]
    assert(newItem)

    utils.expectValue("MoveItemToTurtle", "newItemCount", newItem.count, itemCount)

    local newSummary = iris.itemSummary[testItemHash]

    utils.expectNotValue("MoveItemtoTurtle", "summaryCount", newSummary.count, currentSummary.count)
    utils.expectNotValue("MoveItemtoTurtle", "summaryCount", newSummary.count, currentSummary.count - itemsTransferred)

    return itemsTransferred
end)

-- Try push 1 item from inventory to turtle
-- inventories slot has decreased by one
-- used empty slots stays same
-- total item count - 1
-- item max count stays same
-- item summary goes down by one
-- items record has decremented by 1

-- Try push 1 item from turtle to inventory
-- inventories slot has increased by one
-- used empty slots stays same
-- total item count + 1
-- item max count stays same
-- item summary goes up by one
-- items record has incremented by 1

-- Try push count from inventory to turtle
-- inventories slot has been removed
-- used slots -1
-- empty slots + 1
-- total item count - count
-- item max count changes (if not 64)
-- item summary goes down by count
-- items record has decremented by count
-- Try push count from turtle to inventory

-- Try push 2 stacks from inventory to turtle
-- used slots has changed
-- empty slots has changed
-- item summary has changed
-- items record has changed
-- Try push 2 stacks from turtle to inventory
-- used slots stay same after
-- empty slots stay same after
-- item summary is same
-- items record has stayed same
