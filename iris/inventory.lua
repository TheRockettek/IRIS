local utils = require "iris.utils"

DefaultInventorySize = 64

function Inventory(slotCount)
    utils.expect("Inventory.<init>", "slotCount", slotCount, "number")

    local this = {
        _type = "iris:inventory",
        _defaultInventorySlotSize = DefaultInventorySize,
        _peripheralName = nil,

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

    this.SetInventoryItem = function(slot, inventoryItem)
        utils.expect("Inventory.SetInventoryItem", "slot", slot, "number")
        if inventoryItem ~= nil then
            utils.expectTable("Inventory.SetInventoryItem", "inventoryItem", inventoryItem, "iris:inventory_item")
        end

        local currentSlot = this.slots[tostring(slot)]
        local inventoryItemHash = inventoryItem.hash()
        if inventoryItem == nil or inventoryItem.count == 0 then
            if currentSlot ~= nil then
                local currentSlotHash = currentSlot.hash()
                this.emptySlots[tostring(slot)] = true

                local summary = this.itemSummary[currentSlotHash]
                if summary ~= nil then
                    summary = summary - currentSlot.count
                    if summary == 0 then
                        this.itemSummary[currentSlotHash] = nil
                    else
                        this.itemSummary[currentSlotHash] = summary
                    end
                end

                this.usedSlotCount = this.usedSlotCount - 1
                this.emptySlotCount = this.emptySlotCount + 1
                this.totalItemCount = this.totalItemCount - currentSlot.count
                this.itemMaxCount = this.itemMaxCount - currentSlot.maxCount + this._defaultInventorySlotSize
            end

            this.slots[tostring(slot)] = nil
        else
            if currentSlot ~= nil then
                assert(currentSlot.equals(inventoryItem),
                    ("Unexpected slot item. Current item in slot %d is %s, expected %s"):format(slot, currentSlot.hash()
                        ,
                        inventoryItemHash))

                local countChange = currentSlot.count - inventoryItem.count
                if countChange ~= 0 then
                    this.itemSummary[inventoryItemHash] = this.itemSummary[inventoryItemHash] +
                        (currentSlot.count - inventoryItem.count)

                    this.totalItemCount = this.totalItemCount + (currentSlot.count - inventoryItem.count)
                    this.itemMaxCount = this.itemMaxCount + (currentSlot.maxCount - inventoryItem.maxCount)
                end
            else
                this.emptySlots[tostring(slot)] = nil
                this.itemSummary[inventoryItemHash] = (this.itemSummary[inventoryItemHash] or 0) +
                    inventoryItem.count

                this.usedSlotCount = this.usedSlotCount + 1
                this.emptySlotCount = this.emptySlotCount - 1
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

    this.equals = function(inventoryItem)
        utils.expectTable("InventoryItem.Equals", "inventoryItem", inventoryItem, "iris:inventory_item")

        return this.name == inventoryItem.name and
            this.count == inventoryItem.count and
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

    DefaultInventorySize = DefaultInventorySize
}
