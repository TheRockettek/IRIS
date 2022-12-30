local function TableContains(table, key)
    for i, _ in pairs(table) do
        if i == key then
            return true
        end
    end

    return false
end

local function WillWrap(text)
    return (({term.getCursorPos()})[1] + #text) > ({term.getSize()})[1]
end

return {
    TableContains = TableContains,
    WillWrap = WillWrap
}
