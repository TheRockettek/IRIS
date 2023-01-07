local function expect(functionName, inputName, value, expectedType)
    assert(
        type(value) == expectedType,
        ("%s: bad argument %s (expected %s, got %s)"):format(functionName, inputName, expectedType, type(value))
    )
end

local function expectTable(functionName, inputName, value, expectedType)
    expect(functionName, inputName, value, "table")
    expect(functionName, inputName, value._type, "string")
    if value._type ~= expectedType then
        error(("%s: bad argument %s (expected %s, got %s)"):format(functionName, inputName, expectedType, value._type))
    end
end

local function tableHasKey(table, key)
    return table[key] ~= nil
end

local function tableHasValue(table, value)
    for i, k in pairs(table) do
        if k == value then
            return i
        end
    end
    return nil
end

local function flattenKeysForSearch(table)
    assert(type(table) == "table")

    local this = {
        _flat = ""
    }

    for i, _ in pairs(table) do
        this._flat = this._flat .. tostring(i) .. ";"
    end

    this.find = function(key)
        return string.find(this._flat, tostring(key) .. ";") ~= nil
    end

    return this
end

local function flattenValuesForSearch(table)
    assert(type(table) == "table")

    local this = {
        _flat = ""
    }

    for _, k in pairs(table) do
        this._flat = this._flat .. tostring(k) .. ";"
    end

    this.find = function(value)
        return string.find(this._flat, tostring(value) .. ";") ~= nil
    end

    return this
end

return {
    expect = expect,
    expectTable = expectTable,

    tableHasKey = tableHasKey,
    tableHasValue = tableHasValue,

    flattenKeysForSearch = flattenKeysForSearch,
    flattenValuesForSearch = flattenValuesForSearch,
}
