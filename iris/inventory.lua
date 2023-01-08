local utils = require "utils"

DefaultInventoryStackSize = 64

function Inventory(peripheralName, slotCount)
    utils.expect("Inventory.<init>", "slotCount", slotCount, "number")

    local this = {
        _type = "iris:inventory",
        _defaultInventorySlotSize = DefaultInventoryStackSize,
        _peripheralName = peripheralName,
        _slotCount = slotCount,

        slots = {},
        emptySlots = {},
        itemSummary = {},

        usedSlotCount = 0,
        emptySlotCount = 0,
        totalItemCount = 0,
        itemMaxCount = 0,
    }

    this.emptySlotCount = slotCount
    this.itemMaxCount = slotCount * this._defaultInventorySlotSize

    for i = 1, slotCount, 1 do
        this.emptySlots[tostring(i)] = true
    end

    this.Table = function()
        local slotsTable = {}
        for i, k in pairs(this.slots) do
            slotsTable[i] = k.Table()
        end

        local summaryTable = {}
        for i, k in pairs(this.itemSummary) do
            summaryTable[i] = k.Table()
        end

        return {
            _type = this._type,
            _defaultInventorySlotSize = this._defaultInventorySlotSize,
            _peripheralName = this._peripheralName,
            _slotCount = this._slotCount,

            slots = slotsTable,
            emptySlots = this.emptySlots,
            itemSummary = summaryTable,

            usedSlotCount = this.usedSlotCount,
            emptySlotCount = this.emptySlotCount,
            totalItemCount = this.totalItemCount,
            itemMaxCount = this.itemMaxCount
        }
    end

    this.SetInventoryItem = function(slot, inventoryItem)
        utils.expect("Inventory.SetInventoryItem", "slot", slot, "number")
        if inventoryItem ~= nil then
            utils.expectTable("Inventory.SetInventoryItem", "inventoryItem", inventoryItem, "iris:inventory_item")
        end

        local currentSlot = this.slots[tostring(slot)]
        if inventoryItem == nil or inventoryItem.count == 0 then
            if currentSlot ~= nil then
                local currentSlotHash = currentSlot.hash()
                this.emptySlots[tostring(slot)] = true

                local itemSummary = this.itemSummary[currentSlotHash]
                if itemSummary == nil then
                    itemSummary = utils.deepcopy(inventoryItem)
                else
                    itemSummary.count = itemSummary.count - currentSlot.count
                end

                if itemSummary.count == 0 then
                    this.itemSummary[currentSlotHash] = nil
                else
                    this.itemSummary[currentSlotHash] = itemSummary
                end

                this.usedSlotCount = this.usedSlotCount - 1
                this.emptySlotCount = this.emptySlotCount + 1
                this.totalItemCount = this.totalItemCount - currentSlot.count
                this.itemMaxCount = this.itemMaxCount - currentSlot.maxCount + this._defaultInventorySlotSize
            end

            this.slots[tostring(slot)] = nil
        else
            local inventoryItemHash = inventoryItem.hash()
            if currentSlot ~= nil then
                assert(currentSlot.equals(inventoryItem),
                    ("Unexpected slot item. Current item in slot %d is %s, expected %s"):format(slot, currentSlot.hash()
                        ,
                        inventoryItemHash))

                local countChange = inventoryItem.count - currentSlot.count
                if countChange ~= 0 then
                    local itemSummary = this.itemSummary[inventoryItemHash]
                    if itemSummary == nil then
                        itemSummary = utils.deepcopy(inventoryItem)
                    else
                        itemSummary.count = itemSummary.count + inventoryItem.count
                    end

                    this.itemSummary[inventoryItemHash] = itemSummary

                    this.totalItemCount = this.totalItemCount + countChange
                    this.itemMaxCount = this.itemMaxCount + countChange
                end
            else

                local itemSummary = this.itemSummary[inventoryItemHash]
                if itemSummary == nil then
                    itemSummary = utils.deepcopy(inventoryItem)
                else
                    itemSummary.count = itemSummary.count + inventoryItem.count
                end

                this.itemSummary[inventoryItemHash] = itemSummary
                this.emptySlots[tostring(slot)] = nil

                this.usedSlotCount = this.usedSlotCount + 1
                this.emptySlotCount = this.emptySlotCount - 1
                this.totalItemCount = this.totalItemCount + inventoryItem.count
                this.itemMaxCount = this.itemMaxCount - this._defaultInventorySlotSize + inventoryItem.maxCount
            end

            this.slots[tostring(slot)] = inventoryItem
        end
    end

    return this
end

function InventoryItem(inventoryName, slot, item)
    utils.expect("InventoryItem.<init>", "inventoryName", inventoryName, "string")
    utils.expect("InventoryItem.<init>", "slot", slot, "number")
    utils.expect("InventoryItem.<init>", "item", item, "table")

    local this = {
        _type = "iris:inventory_item",
        _inventoryName = inventoryName,
        _slot = slot,

        name = item.name,
        count = item.count,
        displayName = item.displayName,
        maxCount = item.maxCount,
        nbt = item.nbt,
        tags = item.tags,
    }

    this.Table = function()
        return {
            _type = this._type,
            _inventoryName = this._inventoryName,
            _slot = this._slot,

            name = this.name,
            count = this.count,
            displayName = this.displayName,
            maxCount = this.maxCount,
            nbt = this.nbt,
            tags = this.tags
        }
    end

    this.equals = function(inventoryItem)
        utils.expectTable("InventoryItem.Equals", "inventoryItem", inventoryItem, "iris:inventory_item")

        return this.name == inventoryItem.name and
            this.displayName == inventoryItem.displayName and
            this.nbt == inventoryItem.nbt
    end

    this.equalsSlot = function(inventoryItem)
        return this._inventoryName == inventoryItem._inventoryName and this._slot == inventoryItem._slot
    end

    this.hash = function()
        return this.name .. "@" .. (this.nbt or "")
    end

    this.inventoryHash = function()
        return this._inventoryName .. "$" .. this._slot
    end

    return this
end

function InventorySlotToKey(inventoryName, slot)
    return inventoryName .. "|" .. tostring(slot)
end

function KeyToInventorySlot(key)
    local index = key:find("|")
    assert(index, "Invalid key passed \"" .. key .. "\"")

    return tostring(key:sub(0, index - 1)), tonumber(key:sub(index + 1, -1))
end

return {
    Inventory = Inventory,
    InventoryItem = InventoryItem,

    InventorySlotToKey = InventorySlotToKey,
    KeyToInventorySlot = KeyToInventorySlot,

    DefaultInventoryStackSize = DefaultInventoryStackSize
}
