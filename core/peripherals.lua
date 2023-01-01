local function FindAllInventories(iris)
    local inventories = {}
    local peripherals = peripheral.getNames()

    for _, value in pairs(peripherals) do
        local _, peripheralType = peripheral.getType(value)
        if peripheralType == "inventory" then
            table.insert(inventories, value)
        end
    end

    iris.logger.Debug().Str("count", #inventories).Str("total", #peripherals).Msg("Found inventories")

    return inventories
end

return {
    FindAllInventories = FindAllInventories
}
