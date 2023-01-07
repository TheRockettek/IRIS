-- Provides inventory-like interface for turtles
local function NewTurtle()
    local this = {
        _type = "iris:dummy_turtle_peripheral",

        _nameLocal = nil,

        size = function() return 16 end,
        getItemDetail = function(slot) return turtle.getItemDetail(slot, true) end,
        getItemLimit = function(slot) return turtle.getItemCount(slot) + turtle.getItemSpace(slot) end,
    }

    -- Retrieves cached name local or tries to retrieve name local.
    this.getNameLocal = function()
        return this._nameLocal or this._getNameLocal()
    end

    -- Retrieves name local from attached modem.
    this._getNameLocal = function()
        for _, side in pairs(redstone.getSides()) do
            if peripheral.getType(side) == "modem" then
                local nameLocal = peripheral.call(side, "getNameLocal")
                if nameLocal then
                    this._nameLocal = nameLocal

                    return this._nameLocal
                end
            end
        end

        error("Could not locate turtle name. Is there a modem next to the turtle?")
    end

    -- Lists all item details in a turtles inventory
    this.list = function()
        local items = {}

        for i = 1, this.size(), 1 do
            local item = turtle.getItemDetail(i)
            if item then
                table.insert(items, item)
            end
        end

        return items
    end

    -- Pushes an item from a turtle. This cannot push from one turtle to another.
    this.pushItems = function(toName, fromSlot, limit, toSlot)
        return peripheral.call(toName, "pullItems", this.getNameLocal(), fromSlot, limit, toSlot)
    end

    -- Pulls an item into a turtle. This cannot pull from one turtle to another.
    this.pullItems = function(fromName, fromSlot, limit, toSlot)
        return peripheral.call(fromName, "pushItems", this.getNameLocal(), fromSlot, limit, toSlot)
    end

    return this
end

return { NewTurtle = NewTurtle }
