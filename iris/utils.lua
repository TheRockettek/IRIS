local function expect(functionName, inputName, value, expectedType)
    assert(
        type(value) == expectedType,
        ("%s: bad argument %s (expected %s, got %s)"):format(functionName, inputName, expectedType, type(value))
    )
end

local function expectValue(functionName, inputName, value, expectedValue)
    assert(
        value == expectedValue,
        ("%s: bad value %s (expected %s, got %s)"):format(functionName, inputName, tostring(expectedValue),
            tostring(value))
    )
end

local function expectNotValue(functionName, inputName, value, expectedValue)
    assert(
        value ~= expectedValue,
        ("%s: bad value %s (did not expected %s, got %s)"):format(functionName, inputName, tostring(expectedValue),
            tostring(value))
    )
end

local function expectTable(functionName, inputName, value, expectedType)
    expect(functionName, "value", value, "table")
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
            return true, i
        end
    end
    return false, nil
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

local function deepcopy(orig, copies)
    copies = copies or {}
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        if copies[orig] then
            copy = copies[orig]
        else
            copy = {}
            copies[orig] = copy
            for orig_key, orig_value in next, orig, nil do
                copy[deepcopy(orig_key, copies)] = deepcopy(orig_value, copies)
            end
            setmetatable(copy, deepcopy(getmetatable(orig), copies))
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

return {
    expect = expect,
    expectTable = expectTable,
    expectValue = expectValue,
    expectNotValue = expectNotValue,

    tableHasKey = tableHasKey,
    tableHasValue = tableHasValue,

    flattenKeysForSearch = flattenKeysForSearch,
    flattenValuesForSearch = flattenValuesForSearch,

    deepcopy = deepcopy
}
